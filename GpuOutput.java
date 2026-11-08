import processing.core.PImage;
import processing.opengl.PGraphicsOpenGL;
import processing.opengl.PSurfaceJOGL;
import processing.opengl.Texture;

import com.jogamp.nativewindow.util.RectangleImmutable;
import com.jogamp.newt.MonitorDevice;
import com.jogamp.newt.event.KeyEvent;
import com.jogamp.newt.event.KeyListener;
import com.jogamp.newt.event.WindowAdapter;
import com.jogamp.newt.event.WindowEvent;
import com.jogamp.newt.opengl.GLWindow;
import com.jogamp.opengl.GL;
import com.jogamp.opengl.GL2ES2;
import com.jogamp.opengl.GLCapabilitiesImmutable;
import com.jogamp.opengl.GLContext;
import com.jogamp.opengl.GLProfile;

import java.awt.GraphicsDevice;
import java.awt.GraphicsEnvironment;
import java.awt.Rectangle;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.List;

/**
 * Low-latency external program out.
 * Second NEWT window sharing the main Processing GL context — no second
 * FPSAnimator (that deadlocks on macOS). Presented from the main draw thread.
 */
public class GpuOutput {
  LuckyLoop app;
  String deviceId = "";
  GLWindow window;
  GLWindow mainWindow;
  Rectangle bounds = new Rectangle(0, 0, 1280, 720);
  boolean ready;
  boolean placing;
  public boolean dead;

  int programId;
  int locPos = -1;
  int locUV = -1;
  int locTex = -1;
  int vbo;
  boolean shaderReady;
  boolean shaderFailed;
  boolean placedOk;
  int presentCount;

  public void open(LuckyLoop app, String deviceId, Rectangle bounds) {
    close();
    this.app = app;
    this.deviceId = deviceId == null ? "" : deviceId;
    this.bounds = bounds != null ? new Rectangle(bounds) : new Rectangle(0, 0, 1280, 720);
    this.dead = false;
    this.ready = false;
    this.shaderReady = false;
    this.shaderFailed = false;
    this.placedOk = false;
    this.programId = 0;
    this.vbo = 0;
    this.presentCount = 0;

    Object nativeObj = app.getSurface() != null ? app.getSurface().getNative() : null;
    if (!(nativeObj instanceof GLWindow)) {
      throw new RuntimeException("GpuOutput needs a GL main surface (P2D/P3D)");
    }
    mainWindow = (GLWindow) nativeObj;

    // Pause the main FPSAnimator while creating a shared GL window — otherwise
    // JOGL blocks forever on the animator lock (macOS).
    PSurfaceJOGL surf = null;
    try {
      if (app.getSurface() instanceof PSurfaceJOGL) {
        surf = (PSurfaceJOGL) app.getSurface();
        surf.pauseThread();
      }
    } catch (Throwable t) {
      System.err.println("GpuOutput pause: " + t.getMessage());
    }

    try {
      GLCapabilitiesImmutable caps = mainWindow.getChosenGLCapabilities();
      if (caps == null) {
        caps = new com.jogamp.opengl.GLCapabilities(GLProfile.getDefault());
      }
      window = GLWindow.create(caps);
      window.setSharedAutoDrawable(mainWindow);
      window.setUndecorated(true);
      window.setAlwaysOnTop(true);
      window.setTitle("LuckyLoop · Out");
      // Start tiny on primary; placeOnDevice moves/FS onto the external.
      window.setSize(64, 64);
      window.setPosition(0, 0);

      window.addKeyListener(new KeyListener() {
        public void keyPressed(KeyEvent e) {
          if (e.getKeyCode() == KeyEvent.VK_ESCAPE) {
            dead = true;
            if (GpuOutput.this.app != null) GpuOutput.this.app.beamerClosedFromWindow();
          }
        }
        public void keyReleased(KeyEvent e) {}
      });
      window.addWindowListener(new WindowAdapter() {
        public void windowDestroyed(WindowEvent e) {
          if (placing) return;
          dead = true;
          ready = false;
          if (GpuOutput.this.app != null) GpuOutput.this.app.beamerClosedFromWindow();
        }
      });

      placing = true;
      try {
        window.setVisible(true);
        placeOnDevice();
      } finally {
        placing = false;
      }
      ready = true;
      System.err.println("GpuOutput open " + this.deviceId
        + " target=" + bounds.x + "," + bounds.y + " " + bounds.width + "x" + bounds.height
        + " win=" + window.getX() + "," + window.getY()
        + " " + window.getWidth() + "x" + window.getHeight()
        + " fs=" + window.isFullscreen());
    } finally {
      if (surf != null) {
        try { surf.resumeThread(); } catch (Throwable ignored) {}
      }
    }
  }

  void placeOnDevice() {
    if (window == null) return;
    GraphicsDevice gd = deviceById(deviceId);
    if (gd != null) {
      bounds = new Rectangle(gd.getDefaultConfiguration().getBounds());
    }
    try {
      window.setUndecorated(true);
      window.setAlwaysOnTop(true);

      // Prefer NEWT monitor fullscreen — setPosition with AWT coords often lands
      // wrong on macOS multi-monitor (e.g. y clipped toward the primary).
      MonitorDevice mon = findMonitor(bounds);
      if (mon != null) {
        ArrayList<MonitorDevice> one = new ArrayList<MonitorDevice>(1);
        one.add(mon);
        if (window.setFullscreen(one)) {
          placedOk = true;
          System.err.println("GpuOutput FS monitor id=" + mon.getId());
          return;
        }
      }

      window.setFullscreen(false);
      window.setPosition(bounds.x, bounds.y);
      window.setSize(Math.max(64, bounds.width), Math.max(64, bounds.height));
      placedOk = Math.abs(window.getX() - bounds.x) < 32
        && Math.abs(window.getY() - bounds.y) < 32;
      System.err.println("GpuOutput place fallback @"
        + window.getX() + "," + window.getY()
        + " want " + bounds.x + "," + bounds.y
        + " ok=" + placedOk);
    } catch (Throwable t) {
      System.err.println("GpuOutput place: " + t.getMessage());
      placedOk = false;
    }
  }

  MonitorDevice findMonitor(Rectangle target) {
    try {
      List<MonitorDevice> all = window.getScreen().getMonitorDevices();
      MonitorDevice best = null;
      int bestArea = -1;
      for (int i = 0; i < all.size(); i++) {
        MonitorDevice m = all.get(i);
        if (m.isPrimary()) continue;
        RectangleImmutable vp = m.getViewportInWindowUnits();
        Rectangle mb = new Rectangle(vp.getX(), vp.getY(), vp.getWidth(), vp.getHeight());
        int area = overlapArea(target, mb);
        if (area > bestArea) {
          bestArea = area;
          best = m;
        }
      }
      if (best != null && bestArea > 0) return best;
      // Fallback: any non-primary, or largest overlap including primary.
      best = null;
      bestArea = -1;
      for (int i = 0; i < all.size(); i++) {
        MonitorDevice m = all.get(i);
        RectangleImmutable vp = m.getViewportInWindowUnits();
        Rectangle mb = new Rectangle(vp.getX(), vp.getY(), vp.getWidth(), vp.getHeight());
        int area = overlapArea(target, mb);
        if (area > bestArea) {
          bestArea = area;
          best = m;
        }
      }
      return bestArea > 0 ? best : null;
    } catch (Throwable t) {
      System.err.println("GpuOutput findMonitor: " + t.getMessage());
      return null;
    }
  }

  static int overlapArea(Rectangle a, Rectangle b) {
    int x0 = Math.max(a.x, b.x);
    int y0 = Math.max(a.y, b.y);
    int x1 = Math.min(a.x + a.width, b.x + b.width);
    int y1 = Math.min(a.y + a.height, b.y + b.height);
    int w = x1 - x0;
    int h = y1 - y0;
    return (w > 0 && h > 0) ? w * h : 0;
  }

  /** Blit src to the external window. Must run on the main animation thread. */
  public void present(PImage src) {
    present(src, null);
  }

  /**
   * Blit src, then an optional upper-left overlay as a second quad.
   * src itself is not copied or modified.
   */
  public void present(PImage src, PImage overlay) {
    if (dead || !ready || window == null || app == null || src == null) return;
    if (src.width < 2 || src.height < 2) return;
    if (!(app.g instanceof PGraphicsOpenGL)) return;
    // Retry placement a few frames if the window did not land on the external.
    if (!placedOk && presentCount < 10) {
      placing = true;
      try { placeOnDevice(); } finally { placing = false; }
    }

    PGraphicsOpenGL pg = (PGraphicsOpenGL) app.g;
    Texture tex;
    Texture overlayTex = null;
    try {
      tex = pg.getTexture(src);
      if (overlay != null && overlay != src && overlay.width > 2 && overlay.height > 2) {
        overlayTex = pg.getTexture(overlay);
        if (overlayTex != null && overlayTex.glName <= 0) overlayTex = null;
      }
    } catch (Throwable t) {
      return;
    }
    if (tex == null || tex.glName <= 0) return;

    GLContext mainCtx = mainWindow.getContext();
    if (mainCtx == null) return;

    // Ensure FBO writes from the main context are visible to the shared out context.
    try {
      GL glMain = mainWindow.getGL();
      if (glMain != null) glMain.glFlush();
    } catch (Throwable ignored) {}

    boolean switched = false;
    try {
      window.getContext().makeCurrent();
      switched = true;
    } catch (Throwable t) {
      System.err.println("GpuOutput makeCurrent: " + t.getMessage());
      return;
    }

    try {
      GL2ES2 gl = window.getGL().getGL2ES2();
      int vw = Math.max(1, window.getSurfaceWidth());
      int vh = Math.max(1, window.getSurfaceHeight());
      gl.glViewport(0, 0, vw, vh);
      gl.glDisable(GL.GL_DEPTH_TEST);
      gl.glDisable(GL.GL_CULL_FACE);
      gl.glDisable(GL.GL_BLEND);
      gl.glClearColor(0, 0, 0, 1);
      gl.glClear(GL.GL_COLOR_BUFFER_BIT);

      if (!ensureShader(gl)) return;

      // Integer pixel letterbox — subpixel quads + linear filtering shift mirror seams.
      float aspect = src.width / (float) src.height;
      int dw = vw;
      int dh = Math.round(dw / aspect);
      if (dh > vh) {
        dh = vh;
        dw = Math.round(dh * aspect);
      }
      if (dw > vw) dw = vw;
      if (dh > vh) dh = vh;
      int x0 = (vw - dw) / 2;
      int y0 = (vh - dh) / 2;
      int x1 = x0 + dw;
      int y1 = y0 + dh;

      // 1:1 pixel mapping → nearest (linear filtering shifts sharp mirror folds).
      boolean pixelExact = dw == vw && dh == vh
        && src.width == vw && src.height == vh;
      drawPresentQuad(gl, tex, vw, vh, x0, y0, x1, y1, pixelExact);

      if (overlayTex != null) {
        int margin = Math.max(8, (x1 - x0) / 90);
        int pw = Math.max(24, Math.round((x1 - x0) * 0.22f));
        int ph = Math.max(14, Math.round(pw * (overlay.height / (float) Math.max(1, overlay.width))));
        int ox0 = x0 + margin;
        int oy0 = y0 + margin;
        int ox1 = Math.min(x1 - 2, ox0 + pw);
        int oy1 = Math.min(y1 - 2, oy0 + ph);
        if (ox1 > ox0 + 8 && oy1 > oy0 + 8) {
          gl.glEnable(GL.GL_BLEND);
          gl.glBlendFunc(GL.GL_ONE, GL.GL_ONE_MINUS_SRC_ALPHA);
          drawPresentQuad(gl, overlayTex, vw, vh, ox0, oy0, ox1, oy1, false);
          gl.glDisable(GL.GL_BLEND);
        }
      }

      window.swapBuffers();
      presentCount++;
      if (presentCount == 1) {
        System.err.println("GpuOutput presenting " + src.width + "x" + src.height
          + " → " + window.getWidth() + "x" + window.getHeight()
          + " invY=" + tex.invertedY() + " invX=" + tex.invertedX());
      }
    } catch (Throwable t) {
      System.err.println("GpuOutput present: " + t.getMessage());
    } finally {
      if (switched) {
        try {
          // Release out context first — otherwise main makeCurrent can leave GL 1282.
          window.getContext().release();
        } catch (Throwable ignored) {}
        try {
          mainCtx.makeCurrent();
        } catch (Throwable t) {
          System.err.println("GpuOutput restore main: " + t.getMessage());
        }
      }
    }
  }

  /** One textured quad in window pixels. (x0,y0) is the top-left. */
  void drawPresentQuad(GL2ES2 gl, Texture tex, int vw, int vh,
      int x0, int y0, int x1, int y1, boolean pixelExact) {
    float cx0 = x0 / (float) vw * 2f - 1f;
    float cx1 = x1 / (float) vw * 2f - 1f;
    float cy0 = 1f - y1 / (float) vh * 2f;
    float cy1 = 1f - y0 / (float) vh * 2f;
    float uL = tex.invertedX() ? tex.maxTexcoordU() : 0;
    float uR = tex.invertedX() ? 0 : tex.maxTexcoordU();
    float vTop = tex.invertedY() ? tex.maxTexcoordV() : 0;
    float vBot = tex.invertedY() ? 0 : tex.maxTexcoordV();
    float[] data = {
      cx0, cy0, uL, vBot,
      cx1, cy0, uR, vBot,
      cx0, cy1, uL, vTop,
      cx1, cy1, uR, vTop
    };

    gl.glUseProgram(programId);
    gl.glActiveTexture(GL.GL_TEXTURE0);
    gl.glBindTexture(tex.glTarget, tex.glName);
    int prevMag = -1, prevMin = -1;
    if (pixelExact) {
      int[] got = new int[1];
      gl.glGetTexParameteriv(tex.glTarget, GL.GL_TEXTURE_MAG_FILTER, got, 0);
      prevMag = got[0];
      gl.glGetTexParameteriv(tex.glTarget, GL.GL_TEXTURE_MIN_FILTER, got, 0);
      prevMin = got[0];
      gl.glTexParameteri(tex.glTarget, GL.GL_TEXTURE_MAG_FILTER, GL.GL_NEAREST);
      gl.glTexParameteri(tex.glTarget, GL.GL_TEXTURE_MIN_FILTER, GL.GL_NEAREST);
    }
    if (locTex >= 0) gl.glUniform1i(locTex, 0);

    FloatBuffer buf = FloatBuffer.allocate(data.length);
    buf.put(data);
    buf.rewind();
    gl.glBindBuffer(GL.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(GL.GL_ARRAY_BUFFER, data.length * 4L, buf, GL.GL_DYNAMIC_DRAW);
    gl.glEnableVertexAttribArray(locPos);
    gl.glVertexAttribPointer(locPos, 2, GL.GL_FLOAT, false, 16, 0);
    gl.glEnableVertexAttribArray(locUV);
    gl.glVertexAttribPointer(locUV, 2, GL.GL_FLOAT, false, 16, 8);
    gl.glDrawArrays(GL.GL_TRIANGLE_STRIP, 0, 4);
    gl.glDisableVertexAttribArray(locPos);
    gl.glDisableVertexAttribArray(locUV);
    gl.glBindBuffer(GL.GL_ARRAY_BUFFER, 0);
    if (pixelExact && prevMag >= 0) {
      gl.glTexParameteri(tex.glTarget, GL.GL_TEXTURE_MAG_FILTER, prevMag);
      gl.glTexParameteri(tex.glTarget, GL.GL_TEXTURE_MIN_FILTER, prevMin);
    }
    gl.glBindTexture(tex.glTarget, 0);
    gl.glUseProgram(0);
  }

  boolean ensureShader(GL2ES2 gl) {
    if (shaderReady) return true;
    if (shaderFailed) return false;
    try {
      // Processing on macOS uses a GL3 core profile — need GLSL 150.
      String vert =
        "#version 150\n"
          + "in vec2 aPos;\n"
          + "in vec2 aUV;\n"
          + "out vec2 vUV;\n"
          + "void main(){\n"
          + "  vUV = aUV;\n"
          + "  gl_Position = vec4(aPos, 0.0, 1.0);\n"
          + "}\n";
      String frag =
        "#version 150\n"
          + "uniform sampler2D uTex;\n"
          + "in vec2 vUV;\n"
          + "out vec4 fragColor;\n"
          + "void main(){\n"
          + "  fragColor = texture(uTex, vUV);\n"
          + "}\n";

      int vs = compile(gl, GL2ES2.GL_VERTEX_SHADER, vert);
      int fs = compile(gl, GL2ES2.GL_FRAGMENT_SHADER, frag);
      programId = gl.glCreateProgram();
      gl.glAttachShader(programId, vs);
      gl.glAttachShader(programId, fs);
      gl.glLinkProgram(programId);
      int[] ok = new int[1];
      gl.glGetProgramiv(programId, GL2ES2.GL_LINK_STATUS, ok, 0);
      if (ok[0] == 0) {
        byte[] log = new byte[512];
        int[] len = new int[1];
        gl.glGetProgramInfoLog(programId, 512, len, 0, log, 0);
        throw new RuntimeException(new String(log, 0, Math.max(0, len[0])));
      }
      gl.glDeleteShader(vs);
      gl.glDeleteShader(fs);

      locPos = gl.glGetAttribLocation(programId, "aPos");
      locUV = gl.glGetAttribLocation(programId, "aUV");
      locTex = gl.glGetUniformLocation(programId, "uTex");

      int[] buf = new int[1];
      gl.glGenBuffers(1, buf, 0);
      vbo = buf[0];
      shaderReady = true;
      System.err.println("GpuOutput shader ready");
      return true;
    } catch (Throwable t) {
      System.err.println("GpuOutput shader: " + t.getMessage());
      shaderReady = false;
      shaderFailed = true;
      return false;
    }
  }

  static int compile(GL2ES2 gl, int type, String src) {
    int id = gl.glCreateShader(type);
    gl.glShaderSource(id, 1, new String[] { src }, null);
    gl.glCompileShader(id);
    int[] ok = new int[1];
    gl.glGetShaderiv(id, GL2ES2.GL_COMPILE_STATUS, ok, 0);
    if (ok[0] == 0) {
      byte[] log = new byte[512];
      int[] len = new int[1];
      gl.glGetShaderInfoLog(id, 512, len, 0, log, 0);
      throw new RuntimeException(new String(log, 0, Math.max(0, len[0])));
    }
    return id;
  }

  public void close() {
    ready = false;
    dead = true;
    PSurfaceJOGL surf = null;
    try {
      if (app != null && app.getSurface() instanceof PSurfaceJOGL) {
        surf = (PSurfaceJOGL) app.getSurface();
        surf.pauseThread();
      }
    } catch (Throwable ignored) {}
    try {
      if (window != null) {
        final GLWindow w = window;
        window = null;
        try { w.setFullscreen(false); } catch (Throwable ignored) {}
        try { w.setVisible(false); } catch (Throwable ignored) {}
        try { w.destroy(); } catch (Throwable ignored) {}
      }
    } finally {
      if (surf != null) {
        try { surf.resumeThread(); } catch (Throwable ignored) {}
      }
    }
    shaderReady = false;
    programId = 0;
    vbo = 0;
    mainWindow = null;
    app = null;
  }

  public boolean isAlive() {
    return ready && !dead && window != null && window.isVisible();
  }

  public static GraphicsDevice primaryDevice() {
    try {
      return GraphicsEnvironment.getLocalGraphicsEnvironment().getDefaultScreenDevice();
    } catch (Throwable t) {
      return null;
    }
  }

  public static GraphicsDevice[] allDevices() {
    try {
      GraphicsDevice[] ds = GraphicsEnvironment.getLocalGraphicsEnvironment().getScreenDevices();
      return ds != null ? ds : new GraphicsDevice[0];
    } catch (Throwable t) {
      return new GraphicsDevice[0];
    }
  }

  public static GraphicsDevice deviceById(String id) {
    if (id == null || id.length() == 0) return null;
    GraphicsDevice[] ds = allDevices();
    for (int i = 0; i < ds.length; i++) {
      if (id.equals(ds[i].getIDstring())) return ds[i];
    }
    return null;
  }

  public static boolean isPrimary(GraphicsDevice gd) {
    if (gd == null) return false;
    GraphicsDevice primary = primaryDevice();
    if (primary == null) return false;
    return gd == primary || gd.getIDstring().equals(primary.getIDstring());
  }
}
