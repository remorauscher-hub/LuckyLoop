import java.awt.image.BufferedImage;
import java.io.BufferedReader;
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
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageOutputStream;

/**
 * LuckyPad Bonjour client — ink + preview JPEG (no camera).
 * Protocol: magic 'LPk1', 12-byte BE header,
 * types 2=CTRL 3=STATUS 4=EVENT 5=REF (JPEG preview).
 */
public class PadClient {
  static final int MAGIC = 0x4C506B31; // 'LPk1'
  static final int HEADER = 12;
  static final int TYPE_CTRL = 2;
  static final int TYPE_STATUS = 3;
  static final int TYPE_EVENT = 4;
  static final int TYPE_REF = 5; // mac → pad JPEG preview (live/loop+ink)
  static final int FIXED_PORT = 7879;
  static final int MAX_PACKET = 4 * 1024 * 1024;

  public static final int INK_BEGIN = 0;
  public static final int INK_MOVE = 1;
  public static final int INK_END = 2;

  public static final int ACT_SHOOT = 1;
  public static final int ACT_UNDO = 2;
  public static final int ACT_PLAY = 3;
  public static final int ACT_COLOR = 4;
  public static final int ACT_CLEAR = 5;
  public static final int ACT_ONION = 6;
  public static final int ACT_BAKE = 7;
  public static final int ACT_TOOL = 8;
  public static final int ACT_BRUSH = 9;
  /** Desired onion state from pad (-1 = toggle, 0/1 = set). */
  public volatile int padOnionWant = -1;
  /** Draw tool index from pad (0…DRAW_ROUNDRECT). */
  public volatile int padToolWant = -1;
  /** Brush size from pad (1…DRAW_BRUSH_MAX). */
  public volatile float padBrushWant = -1;

  public volatile boolean running;
  public volatile boolean connected;
  public volatile String status = "LuckyPad off";
  public volatile int canvasW = 1920;
  public volatile int canvasH = 1080;
  /** Last color picked on the iPad (RGB 0xRRGGBB), or -1. */
  public volatile int padColorRgb = -1;
  /** Swatch index from pad (−1 if omitted). */
  public volatile int padColorIdx = -1;

  private final Object inkLock = new Object();
  private final float[] inkX = new float[2048];
  private final float[] inkY = new float[2048];
  private final int[] inkPh = new int[2048];
  private int inkHead = 0;
  private int inkTail = 0;

  private final Object actLock = new Object();
  private final int[] actQ = new int[32];
  private int actHead = 0;
  private int actTail = 0;

  private Thread worker;
  private Socket socket;
  private final Object sendLock = new Object();

  private static final Pattern REACH =
    Pattern.compile("can be reached at\\s+([^:\\s]+):(\\d+)", Pattern.CASE_INSENSITIVE);
  private static final Pattern BROWSE_ADD =
    Pattern.compile("^\\s*Add\\b.*\\s(_luckypad\\._tcp\\.)\\s+(.+)\\s*$");

  public void start() {
    if (running) return;
    running = true;
    connected = false;
    status = "LuckyPad: browsing…";
    worker = new Thread(this::runLoop, "LuckyPad");
    worker.setDaemon(true);
    worker.start();
  }

  public void stop() {
    running = false;
    connected = false;
    status = "LuckyPad off";
    closeSocket();
    Thread t = worker;
    if (t != null) {
      try {
        t.join(800);
      } catch (InterruptedException ignored) {
      }
    }
    worker = null;
  }

  public void sendControl(String json) {
    if (json == null || !connected) return;
    sendPacket(TYPE_CTRL, json.getBytes(StandardCharsets.UTF_8), 0, true);
  }

  /** Full preview JPEG for the iPad (live/loop + ink). Latest-wins on the wire. */
  public void sendPreviewJpeg(byte[] jpeg) {
    if (jpeg == null || jpeg.length == 0 || !connected) return;
    sendPacket(TYPE_REF, jpeg, 0, false);
  }

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
      param.setCompressionQuality(Math.max(0.2f, Math.min(0.92f, quality)));
    }
    ByteArrayOutputStream bos = new ByteArrayOutputStream(w * h / 4);
    ImageOutputStream ios = ImageIO.createImageOutputStream(bos);
    writer.setOutput(ios);
    writer.write(null, new IIOImage(bi, null, null), param);
    ios.close();
    writer.dispose();
    return bos.toByteArray();
  }

  /** Drain one paint sample. out = {x,y,phase}. */
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

  private void sendPacket(int type, byte[] payload, int flags, boolean flush) {
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
        if (flush || payload.length < 4096) out.flush();
      } catch (IOException ignored) {
      }
    }
  }

  private void runLoop() {
    while (running) {
      try {
        HostPort hp = resolveService();
        if (hp == null) {
          status = "LuckyPad: waiting for iPad…";
          sleep(1200);
          continue;
        }
        status = "LuckyPad: connecting " + hp.host + ":" + hp.port + "…";
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
        status = "LuckyPad: LINK";
        readConnected(s);
      } catch (Exception e) {
        connected = false;
        status = "LuckyPad: " + shortErr(e);
        closeSocket();
        sleep(1000);
      }
    }
    connected = false;
    closeSocket();
  }

  private void readConnected(Socket s) throws IOException {
    InputStream in = s.getInputStream();
    byte[] buf = new byte[64 * 1024];
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
      int length = u32(b, 8);
      if (length < 0 || length > MAX_PACKET) {
        rx.clear();
        return;
      }
      int total = HEADER + length;
      if (rx.size < total) return;
      byte[] payload = rx.slice(HEADER, length);
      rx.drop(total);
      if (type == TYPE_STATUS) onStatus(payload);
      else if (type == TYPE_EVENT) onEvent(payload);
    }
  }

  private void onStatus(byte[] payload) {
    String json = new String(payload, StandardCharsets.UTF_8);
    int w = (int) fnum(json, "w", 0);
    int h = (int) fnum(json, "h", 0);
    if (w > 1 && h > 1) {
      canvasW = w;
      canvasH = h;
    }
  }

  private void onEvent(byte[] payload) {
    String json = new String(payload, StandardCharsets.UTF_8);
    // Brush before ink: "brush" must not be confused with ink's optional "b".
    if (isCmd(json, "brush")) {
      padBrushWant = fnum(json, "v", -1);
      if (padBrushWant >= 1) pushAction(ACT_BRUSH);
      return;
    }
    if (isCmd(json, "tool")) {
      padToolWant = (int) fnum(json, "v", -1);
      if (padToolWant >= 0) pushAction(ACT_TOOL);
      return;
    }
    // Ink samples: match "c":"ink" (not "inkrgb"). Optional "b" = brush at stroke begin.
    if (isCmd(json, "ink")) {
      float x = fnum(json, "x", -1);
      float y = fnum(json, "y", -1);
      int ph = (int) fnum(json, "ph", 1);
      if (x < 0 || y < 0) return;
      float b = fnum(json, "b", -1);
      if (b >= 1) {
        padBrushWant = b;
        pushAction(ACT_BRUSH);
      }
      pushInk(constrain01(x), constrain01(y), ph);
      return;
    }
    // Pad ColorPicker edit: {"c":"swatch","i":N,"r":R,"g":G,"b":B}
    if (isCmd(json, "swatch")) {
      int r = (int) fnum(json, "r", 237);
      int g = (int) fnum(json, "g", 237);
      int b = (int) fnum(json, "b", 240);
      padColorRgb = ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);
      padColorIdx = (int) fnum(json, "i", -1);
      pushAction(ACT_COLOR);
      return;
    }
    if (json.indexOf("\"inkrgb\"") >= 0 || isCmd(json, "color")) {
      int r = (int) fnum(json, "r", 237);
      int g = (int) fnum(json, "g", 237);
      int b = (int) fnum(json, "b", 240);
      padColorRgb = ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);
      padColorIdx = json.indexOf("\"i\"") >= 0 ? (int) fnum(json, "i", -1) : -1;
      pushAction(ACT_COLOR);
      return;
    }
    if (json.indexOf("\"onion\"") >= 0) {
      padOnionWant = json.indexOf("\"v\"") >= 0 ? (int) fnum(json, "v", -1) : -1;
      pushAction(ACT_ONION);
      return;
    }
    if (isCmd(json, "shoot") || json.indexOf("\"shoot\"") >= 0) pushAction(ACT_SHOOT);
    else if (isCmd(json, "undo") || json.indexOf("\"undo\"") >= 0) pushAction(ACT_UNDO);
    else if (isCmd(json, "play") || json.indexOf("\"play\"") >= 0) pushAction(ACT_PLAY);
    else if (isCmd(json, "bake") || json.indexOf("\"bake\"") >= 0) pushAction(ACT_BAKE);
    else if (isCmd(json, "clear") || json.indexOf("\"clear\"") >= 0) pushAction(ACT_CLEAR);
  }

  private void pushInk(float x, float y, int ph) {
    synchronized (inkLock) {
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
        inkTail = (inkTail + 1) % inkX.length;
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

  private HostPort resolveService() {
    List<String> names = browseNames(2000);
    if (names.isEmpty()) names.add("LuckyPad");
    for (String name : names) {
      HostPort hp = lookup(name, 2000);
      if (hp != null) {
        if (tryReachable(hp.host, FIXED_PORT, 400)) return new HostPort(hp.host, FIXED_PORT);
        if (tryReachable(hp.host, hp.port, 400)) return hp;
        // Still try FIXED_PORT even if probe failed (race with listen start).
        return new HostPort(hp.host, FIXED_PORT);
      }
    }
    // Bonjour quiet (Local Network denied on pad, USB-only, etc.) — direct fallbacks.
    HostPort direct = probeDirectHosts();
    if (direct != null) return direct;
    return null;
  }

  /** USB / .local hostnames when mDNS service browse finds nothing. */
  private HostPort probeDirectHosts() {
    String[] hosts = {
      "rms-iPad.local",
      "rm’s iPad.local",
      "iPad.local",
      "LuckyPad.local"
    };
    for (String h : hosts) {
      if (tryReachable(h, FIXED_PORT, 500)) return new HostPort(h, FIXED_PORT);
    }
    // Resolve USB link-local via dns-sd hostname, then connect.
    String[] mdns = { "rms-iPad.local", "iPad.local" };
    for (String h : mdns) {
      String ip = resolveA(h, 1200);
      if (ip != null && tryReachable(ip, FIXED_PORT, 500)) return new HostPort(ip, FIXED_PORT);
    }
    return null;
  }

  /** dns-sd -G v4 hostname → first IPv4. */
  private String resolveA(String hostname, int timeoutMs) {
    Process p = null;
    try {
      p = new ProcessBuilder("dns-sd", "-G", "v4", hostname)
        .redirectErrorStream(true).start();
      BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8));
      long deadline = System.currentTimeMillis() + timeoutMs;
      Pattern ipPat = Pattern.compile("\\b(\\d{1,3}(?:\\.\\d{1,3}){3})\\b");
      while (System.currentTimeMillis() < deadline && running) {
        if (br.ready()) {
          String line = br.readLine();
          if (line == null) break;
          if (line.contains("No Such Record")) continue;
          Matcher m = ipPat.matcher(line);
          if (m.find()) {
            String ip = m.group(1);
            if (!ip.startsWith("0.")) return ip;
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
      p = new ProcessBuilder("dns-sd", "-B", "_luckypad._tcp", "local.")
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
      p = new ProcessBuilder("dns-sd", "-L", name, "_luckypad._tcp", "local.")
        .redirectErrorStream(true).start();
      BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8));
      long deadline = System.currentTimeMillis() + timeoutMs;
      while (System.currentTimeMillis() < deadline && running) {
        if (br.ready()) {
          String line = br.readLine();
          if (line == null) break;
          Matcher m = REACH.matcher(line);
          if (m.find()) {
            return new HostPort(m.group(1).trim(), Integer.parseInt(m.group(2).trim()));
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
    Socket s = socket;
    socket = null;
    if (s != null) {
      try {
        s.close();
      } catch (IOException ignored) {
      }
    }
  }

  private static void kill(Process p) {
    if (p == null) return;
    p.destroy();
    try {
      if (!p.waitFor(300, java.util.concurrent.TimeUnit.MILLISECONDS)) {
        p.destroyForcibly();
        p.waitFor(300, java.util.concurrent.TimeUnit.MILLISECONDS);
      }
    } catch (InterruptedException ignored) {
      p.destroyForcibly();
    } catch (Exception ignored) {
      try {
        p.destroyForcibly();
      } catch (Exception ignored2) {
      }
    }
  }

  private static void sleep(long ms) {
    try {
      Thread.sleep(ms);
    } catch (InterruptedException ignored) {
    }
  }

  private static int u32(byte[] b, int o) {
    return ((b[o] & 0xff) << 24) | ((b[o + 1] & 0xff) << 16)
      | ((b[o + 2] & 0xff) << 8) | (b[o + 3] & 0xff);
  }

  /** True when JSON command field c equals cmd (tolerant of spaces). */
  private static boolean isCmd(String json, String cmd) {
    if (json == null || cmd == null) return false;
    return json.indexOf("\"c\":\"" + cmd + "\"") >= 0
      || json.indexOf("\"c\": \"" + cmd + "\"") >= 0;
  }

  private static float fnum(String json, String key, float fallback) {
    // Accept `.` or `,` decimals (iPad locale can emit commas via String(format:)).
    Pattern p = Pattern.compile("\"" + key + "\"\\s*:\\s*(-?\\d+(?:[.,]\\d+)?)");
    Matcher m = p.matcher(json);
    if (!m.find()) return fallback;
    try {
      return Float.parseFloat(m.group(1).replace(',', '.'));
    } catch (NumberFormatException e) {
      return fallback;
    }
  }

  private static float constrain01(float v) {
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v;
  }

  private static String shortErr(Exception e) {
    String m = e.getMessage();
    if (m == null || m.length() == 0) return e.getClass().getSimpleName();
    if (m.length() > 48) return m.substring(0, 48);
    return m;
  }

  private static final class HostPort {
    final String host;
    final int port;
    HostPort(String host, int port) {
      this.host = host;
      this.port = port;
    }
  }

  private static final class ByteAccum {
    byte[] data = new byte[64 * 1024];
    int size;

    void append(byte[] src, int off, int len) {
      ensure(size + len);
      System.arraycopy(src, off, data, size, len);
      size += len;
    }

    void ensure(int need) {
      if (need <= data.length) return;
      int n = data.length;
      while (n < need) n *= 2;
      byte[] next = new byte[n];
      System.arraycopy(data, 0, next, 0, size);
      data = next;
    }

    void drop(int n) {
      if (n <= 0) return;
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
