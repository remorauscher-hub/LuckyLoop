public class TetherNative {
  static boolean loaded;
  static String fail = "";

  static void load(String path) {
    if (loaded) return;
    java.io.File file = new java.io.File(path);
    if (!file.exists()) {
      fail = "Tether library missing.";
      return;
    }
    try {
      System.load(file.getAbsolutePath());
      loaded = true;
    } catch (Throwable t) {
      fail = t.getMessage() == null ? "Tether library failed to load." : t.getMessage();
    }
  }

  static native void start();
  static native void stop();
  static native boolean connected();
  static native String status();
  static native String phoneStatus();
  static native long frameSeq();
  static native byte[] copyJpeg();
  static native void sendControl(String json);
}
