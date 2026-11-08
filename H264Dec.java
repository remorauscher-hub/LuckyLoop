/**
 * VideoToolbox Annex-B H.264 decoder (LuckyTether type-6 frames).
 */
public class H264Dec {
  static boolean loaded;
  static String fail = "";

  static void load(String path) {
    if (loaded) return;
    java.io.File file = new java.io.File(path);
    if (!file.exists()) {
      fail = "H.264 decoder library is missing.";
      return;
    }
    try {
      System.load(file.getAbsolutePath());
      loaded = true;
    } catch (Throwable t) {
      fail = t.getMessage() == null ? "H.264 decoder failed to load." : t.getMessage();
    }
  }

  /** Decode one Annex-B access unit. keyframe bit from packet flags. Returns 1 on success. */
  static native int decode(byte[] annexB, int keyframe, int hintW, int hintH);

  /** Decode one JPEG (LuckyTether type-1). Avoids AWT ImageIO inside Processing. Returns 1 on success. */
  static native int decodeJpeg(byte[] jpeg);

  /** Copy latest ARGB frame into dest (or allocate). Returns null if none. */
  static native int[] copyPixels(int[] dest);

  static native int width();
  static native int height();
  static native long frameSeq();

  static native void reset();
}
