// Export current Hap loop background (no live / stoptrick / draw) as H.264 MP4.

volatile boolean exportBusy = false;
volatile boolean archiveBusy = false;
volatile String exportStatus = "";
/** Guards Loop FX / curve buffers shared with the draw thread. */
final Object loopComposeLock = new Object();

String findFfmpeg() {
  String[] cands = {
    "/opt/homebrew/bin/ffmpeg",
    "/usr/local/bin/ffmpeg",
    System.getProperty("user.home") + "/homebrew/bin/ffmpeg",
    System.getProperty("user.home") + "/Homebrew/bin/ffmpeg",
    "/usr/bin/ffmpeg",
    "ffmpeg"
  };
  for (int i = 0; i < cands.length; i++) {
    File f = new File(cands[i]);
    if (f.isFile() && f.canExecute()) return f.getAbsolutePath();
  }
  // PATH lookup
  try {
    Process p = new ProcessBuilder("/bin/sh", "-c", "command -v ffmpeg").start();
    java.io.BufferedReader br = new java.io.BufferedReader(
      new java.io.InputStreamReader(p.getInputStream()));
    String line = br.readLine();
    p.waitFor();
    if (line != null && line.length() > 0) {
      File f = new File(line.trim());
      if (f.isFile()) return f.getAbsolutePath();
    }
  } catch (Throwable ignored) {
  }
  return null;
}

void requestLoopExport() {
  if (exportBusy || archiveBusy) {
    note("Export running…");
    return;
  }
  if (!requireProject()) return;
  if (!hasLoop() || loopFrames < 1 || layerCount() < 1) {
    note("No loop to export");
    return;
  }
  snapshotTextForExport();
  exportBusy = true;
  exportStatus = "Exporting…";
  note("Exporting loop…");
  thread("runLoopExport");
}

/** Background thread entry (Processing thread("…")). */
void runLoopExport() {
  File outFile = null;
  try {
    outFile = exportLoopMp4();
    if (outFile != null) {
      exportStatus = outFile.getName();
      note("Exported  " + outFile.getName());
      println("Loop export: " + outFile.getAbsolutePath());
    } else if (exportStatus == null || exportStatus.length() == 0) {
      exportStatus = "Export failed";
      note("Export failed");
    } else {
      note(exportStatus);
    }
  } catch (Throwable t) {
    exportStatus = t.getMessage() == null ? "Export failed" : t.getMessage();
    note("Export failed");
    println("Loop export failed: " + exportStatus);
    t.printStackTrace();
  } finally {
    loopImgHead = -1;
    exportBusy = false;
  }
}

File exportLoopMp4() throws Exception {
  return encodeLoopMp4(null, null, loopFrames, capW, capH, max(1, capFps));
}

/** Encode a Hap stack to H.264. stores == null reads the live play layers. */
File encodeLoopMp4(HapLoopStore[] stores, int[] blends, int n, int w, int h, int fps) throws Exception {
  String ffmpeg = findFfmpeg();
  if (ffmpeg == null) {
    exportStatus = "ffmpeg not found";
    return null;
  }
  if (n < 1 || w < 2 || h < 2) {
    exportStatus = "MP4 failed";
    return null;
  }
  ensureProjectDirs();
  File dir = new File(projectDir, "export");
  dir.mkdirs();
  String stamp = new java.text.SimpleDateFormat("yyyyMMdd-HHmmss").format(new java.util.Date());
  File outFile = new File(dir, "loop-" + stamp + ".mp4");

  int[] frame = new int[w * h];
  int[] scratch = new int[w * h];
  byte[] rgb = new byte[w * h * 3];

  // Prefer VideoToolbox on Mac; fall back to libx264.
  String[][] encoderTries = {
    { "h264_videotoolbox", "65" },
    { "libx264", "18" }
  };

  Exception last = null;
  for (int e = 0; e < encoderTries.length; e++) {
    String codec = encoderTries[e][0];
    String quality = encoderTries[e][1];
    try {
      if (outFile.exists()) outFile.delete();
      writeLoopMp4(ffmpeg, outFile, codec, quality, n, w, h, fps, frame, scratch, rgb, stores, blends);
      if (outFile.exists() && outFile.length() > 1024) return outFile;
      last = new Exception(codec + " produced empty file");
    } catch (Exception ex) {
      last = ex;
      println("Loop export via " + codec + " failed: " + ex.getMessage());
      if (outFile.exists()) outFile.delete();
    }
  }
  if (last != null) throw last;
  exportStatus = "Export failed";
  return null;
}

void writeLoopMp4(String ffmpeg, File outFile, String codec, String quality,
                  int n, int w, int h, int fps,
                  int[] frame, int[] scratch, byte[] rgb,
                  HapLoopStore[] stores, int[] blends) throws Exception {
  java.util.ArrayList<String> cmd = new java.util.ArrayList<String>();
  cmd.add(ffmpeg);
  cmd.add("-y");
  cmd.add("-f"); cmd.add("rawvideo");
  cmd.add("-pix_fmt"); cmd.add("rgb24");
  cmd.add("-s"); cmd.add(w + "x" + h);
  cmd.add("-r"); cmd.add(str(fps));
  cmd.add("-i"); cmd.add("-");
  cmd.add("-an");
  cmd.add("-c:v"); cmd.add(codec);
  if (codec.equals("libx264")) {
    cmd.add("-preset"); cmd.add("fast");
    cmd.add("-crf"); cmd.add(quality);
  } else {
    // videotoolbox: quality 1–100 (higher = better). Map roughly from CRF-ish.
    cmd.add("-q:v"); cmd.add("55");
  }
  cmd.add("-pix_fmt"); cmd.add("yuv420p");
  cmd.add("-movflags"); cmd.add("+faststart");
  cmd.add(outFile.getAbsolutePath());

  ProcessBuilder pb = new ProcessBuilder(cmd);
  pb.redirectErrorStream(true);
  Process proc = pb.start();
  final StringBuilder log = new StringBuilder();
  Thread logThread = new Thread(new Runnable() {
    public void run() {
      try {
        java.io.BufferedReader br = new java.io.BufferedReader(
          new java.io.InputStreamReader(proc.getInputStream()));
        String line;
        while ((line = br.readLine()) != null) {
          if (log.length() < 8000) log.append(line).append('\n');
        }
      } catch (Throwable ignored) {
      }
    }
  }, "ffmpeg-log");
  logThread.setDaemon(true);
  logThread.start();

  java.io.OutputStream stdin = proc.getOutputStream();
  try {
    for (int i = 0; i < n; i++) {
      if (!composeExportFrame(i, frame, scratch, w, h, stores, blends)) {
        java.util.Arrays.fill(frame, 0xFF000000);
      }
      argbToRgb24(frame, rgb);
      stdin.write(rgb);
      if ((i & 7) == 0) {
        exportStatus = "Export " + (i + 1) + "/" + n;
      }
    }
    stdin.flush();
  } finally {
    try { stdin.close(); } catch (Throwable ignored) {}
  }
  logThread.join(15000);
  int code = proc.waitFor();
  if (code != 0) {
    throw new Exception("ffmpeg exit " + code + (log.length() > 0 ? (": " + log.toString()) : ""));
  }
}

/** Hap stack + Loop FX/curves at a fixed head — no live, stoptrick, or draw. */
boolean composeExportFrame(int head, int[] dest, int[] scratch, int w, int h,
    HapLoopStore[] stores, int[] blends) {
  if (dest == null || scratch == null || w < 2 || h < 2) return false;
  int n = w * h;
  if (dest.length < n || scratch.length < n) return false;
  int count = stores != null ? stores.length : layerCount();
  if (count < 1) return false;
  java.util.Arrays.fill(dest, 0, n, 0xFF000000);
  boolean any = false;

  // Two Hap layers: recover Draw-first (ink-on-black) + camera overdub.
  if (count == 2) {
    HapLoopStore a = stores != null ? stores[0] : hapLayers.get(0);
    HapLoopStore b = stores != null ? stores[1] : hapLayers.get(1);
    int[] scratchB = new int[n];
    boolean gotA = a != null && a.copyFrame(head, scratch);
    boolean gotB = b != null && b.copyFrame(head, scratchB);
    if (gotA && gotB) {
      boolean aInk = layers.size() > 0 && layers.get(0).inkPlate;
      boolean bInk = layers.size() > 1 && layers.get(1).inkPlate;
      if (!aInk && !bInk && stores != null) {
        // Legacy hist without ink flags — strict heuristic only.
        aInk = pixelsLookLikeInkOnBlack(scratch);
        bInk = pixelsLookLikeInkOnBlack(scratchB);
      }
      if (aInk && !bInk) {
        System.arraycopy(scratchB, 0, dest, 0, n);
        blendInkOnto(dest, scratch, 255);
        any = true;
      } else if (bInk && !aInk) {
        System.arraycopy(scratch, 0, dest, 0, n);
        blendInkOnto(dest, scratchB, 255);
        any = true;
      }
    }
    if (!any && gotA) {
      System.arraycopy(scratch, 0, dest, 0, n);
      any = true;
      if (gotB) {
        int blend = BLEND_MULTIPLY;
        if (blends != null && blends.length > 1) blend = blends[1];
        else if (stores == null && layers.size() > 1) blend = layers.get(1).blend;
        blendInto(dest, scratchB, 255, blend);
      }
    } else if (!any && gotB) {
      System.arraycopy(scratchB, 0, dest, 0, n);
      any = true;
    }
  } else {
    for (int i = 0; i < count; i++) {
      HapLoopStore store = stores != null ? stores[i] : hapLayers.get(i);
      if (store == null || !store.copyFrame(head, scratch)) continue;
      if (!any) {
        System.arraycopy(scratch, 0, dest, 0, n);
        any = true;
      } else {
        int blend = BLEND_MULTIPLY;
        if (blends != null && i < blends.length) blend = blends[i];
        else if (stores == null && i < layers.size()) blend = layers.get(i).blend;
        blendInto(dest, scratch, 255, blend);
      }
    }
  }
  if (!any) return false;
  synchronized (loopComposeLock) {
    applyLoopFxCurves(dest);
  }
  burnTextExport(dest, w, h);
  return true;
}

void argbToRgb24(int[] argb, byte[] rgb) {
  int n = argb.length;
  int o = 0;
  for (int i = 0; i < n; i++) {
    int c = argb[i];
    rgb[o++] = (byte) ((c >> 16) & 255);
    rgb[o++] = (byte) ((c >> 8) & 255);
    rgb[o++] = (byte) (c & 255);
  }
}
