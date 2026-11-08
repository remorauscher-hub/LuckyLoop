public class CamCtl {
  static boolean loaded;
  static String fail = "";

  static void load(String path) {
    if (loaded) return;
    java.io.File file = new java.io.File(path);
    if (!file.exists()) {
      fail = "Camera control library is missing.";
      return;
    }
    try {
      System.load(file.getAbsolutePath());
      loaded = true;
    } catch (Throwable t) {
      fail = t.getMessage() == null ? "Camera control library failed to load." : t.getMessage();
    }
  }

  static native int configure(String name, String uid, byte[] out,
    int autoExposure, int autoFocus, int autoWhite, int lensLock, int centerStage,
    float bias, float focus, float zoom, int lens,
    int applyBias, int applyFocus, int applyZoom, int applyLens);

  static native void releaseStage();

  /** Rows: "localizedName\\tuniqueID\\tcontinuity(0|1)". Includes Continuity Camera. */
  static native String[] listDevices();

  /** 1 if host Info.plist has NSCameraUseContinuityCameraDeviceType. */
  static native int continuityOptIn();
}
