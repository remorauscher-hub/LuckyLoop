public class MidiCtl {
  static boolean loaded;
  static String fail = "";

  static void load(String path) {
    if (loaded) return;
    java.io.File file = new java.io.File(path);
    if (!file.exists()) {
      fail = "MIDI native library is missing.";
      return;
    }
    try {
      System.load(file.getAbsolutePath());
      loaded = true;
    } catch (Throwable t) {
      fail = t.getMessage() == null ? "MIDI native library failed to load." : t.getMessage();
    }
  }

  /** Start CoreMIDI input (all sources). 1 = ok. */
  static native int start();

  static native void stop();

  /** Re-scan / reconnect sources (hot-plug). */
  static native void refresh();

  /**
   * Drain pending events into out as type,ch,num,val,...
   * Returns number of events written.
   */
  static native int poll(int[] out);

  static native int sourceCount();

  /** CoreMIDI source display name, or null. */
  static native String sourceName(int index);
}
