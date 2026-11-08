import java.awt.image.BufferedImage;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageOutputStream;

/**
 * LuckyTether Bonjour client (JPEG/H264 + CTRL + STATUS + EVENT).
 * Protocol: magic 'LTk1', 12-byte BE header, types 1=JPEG 2=CTRL 3=STATUS 4=EVENT 6=H264.
 */
public class TetherClient {
  static final int MAGIC = 0x4C546B31;
  static final int HEADER = 12;
  static final int TYPE_JPEG = 1;
  static final int TYPE_CTRL = 2;
  static final int TYPE_STATUS = 3;
  static final int TYPE_EVENT = 4;
  static final int TYPE_REF = 5; // mac → phone underlay JPEG
  static final int TYPE_H264 = 6; // phone → mac Annex-B access unit
  static final int FIXED_PORT = 7878;
  /** flags for REF: 0 = live loop underlay, 1 = onion commit (clear phone ink) */
  public static final int REF_LOOP = 0;
  public static final int REF_ONION = 1;

  public static final int INK_BEGIN = 0;
  public static final int INK_MOVE = 1;
  public static final int INK_END = 2;

  public volatile boolean running;
  public volatile boolean connected;
  public volatile String status = "Tether off";
  public volatile String phoneStatus = "";
  public volatile float lensPos = -1;
  public volatile float bias = 0;
  public volatile int iso = 0;
  public volatile int locked = 0;
  /** -1 = phone status has no af/ae yet (legacy). */
  public volatile int af = -1;
  public volatile int ae = -1;
  public volatile int cam = 1;
  public volatile String[] cams = new String[0];
  public volatile float tapX = -1;
  public volatile float tapY = -1;
  public volatile int paint = 0;

  public volatile int frameW;
  public volatile int frameH;
  public final AtomicLong frameSeq = new AtomicLong(0);
  private final Object frameLock = new Object();
  private int[] framePixels;
  // Decode on the reader thread (ImageIO/VT must not run on Processing's GL thread).
  private byte[] pendingJpeg;
  private byte[] pendingH264;
  private int pendingH264Key;
  private final Object decodeLock = new Object();
  private Thread decodeWorker;
  private volatile boolean decodeWake;

  private final Object inkLock = new Object();
  private final float[] inkX = new float[2048];
  private final float[] inkY = new float[2048];
  private final int[] inkPh = new int[2048];
  private int inkHead = 0;
  private int inkTail = 0;

  public static final int ACT_SHOOT = 1;
  public static final int ACT_UNDO = 2;
  public static final int ACT_PLAY = 3;
  private final Object actLock = new Object();
  private final int[] actQ = new int[32];
  private int actHead = 0;
  private int actTail = 0;

  private Thread worker;
  private Socket socket;
  private final Object sendLock = new Object();

  private static final Pattern REACH =
    Pattern.compile("can be reached at\\s+([^:\\s]+):(\\d+)", Pattern.CASE_INSENSITIVE);
  // dns-sd lines start with a timestamp, then "Add".
  private static final Pattern BROWSE_ADD =
    Pattern.compile("\\bAdd\\b.*\\s(_luckytether\\._tcp\\.?)\\s+(.+?)\\s*$");
  private static final Pattern ADDR_V4 =
    Pattern.compile("\\bAdd\\s+\\d+\\s+\\d+\\s+\\S+\\s+(\\d+\\.\\d+\\.\\d+\\.\\d+)\\s+\\d+");
  /** iPhone USB / Wi‑Fi Personal Hotspot gateway. */
  private static final String HOTSPOT = "172.20.10.1";

  public void start() {
    if (running) return;
    running = true;
    connected = false;
    status = "Tether: browsing…";
    decodeWake = false;
    decodeWorker = new Thread(this::decodeLoop, "LuckyTetherDecode");
    decodeWorker.setDaemon(true);
    decodeWorker.start();
    worker = new Thread(this::runLoop, "LuckyTether");
    worker.setDaemon(true);
    worker.start();
  }

  public void stop() {
    running = false;
    connected = false;
    status = "Tether off";
    closeSocket();
    synchronized (decodeLock) {
      decodeWake = true;
      decodeLock.notifyAll();
    }
    Thread d = decodeWorker;
    if (d != null) {
      try {
        d.join(800);
      } catch (InterruptedException ignored) {
      }
    }
    decodeWorker = null;
    Thread t = worker;
    if (t != null) {
      try {
        t.join(800);
      } catch (InterruptedException ignored) {
      }
    }
    worker = null;
    if (H264Dec.loaded) H264Dec.reset();
    synchronized (frameLock) {
      pendingJpeg = null;
      pendingH264 = null;
      framePixels = null;
      frameW = 0;
      frameH = 0;
    }
  }

  public int[] copyFrame(int[] into) {
    synchronized (frameLock) {
      if (framePixels == null || frameW < 2 || frameH < 2) return null;
      int n = frameW * frameH;
      if (into == null || into.length != n) into = new int[n];
      System.arraycopy(framePixels, 0, into, 0, n);
      return into;
    }
  }

  private void kickDecode() {
    synchronized (decodeLock) {
      decodeWake = true;
      decodeLock.notifyAll();
    }
  }

  private void decodeLoop() {
    while (running) {
      byte[] jpeg;
      byte[] h264;
      int key;
      synchronized (frameLock) {
        jpeg = pendingJpeg;
        pendingJpeg = null;
        h264 = pendingH264;
        key = pendingH264Key;
        pendingH264 = null;
      }
      if (h264 != null) decodeH264(h264, key);
      else if (jpeg != null) decodeJpeg(jpeg);
      else {
        synchronized (decodeLock) {
          if (!decodeWake) {
            try {
              decodeLock.wait(200);
            } catch (InterruptedException ignored) {
            }
          }
          decodeWake = false;
        }
      }
    }
  }

  public void sendControl(String json) {
    if (json == null || !connected) return;
    sendPacket(TYPE_CTRL, json.getBytes(StandardCharsets.UTF_8));
  }

  /** Loop underlay or onion plate for phone paint. */
  public void sendRefJpeg(byte[] jpeg) {
    sendRefJpeg(jpeg, REF_LOOP);
  }

  public void sendRefJpeg(byte[] jpeg, int flags) {
    if (jpeg == null || jpeg.length == 0 || !connected) return;
    sendPacket(TYPE_REF, jpeg, flags & 0xff);
  }

  /** Fast RGB/ARGB → JPEG in memory (no disk). */
  public static byte[] encodeJpeg(int[] argb, int w, int h, float quality) throws IOException {
    if (argb == null || w < 1 || h < 1) return null;
    BufferedImage bi = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
    bi.setRGB(0, 0, w, h, argb, 0, w);
    Iterator<ImageWriter> writers = ImageIO.getImageWritersByFormatName("jpg");
    if (!writers.hasNext()) writers = ImageIO.getImageWritersByFormatName("jpeg");
    if (!writers.hasNext()) {
      ByteArrayOutputStream bos = new ByteArrayOutputStream();
      ImageIO.write(bi, "jpg", bos);
      return bos.toByteArray();
    }
    ImageWriter writer = writers.next();
    ImageWriteParam param = writer.getDefaultWriteParam();
    if (param.canWriteCompressed()) {
      param.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
      param.setCompressionQuality(Math.max(0.2f, Math.min(0.95f, quality)));
    }
    ByteArrayOutputStream bos = new ByteArrayOutputStream(w * h / 4);
    ImageOutputStream ios = ImageIO.createImageOutputStream(bos);
    writer.setOutput(ios);
    writer.write(null, new IIOImage(bi, null, null), param);
    ios.close();
    writer.dispose();
    return bos.toByteArray();
  }

  private void sendPacket(int type, byte[] payload) {
    sendPacket(type, payload, 0);
  }

  private void sendPacket(int type, byte[] payload, int flags) {
    if (payload == null) return;
    byte[] packet = new byte[HEADER + payload.length];
    packet[0] = (byte) ((MAGIC >> 24) & 0xff);
    packet[1] = (byte) ((MAGIC >> 16) & 0xff);
    packet[2] = (byte) ((MAGIC >> 8) & 0xff);
    packet[3] = (byte) (MAGIC & 0xff);
    packet[4] = (byte) type;
    packet[5] = (byte) (flags & 0xff);
    int len = payload.length;
    packet[8] = (byte) ((len >> 24) & 0xff);
    packet[9] = (byte) ((len >> 16) & 0xff);
    packet[10] = (byte) ((len >> 8) & 0xff);
    packet[11] = (byte) (len & 0xff);
    System.arraycopy(payload, 0, packet, HEADER, payload.length);
    synchronized (sendLock) {
      try {
        if (socket == null || socket.isClosed()) return;
        OutputStream out = socket.getOutputStream();
        out.write(packet);
        // Flush only small control/event packets; large JPEG flush stalls the ink path.
        if (payload.length < 4096) out.flush();
      } catch (IOException e) {
        // reconnect loop will notice
      }
    }
  }

  private void runLoop() {
    while (running) {
      try {
        HostPort hp = resolveService();
        if (hp == null) {
          status = "Tether: waiting for LuckyTether…";
          sleep(1200);
          continue;
        }
        status = "Tether: connecting " + hp.host + ":" + hp.port + "…";
        Socket s = new Socket();
        s.setTcpNoDelay(true);
        s.connect(new InetSocketAddress(hp.host, hp.port), 4000);
        if (!running) {
          try {
            s.close();
          } catch (IOException ignored) {
          }
          break;
        }
        socket = s;
        connected = true;
        status = "Tether: LIVE";
        readConnected(s);
      } catch (Exception e) {
        connected = false;
        status = "Tether: " + shortErr(e);
        closeSocket();
        sleep(1000);
      }
    }
    connected = false;
    closeSocket();
  }

  private void readConnected(Socket s) throws IOException {
    InputStream in = s.getInputStream();
    byte[] buf = new byte[256 * 1024];
    ByteAccum rx = new ByteAccum();
    while (running && !s.isClosed()) {
      int n = in.read(buf);
      if (n < 0) break;
      rx.append(buf, 0, n);
      consume(rx);
    }
    throw new IOException("disconnected");
  }

  private void consume(ByteAccum rx) {
    while (rx.size >= HEADER) {
      byte[] b = rx.data;
      int magic = u32(b, 0);
      if (magic != MAGIC) {
        rx.drop(1);
        continue;
      }
      int type = b[4] & 0xff;
      int flags = b[5] & 0xff;
      int length = u32(b, 8);
      if (length < 0 || length > 8 * 1024 * 1024) {
        rx.clear();
        return;
      }
      int total = HEADER + length;
      if (rx.size < total) return;
      byte[] payload = rx.slice(HEADER, length);
      rx.drop(total);
      if (type == TYPE_JPEG) {
        // Keep only the newest frame; decode on LuckyTetherDecode thread.
        synchronized (frameLock) {
          pendingJpeg = payload;
          pendingH264 = null;
        }
        kickDecode();
      } else if (type == TYPE_H264) {
        synchronized (frameLock) {
          pendingH264 = payload;
          pendingH264Key = flags & 1;
          pendingJpeg = null;
        }
        kickDecode();
      } else if (type == TYPE_STATUS) onStatus(payload);
      // EVENT / paint ignored for now — draw disabled
    }
  }

  /** Drain one paint sample. Returns false if queue empty. out = {x,y,phase}. */
  public boolean pollInk(float[] out) {
    if (out == null || out.length < 3) return false;
    synchronized (inkLock) {
      if (inkHead == inkTail) return false;
      out[0] = inkX[inkTail];
      out[1] = inkY[inkTail];
      out[2] = inkPh[inkTail];
      inkTail = (inkTail + 1) % inkX.length;
      return true;
    }
  }

  public void clearInk() {
    synchronized (inkLock) {
      inkHead = 0;
      inkTail = 0;
    }
  }

  public int pollAction() {
    synchronized (actLock) {
      if (actHead == actTail) return 0;
      int a = actQ[actTail];
      actTail = (actTail + 1) % actQ.length;
      return a;
    }
  }

  private void pushInk(float x, float y, int ph) {
    synchronized (inkLock) {
      // Coalesce consecutive MOVE samples — keeps BEGIN/END and latest point.
      if (ph == INK_MOVE && inkHead != inkTail) {
        int last = (inkHead - 1 + inkX.length) % inkX.length;
        if (inkPh[last] == INK_MOVE) {
          inkX[last] = x;
          inkY[last] = y;
          return;
        }
      }
      int next = (inkHead + 1) % inkX.length;
      if (next == inkTail) {
        // Queue full: drop oldest MOVE if possible, never prefer dropping END.
        if (inkPh[inkTail] == INK_MOVE) {
          inkTail = (inkTail + 1) % inkX.length;
        } else {
          // Drop oldest anyway to make room (BEGIN already consumed relative to END).
          inkTail = (inkTail + 1) % inkX.length;
        }
        next = (inkHead + 1) % inkX.length;
      }
      inkX[inkHead] = x;
      inkY[inkHead] = y;
      inkPh[inkHead] = ph;
      inkHead = next;
    }
  }

  private void pushAction(int a) {
    if (a <= 0) return;
    synchronized (actLock) {
      int next = (actHead + 1) % actQ.length;
      if (next == actTail) actTail = (actTail + 1) % actQ.length;
      actQ[actHead] = a;
      actHead = next;
    }
  }

  private void onEvent(byte[] payload) {
    String json = new String(payload, StandardCharsets.UTF_8);
    if (json.indexOf("\"ink\"") >= 0) {
      float x = fnum(json, "x", -1);
      float y = fnum(json, "y", -1);
      int ph = (int) fnum(json, "ph", 1);
      if (x < 0 || y < 0) return;
      pushInk(constrain01(x), constrain01(y), ph);
      return;
    }
    if (json.indexOf("\"shoot\"") >= 0) pushAction(ACT_SHOOT);
    else if (json.indexOf("\"undo\"") >= 0) pushAction(ACT_UNDO);
    else if (json.indexOf("\"play\"") >= 0) pushAction(ACT_PLAY);
  }

  private static float constrain01(float v) {
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v;
  }

  private void decodeJpeg(byte[] jpeg) {
    if (jpeg == null || jpeg.length < 24) return;
    // Prefer native ImageIO — AWT ImageIO deadlocks inside Processing's JVM.
    if (H264Dec.loaded) {
      if (H264Dec.decodeJpeg(jpeg) != 1) return;
      int w = H264Dec.width();
      int h = H264Dec.height();
      int[] px = H264Dec.copyPixels(null);
      if (px == null || w < 2 || h < 2) return;
      synchronized (frameLock) {
        frameW = w;
        frameH = h;
        framePixels = px;
      }
      frameSeq.incrementAndGet();
      return;
    }
    try {
      BufferedImage bi = ImageIO.read(new ByteArrayInputStream(jpeg));
      if (bi == null) return;
      int w = bi.getWidth();
      int h = bi.getHeight();
      if (w < 2 || h < 2) return;
      int[] px = new int[w * h];
      bi.getRGB(0, 0, w, h, px, 0, w);
      synchronized (frameLock) {
        frameW = w;
        frameH = h;
        framePixels = px;
      }
      frameSeq.incrementAndGet();
    } catch (Exception ignored) {
    }
  }

  private void onStatus(byte[] payload) {
    String json = new String(payload, StandardCharsets.UTF_8);
    phoneStatus = json;
    lensPos = fnum(json, "lens", lensPos);
    bias = fnum(json, "bias", bias);
    iso = (int) fnum(json, "iso", iso);
    locked = (int) fnum(json, "locked", locked);
    if (json.indexOf("\"af\"") >= 0) af = (int) fnum(json, "af", af < 0 ? 1 : af);
    if (json.indexOf("\"ae\"") >= 0) ae = (int) fnum(json, "ae", ae < 0 ? 1 : ae);
    cam = (int) fnum(json, "cam", cam);
    tapX = fnum(json, "tapx", tapX);
    tapY = fnum(json, "tapy", tapY);
    paint = (int) fnum(json, "paint", paint);
    int sw = (int) fnum(json, "w", 0);
    int sh = (int) fnum(json, "h", 0);
    if (sw > 1 && sh > 1 && (frameW < 2 || frameH < 2)) {
      frameW = sw;
      frameH = sh;
    }
    String[] list = parseCams(json);
    if (list != null) cams = list;
  }

  private void decodeH264(byte[] annexB, int keyframe) {
    if (!H264Dec.loaded || annexB == null || annexB.length < 8) return;
    if (H264Dec.decode(annexB, keyframe, frameW, frameH) != 1) return;
    int w = H264Dec.width();
    int h = H264Dec.height();
    int[] px = H264Dec.copyPixels(null);
    if (px == null || w < 2 || h < 2) return;
    synchronized (frameLock) {
      frameW = w;
      frameH = h;
      framePixels = px;
    }
    frameSeq.incrementAndGet();
  }

  private static String[] parseCams(String json) {
    int i = json.indexOf("\"cams\"");
    if (i < 0) return null;
    int a = json.indexOf('[', i);
    int b = json.indexOf(']', a);
    if (a < 0 || b < 0) return null;
    String body = json.substring(a + 1, b).trim();
    if (body.length() == 0) return new String[0];
    List<String> out = new ArrayList<String>();
    Matcher m = Pattern.compile("\"([^\"]+)\"").matcher(body);
    while (m.find()) out.add(m.group(1));
    return out.toArray(new String[0]);
  }

  private static float fnum(String json, String key, float fallback) {
    Pattern p = Pattern.compile("\"" + key + "\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)");
    Matcher m = p.matcher(json);
    if (!m.find()) return fallback;
    try {
      return Float.parseFloat(m.group(1));
    } catch (NumberFormatException e) {
      return fallback;
    }
  }

  private HostPort resolveService() {
    // USB hotspot does not depend on Bonjour. The phone listens on its gateway address.
    if (tryReachable(HOTSPOT, FIXED_PORT, 400)) return new HostPort(HOTSPOT, FIXED_PORT);
    List<String> names = browseNames(2000);
    if (names.isEmpty()) names.add("LuckyTether");
    for (String name : names) {
      HostPort hp = lookup(name, 2000);
      if (hp == null) continue;
      String host = stripDot(hp.host);
      int port = hp.port > 0 ? hp.port : FIXED_PORT;
      List<String> ips = resolveV4(host, 1500);
      if (ips.isEmpty()) ips.add(host);
      for (String ip : ips) {
        if (tryReachable(ip, port, 400)) return new HostPort(ip, port);
        if (port != FIXED_PORT && tryReachable(ip, FIXED_PORT, 400)) {
          return new HostPort(ip, FIXED_PORT);
        }
      }
    }
    return null;
  }

  private static String stripDot(String host) {
    if (host == null) return "";
    String h = host.trim();
    while (h.endsWith(".")) h = h.substring(0, h.length() - 1);
    return h;
  }

  /** Numeric IPv4 for a .local name — Java's resolver often misses the USB address. */
  private List<String> resolveV4(String host, int timeoutMs) {
    List<String> ips = new ArrayList<String>();
    if (host == null || host.length() == 0) return ips;
    if (host.matches("\\d+\\.\\d+\\.\\d+\\.\\d+")) {
      ips.add(host);
      return ips;
    }
    Process p = null;
    try {
      p = new ProcessBuilder("dns-sd", "-G", "v4", host)
        .redirectErrorStream(true).start();
      BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8));
      long deadline = System.currentTimeMillis() + timeoutMs;
      while (System.currentTimeMillis() < deadline && running) {
        if (br.ready()) {
          String line = br.readLine();
          if (line == null) break;
          Matcher m = ADDR_V4.matcher(line);
          if (m.find()) {
            String ip = m.group(1);
            if (!ips.contains(ip)) ips.add(ip);
          }
        } else {
          sleep(40);
        }
      }
    } catch (Exception ignored) {
    } finally {
      kill(p);
    }
    return ips;
  }

  private boolean tryReachable(String host, int port, int timeoutMs) {
    try (Socket s = new Socket()) {
      s.connect(new InetSocketAddress(host, port), timeoutMs);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  private List<String> browseNames(int timeoutMs) {
    List<String> names = new ArrayList<String>();
    Process p = null;
    try {
      p = new ProcessBuilder("dns-sd", "-B", "_luckytether._tcp", "local.")
        .redirectErrorStream(true).start();
      BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8));
      long deadline = System.currentTimeMillis() + timeoutMs;
      while (System.currentTimeMillis() < deadline && running) {
        if (br.ready()) {
          String line = br.readLine();
          if (line == null) break;
          Matcher m = BROWSE_ADD.matcher(line);
          if (m.find()) {
            String n = m.group(2).trim();
            if (n.length() > 0 && !names.contains(n)) names.add(n);
          }
        } else {
          sleep(40);
        }
      }
    } catch (Exception ignored) {
    } finally {
      kill(p);
    }
    return names;
  }

  private HostPort lookup(String name, int timeoutMs) {
    Process p = null;
    try {
      p = new ProcessBuilder("dns-sd", "-L", name, "_luckytether._tcp", "local.")
        .redirectErrorStream(true).start();
      BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8));
      long deadline = System.currentTimeMillis() + timeoutMs;
      while (System.currentTimeMillis() < deadline && running) {
        if (br.ready()) {
          String line = br.readLine();
          if (line == null) break;
          Matcher m = REACH.matcher(line);
          if (m.find()) {
            return new HostPort(m.group(1), Integer.parseInt(m.group(2)));
          }
        } else {
          sleep(40);
        }
      }
    } catch (Exception ignored) {
    } finally {
      kill(p);
    }
    return null;
  }

  private void closeSocket() {
    synchronized (sendLock) {
      if (socket != null) {
        try {
          socket.close();
        } catch (IOException ignored) {
        }
        socket = null;
      }
    }
  }

  private static void kill(Process p) {
    if (p == null) return;
    p.destroy();
    try {
      if (!p.waitFor(200, java.util.concurrent.TimeUnit.MILLISECONDS)) p.destroyForcibly();
    } catch (Exception e) {
      try {
        p.destroyForcibly();
      } catch (Exception ignored) {
      }
    }
  }

  private static void sleep(long ms) {
    try {
      Thread.sleep(ms);
    } catch (InterruptedException ignored) {
    }
  }

  private static int u32(byte[] b, int off) {
    return ((b[off] & 0xff) << 24) | ((b[off + 1] & 0xff) << 16)
      | ((b[off + 2] & 0xff) << 8) | (b[off + 3] & 0xff);
  }

  private static String shortErr(Exception e) {
    String m = e.getMessage();
    if (m == null || m.length() == 0) m = e.getClass().getSimpleName();
    if (m.length() > 48) m = m.substring(0, 48);
    return m;
  }

  private static class HostPort {
    final String host;
    final int port;
    HostPort(String host, int port) {
      this.host = host;
      this.port = port;
    }
  }

  private static class ByteAccum {
    byte[] data = new byte[65536];
    int size;

    void append(byte[] src, int off, int len) {
      ensure(size + len);
      System.arraycopy(src, off, data, size, len);
      size += len;
    }

    void ensure(int need) {
      if (need <= data.length) return;
      int n = Math.max(data.length * 2, need);
      byte[] next = new byte[n];
      System.arraycopy(data, 0, next, 0, size);
      data = next;
    }

    void drop(int n) {
      if (n >= size) {
        size = 0;
        return;
      }
      System.arraycopy(data, n, data, 0, size - n);
      size -= n;
    }

    void clear() {
      size = 0;
    }

    byte[] slice(int off, int len) {
      byte[] out = new byte[len];
      System.arraycopy(data, off, out, 0, len);
      return out;
    }
  }
}
