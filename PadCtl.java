public class PadCtl {
  static boolean loaded;
  static String fail = "";

  static void load(String path) {
    if (loaded) return;
    java.io.File file = new java.io.File(path);
    if (!file.exists()) {
      fail = "Trackpad library is missing.";
      return;
    }
    try {
      System.load(file.getAbsolutePath());
      loaded = true;
    } catch (Throwable t) {
      fail = t.getMessage() == null ? "Trackpad library failed to load." : t.getMessage();
    }
  }

  /** Start absolute multitouch + magnify monitor. 1 = ok. */
  static native int start();

  static native void stop();

  /**
   * out[0]=x, out[1]=y in 0..1 (origin bottom-left of pad).
   * Returns 1 while a finger is down, 0 otherwise.
   */
  static native int poll(float[] out);

  /**
   * Fill out as x0,y0,x1,y1,... (normalized 0..1, origin bottom-left).
   * Returns active touch count.
   */
  static native int pollAll(float[] out);

  /** Accumulated trackpad pinch delta since last poll (cleared on read). */
  static native float pollMagnify();

  /** Accumulated trackpad rotate delta in degrees since last poll (cleared on read). */
  static native float pollRotate();

  /**
   * Two-finger trackpad pan as precise scroll deltas (points).
   * out[0]=dx, out[1]=dy. Returns 1 if any delta was pending.
   */
  static native int pollScroll(float[] out);
}
