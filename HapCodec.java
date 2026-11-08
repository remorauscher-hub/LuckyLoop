import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Hap1-style DXT1 (BC1) encode/decode — same texture stage Resolume uses for Hap.
 * No Snappy second stage so frame size stays fixed and seeks are O(1).
 */
public final class HapCodec {
  public static final int HAP1_NONE = 0xAB;

  private HapCodec() {}

  public static int dxt1Size(int w, int h) {
    int bw = Math.max(1, (w + 3) / 4);
    int bh = Math.max(1, (h + 3) / 4);
    return bw * bh * 8;
  }

  public static void encodeDxt1(int[] argb, int w, int h, byte[] out) {
    int bw = (w + 3) / 4;
    int bh = (h + 3) / 4;
    int o = 0;
    int[] block = new int[16];
    for (int by = 0; by < bh; by++) {
      for (int bx = 0; bx < bw; bx++) {
        int i = 0;
        for (int py = 0; py < 4; py++) {
          int y = Math.min(h - 1, by * 4 + py);
          int row = y * w;
          for (int px = 0; px < 4; px++) {
            int x = Math.min(w - 1, bx * 4 + px);
            block[i++] = argb[row + x];
          }
        }
        o = writeBlock(block, out, o);
      }
    }
  }

  public static void decodeDxt1(byte[] dxt, int w, int h, int[] argb) {
    int bw = (w + 3) / 4;
    int bh = (h + 3) / 4;
    int o = 0;
    int[] colors = new int[4];
    for (int by = 0; by < bh; by++) {
      for (int bx = 0; bx < bw; bx++) {
        int c0 = (dxt[o] & 255) | ((dxt[o + 1] & 255) << 8);
        int c1 = (dxt[o + 2] & 255) | ((dxt[o + 3] & 255) << 8);
        o += 4;
        int bits = (dxt[o] & 255)
          | ((dxt[o + 1] & 255) << 8)
          | ((dxt[o + 2] & 255) << 16)
          | ((dxt[o + 3] & 255) << 24);
        o += 4;
        unpack565(c0, colors, 0);
        unpack565(c1, colors, 1);
        if (c0 > c1) {
          colors[2] = mix(colors[0], colors[1], 2, 1);
          colors[3] = mix(colors[0], colors[1], 1, 2);
        } else {
          colors[2] = mix(colors[0], colors[1], 1, 1);
          colors[3] = 0xFF000000;
        }
        for (int py = 0; py < 4; py++) {
          int y = by * 4 + py;
          if (y >= h) continue;
          int row = y * w;
          for (int px = 0; px < 4; px++) {
            int x = bx * 4 + px;
            if (x >= w) continue;
            int idx = (bits >>> ((py * 4 + px) * 2)) & 3;
            argb[row + x] = colors[idx] | 0xFF000000;
          }
        }
      }
    }
  }

  /** Optional Hap section header (type 0xAB) in front of DXT1 payload. */
  public static int writeHap1Section(byte[] dxt, int dxtLen, byte[] dest, int destOff) {
    dest[destOff] = (byte) (dxtLen & 255);
    dest[destOff + 1] = (byte) ((dxtLen >>> 8) & 255);
    dest[destOff + 2] = (byte) ((dxtLen >>> 16) & 255);
    dest[destOff + 3] = (byte) HAP1_NONE;
    System.arraycopy(dxt, 0, dest, destOff + 4, dxtLen);
    return destOff + 4 + dxtLen;
  }

  private static int writeBlock(int[] block, byte[] out, int o) {
    int minL = Integer.MAX_VALUE;
    int maxL = Integer.MIN_VALUE;
    int cMin = block[0];
    int cMax = block[0];
    for (int i = 0; i < 16; i++) {
      int p = block[i];
      int r = (p >> 16) & 255;
      int g = (p >> 8) & 255;
      int b = p & 255;
      int l = r * 2 + g * 5 + b;
      if (l < minL) {
        minL = l;
        cMin = p;
      }
      if (l > maxL) {
        maxL = l;
        cMax = p;
      }
    }
    int c0 = to565(cMax);
    int c1 = to565(cMin);
    if (c0 == c1) {
      out[o++] = (byte) (c0 & 255);
      out[o++] = (byte) ((c0 >>> 8) & 255);
      out[o++] = (byte) (c1 & 255);
      out[o++] = (byte) ((c1 >>> 8) & 255);
      out[o++] = 0;
      out[o++] = 0;
      out[o++] = 0;
      out[o++] = 0;
      return o;
    }
    if (c0 < c1) {
      int t = c0;
      c0 = c1;
      c1 = t;
      int p = cMax;
      cMax = cMin;
      cMin = p;
    }
    int[] colors = new int[4];
    unpack565(c0, colors, 0);
    unpack565(c1, colors, 1);
    colors[2] = mix(colors[0], colors[1], 2, 1);
    colors[3] = mix(colors[0], colors[1], 1, 2);
    int bits = 0;
    for (int i = 0; i < 16; i++) {
      bits |= nearest(block[i], colors) << (i * 2);
    }
    out[o++] = (byte) (c0 & 255);
    out[o++] = (byte) ((c0 >>> 8) & 255);
    out[o++] = (byte) (c1 & 255);
    out[o++] = (byte) ((c1 >>> 8) & 255);
    out[o++] = (byte) (bits & 255);
    out[o++] = (byte) ((bits >>> 8) & 255);
    out[o++] = (byte) ((bits >>> 16) & 255);
    out[o++] = (byte) ((bits >>> 24) & 255);
    return o;
  }

  private static int nearest(int p, int[] colors) {
    int best = 0;
    int bestD = Integer.MAX_VALUE;
    int pr = (p >> 16) & 255;
    int pg = (p >> 8) & 255;
    int pb = p & 255;
    for (int i = 0; i < 4; i++) {
      int c = colors[i];
      int dr = pr - ((c >> 16) & 255);
      int dg = pg - ((c >> 8) & 255);
      int db = pb - (c & 255);
      int d = dr * dr * 2 + dg * dg * 4 + db * db;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  private static int to565(int argb) {
    int r = (argb >> 16) & 255;
    int g = (argb >> 8) & 255;
    int b = argb & 255;
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
  }

  private static void unpack565(int c, int[] dest, int i) {
    int r = ((c >> 11) & 31) * 255 / 31;
    int g = ((c >> 5) & 63) * 255 / 63;
    int b = (c & 31) * 255 / 31;
    dest[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  private static int mix(int a, int b, int wa, int wb) {
    int t = wa + wb;
    int r = ((((a >> 16) & 255) * wa) + (((b >> 16) & 255) * wb)) / t;
    int g = ((((a >> 8) & 255) * wa) + (((b >> 8) & 255) * wb)) / t;
    int bl = (((a & 255) * wa) + ((b & 255) * wb)) / t;
    return 0xFF000000 | (r << 16) | (g << 8) | bl;
  }

  public static ByteBuffer le(int capacity) {
    return ByteBuffer.allocate(capacity).order(ByteOrder.LITTLE_ENDIAN);
  }
}
