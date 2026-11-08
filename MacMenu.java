public class MacMenu {
  static boolean loaded;
  static String fail = "";

  static void load(String path) {
    if (loaded) return;
    java.io.File file = new java.io.File(path);
    if (!file.exists()) {
      fail = "Menu library is missing.";
      return;
    }
    try {
      System.load(file.getAbsolutePath());
      loaded = true;
    } catch (Throwable t) {
      fail = t.getMessage() == null ? "Menu library failed to load." : t.getMessage();
    }
  }

  static native void install();

  static native int poll();

  static native void setRecents(String[] titles, String[] paths);

  /** Keep the Mac menu bar visible on the laptop; clamp the main window into visibleFrame. */
  static native void keepDesktopChrome();

  /** Cover menu bar / clock on program-out screens only (above menu bar, full screen.frame). */
  static native void shieldProgramOut();
}
