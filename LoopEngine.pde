HapLoopStore hapRec = new HapLoopStore();
ArrayList<HapLoopStore> hapLayers = new ArrayList<HapLoopStore>();
ArrayList<File> hapLayerFiles = new ArrayList<File>();
int[] loopPixels;
int[] layerScratch;
int[] layerScratchB;
PImage loopImg;
int loopImgHead = -1;
int loopFrames = 0;
int nextSampleAt = 0;
long playOrigin = 0;
int recStartMillis = 0;
int recFrameCount = 0;
boolean recWait = false;
int recWaitHead = -1;
boolean recFromStop = false;
/** Current take is a sparse Draw/ink plate (not dark camera video). */
boolean recInkPlate = false;
boolean loopReady = false;
int lockedFrames = 0; // set by first record; only Clear unlocks length
File hapRecFile;

static final int DEFAULT_UNDO_STEPS = 10;
int undoSteps = DEFAULT_UNDO_STEPS;
ArrayList<LoopHist> undoHist = new ArrayList<LoopHist>();
ArrayList<LoopHist> redoHist = new ArrayList<LoopHist>();

int activeLayer = -1;
int selectedLayer = -1;
ArrayList<LoopLayer> layers = new ArrayList<LoopLayer>();

// Async overdub bake: old background keeps playing, then soft crossfade.
static final int BAKE_FADE_MS = 300;
// First take: loop eases in under the live picture instead of cutting on.
static final int LOOP_INTRO_MS = 320;
boolean loopIntroOn = false;
float loopIntro = 1;
int loopIntroAt = 0;
// Undo / redo: previous loop plate dissolves into the one now playing.
boolean loopHistFade = false;
boolean loopHistGhost = false;
float loopHistAmt = 0;
int loopHistAt = 0;
boolean loopHistSrcValid = false;
int[] loopHistSrc;
PImage loopHistImg;
volatile boolean flattenBusy = false;
volatile boolean flattenReady = false;
volatile boolean flattenFailed = false;
final java.util.concurrent.atomic.AtomicBoolean flattenCancel =
  new java.util.concurrent.atomic.AtomicBoolean(false);
File flattenFile;
File flattenNewFile;
int flattenNewBlend = BLEND_MULTIPLY;
int flattenNewTake = 0;
HapLoopStore flattenIncoming;
float flattenFade = 0;
int flattenFadeAt = 0;
int[] flattenFadeScratch;
int[] flattenHoldScratch;
/** Per overdub frame: loop-layer opacity 0–255. -1 = not sampled. */
int[] recLoopAlpha;
/** Per live-overdub frame: live-bus opacity 0–255. -1 = not sampled. */
int[] recLiveAlpha;
/** Baked into the overdub flatten. Null means the loop stayed at full opacity. */
int[] flattenBgAlpha;
boolean flattenPrintedOpacity;
/** Overdub bake: burn active Loop-FX into the old plate (snapshot for the bake thread). */
boolean flattenBakeLoopFx = false;
ArrayList<FxUnit> flattenFxSnap;
/** Frames stay on screen until the new Hap has faded over them. */
boolean stopAwaitHap = false;
/** Double-tap on "-" clears after the bake. A single tap keeps the frames. */
boolean stopClearThisBake = false;
/** Remembered across the Hap fade: wipe the stack when the cover finishes. */
boolean stopReleaseClears = false;
int dashArmAt = 0;
/** Set when a dash single commits a keep, so the second tap can still clear. */
int dashBakeKeptAt = 0;
boolean dashLatch = false;
float stopCover = 0;
int stopCoverAt = 0;
PImage stopCoverImg;

class LoopLayer {
  int number = 1;
  int take;
  int w;
  int h;
  String path = "";
  boolean saved;
  boolean binOnSave;
  int blend = BLEND_MULTIPLY;
  /** Sparse Draw/ink Hap (clear→black). Never infer from dark Multiply video. */
  boolean inkPlate = false;
  final Object fileLock = new Object();
}

class LoopHist {
  File file;
  int take;
  int frames;
  int w;
  int h;
  int fps;
  int blend;
  LoopHist(File file, int take, int frames, int w, int h, int fps, int blend) {
    this.file = file;
    this.take = take;
    this.frames = frames;
    this.w = w;
    this.h = h;
    this.fps = fps;
    this.blend = blend;
  }
}

int sampleIntervalMs() {
  return max(1, round(1000f / capFps));
}

/** Shared time→frame mapping for record length and playback head. */
int framesForElapsed(long elapsedMs) {
  if (elapsedMs <= 0) return 0;
  return (int) (elapsedMs * (long) capFps / 1000L);
}

int maxFrames() {
  return capFps * MAX_SECONDS;
}

boolean lengthLocked() {
  return lockedFrames > 0;
}

int recTargetFrames() {
  return lengthLocked() ? lockedFrames : maxFrames();
}

int layerCount() {
  return hapLayers.size();
}

boolean hasLoop() {
  return loopReady && loopFrames > 0 && layerCount() > 0;
}

/** Loop stack stays visible while overdubbing. */
boolean loopAudible() {
  return hasLoop();
}

int currentHead() {
  if (loopFrames <= 0) return 0;
  long elapsed = millis() - playOrigin;
  if (elapsed < 0) elapsed = 0;
  int f = framesForElapsed(elapsed);
  int m = f % loopFrames;
  if (m < 0) m += loopFrames;
  return m;
}

void onSpace() {
  // Work-mode routing: Stoptrick/Draw own Space; Live / FX keep dubbing.
  // FX view always records like Live so you can take while tweaking FX.
  // Text Place gives Space back to recording so a pinch performance can be taken.
  if ((stopModeOn() || drawModeOn()) && !textPlaceRecords() && !fxViewOn()) {
    stopTogglePlay();
    return;
  }
  if (mode == MODE_LIVE) beginRec();
  else if (mode == MODE_REC) {
    if (lengthLocked()) cancelRecKeepLoop();
    else commitRec();
  } else if (mode == MODE_PLAY) {
    if (recWait) cancelRecWait();
    else armRecWait();
  }
}

/**
 * Bake stoptrick onto the Hap loop.
 * Layer 1 (no locked length): Bake starts free-length record; Bake again locks / commits.
 * With a loop: wait for the next loop start, then bake exactly one loop length.
 * A single "-" keeps the frames. A double-tap clears them after the Hap is in.
 */
void bakeStoptrick() {
  if (stopAwaitHap) {
    note("Fading bake in");
    return;
  }
  if (!hasStop()) {
    note("No stoptrick frames");
    luckyPadSyncPlay();
    return;
  }
  fxCancelNudge();
  // First-layer bake in progress → Bake again locks length.
  if (mode == MODE_REC && recFromStop && !lengthLocked()) {
    commitRec();
    return;
  }
  // Fixed-length bake in progress → Bake cancels.
  if (mode == MODE_REC && recFromStop && lengthLocked()) {
    cancelRecKeepLoop();
    luckyPadAfterBakeReset(false);
    return;
  }
  // Waiting for loop start → Bake again cancels the wait.
  if (recWait && stopIsRecordSource()) {
    cancelRecWait();
    luckyPadAfterBakeReset(false);
    return;
  }

  if (!stopPlaying) {
    stopPlaying = true;
    stopOrigin = millis();
    stopInvalidateImg();
    selectedLayer = SEL_STOP;
  } else {
    selectedLayer = SEL_STOP;
  }

  if (hasLoop() && lengthLocked()) {
    // Always burn at the next loop wrap — even if we were in LIVE / Draw.
    if (mode != MODE_PLAY) {
      mode = MODE_PLAY;
      if (playOrigin == 0) playOrigin = millis();
    }
    armRecWait();
  } else if (mode == MODE_LIVE || !hasLoop()) {
    // Layer 1 (no locked length): free record until Bake again.
    beginRec();
  } else if (mode == MODE_REC) {
    note("Already recording");
  }
  luckyPadSyncPlay();
  luckyPadRequestPreview(true);
}

/** After bake (or cancel): Hold→Play, Bake idle, frames cleared when done. */
void luckyPadAfterBakeReset(boolean clearFrames) {
  if (clearFrames && hasStop()) stopClear(false);
  else {
    stopPlaying = false;
    stopHold = -1;
    stopInvalidateImg();
  }
  luckyPadSyncPlay();
  luckyPadRequestPreview(true);
}

/**
 * "-": one tap bakes and keeps the frames. Two taps inside the double-tap
 * window bake and clear. The second tap does not lock or cancel.
 */
void pressBakeDash() {
  if (!(stopModeOn() || drawModeOn())) return;
  int now = millis();
  boolean twice = dashArmAt > 0 && now - dashArmAt < FX_TAP_MS;
  if (twice) {
    dashArmAt = 0;
    onDashDouble(now);
    return;
  }
  dashArmAt = now;
  boolean locking = mode == MODE_REC && recFromStop && !lengthLocked();
  if (!locking) stopClearThisBake = false;
  bakeStoptrick();
}

void onDashDouble(int now) {
  if (dashBakeKeptAt > 0 && now - dashBakeKeptAt < FX_TAP_MS) {
    dashBakeKeptAt = 0;
    if (hasStop()) {
      stopClear(false);
      note("Bake  ·  frames cleared");
    }
    return;
  }
  boolean justStarted = (mode == MODE_REC && recFromStop && now - recStartMillis < FX_TAP_MS)
    || (recWait && stopIsRecordSource());
  if (justStarted) {
    stopClearThisBake = true;
    note("Bake and clear");
    return;
  }
}

void beginRec() {
  if (!requireProject()) return;
  if (stopAwaitHap) {
    note("Fading bake in");
    return;
  }
  if (flattenInFlight()) {
    note("Still baking previous overdub");
    return;
  }
  fxCancelNudge();
  recFromStop = stopIsRecordSource();
  recInkPlate = recFromStop && stopStackMostlyInk();
  if (!recFromStop && !liveValid && sourceMode != SRC_TEST) {
    note("No source");
    return;
  }
  ensureProjectDirs();
  currentTake = ++takeCount;
  hapRecFile = new File(takeFolder(currentTake), "layer-" + String.format("%02d", layerCount() + 1) + ".hap1");
  hapRec.prepare(capW, capH, capFps);
  if (!hapRec.beginRecord(hapRecFile)) {
    note("Hap record failed");
    if (hapRec.failMessage().length() > 0) println(hapRec.failMessage());
    recFromStop = false;
    recInkPlate = false;
    return;
  }
  recFrameCount = 0;
  armRecLoopAlpha();
  if (lengthLocked()) {
    endLoopIntro();
    endLoopHistFade();
  }
  mode = MODE_REC;
  recStartMillis = millis();
  nextSampleAt = millis();
  if (recFromStop) {
    if (lengthLocked()) note("Baking stoptrick  ·  layer " + (layerCount() + 1) + "  ·  one loop");
    else note("Baking stoptrick  ·  Bake again locks length");
  } else if (lengthLocked()) note("Overdub  layer " + (layerCount() + 1) + "  ·  " + fmtSec(lockedFrames / (float) capFps));
  else note("Recording  sets loop length");
}

void armRecWait() {
  if (flattenInFlight()) {
    note("Still baking previous overdub");
    return;
  }
  if (!stopIsRecordSource() && !liveValid && sourceMode != SRC_TEST) {
    note("No source");
    return;
  }
  if (!lengthLocked()) {
    note("No locked length");
    return;
  }
  recWait = true;
  recWaitHead = currentHead();
  endLoopIntro();
  endLoopHistFade();
  note(stopIsRecordSource()
    ? "Waiting for loop start  ·  bake one loop"
    : "Waiting for loop start  ·  overdub");
}

void cancelRecWait() {
  recWait = false;
  recWaitHead = -1;
  note("Record cancelled");
  luckyPadSyncPlay();
  luckyPadRequestPreview(true);
}

void cancelRecKeepLoop() {
  hapRec.cancelRecord();
  if (hapRecFile != null && hapRecFile.exists()) hapRecFile.delete();
  hapRecFile = null;
  recLoopAlpha = null;
  recLiveAlpha = null;
  recFromStop = false;
  recInkPlate = false;
  mode = hasLoop() ? MODE_PLAY : MODE_LIVE;
  note(hasLoop() ? "Overdub cancelled" : "Recording discarded");
  luckyPadSyncPlay();
  luckyPadRequestPreview(true);
}

void commitRec() {
  int minFrames = max(4, capFps / 4);
  boolean first = !lengthLocked();
  boolean liveTake = !recFromStop;
  // Lock first take to wall-clock duration so dropped encodes can't shorten playback.
  int wallFrames = max(minFrames, framesForElapsed(millis() - recStartMillis));
  int target = first ? wallFrames : recTargetFrames();
  boolean ok = hapRec.finishRecord(target);
  int n = hapRec.frameCount;
  if (first && ok && n > 0 && n < wallFrames) {
    if (hapRec.padToFrames(wallFrames)) n = hapRec.frameCount;
  }
  if (!ok || n < minFrames) {
    cancelRecKeepLoop();
    note("Too short, recording discarded");
    return;
  }
  if (!first) {
    if (n < lockedFrames) {
      cancelRecKeepLoop();
      note("Overdub incomplete — length stays locked");
      return;
    }
    n = lockedFrames;
  } else {
    n = min(n, wallFrames);
    if (hapRec.frameCount > n) hapRec.trimToFrames(n);
  }

  // Live mix for the take is already printed into the bake — fader back to 100%.
  if (liveTake) liveOpacity = 1;

  clearHist(redoHist);
  if (first) {
    lockedFrames = n;
    loopFrames = n;
    playOrigin = millis();
  } else if (undoSteps > 0) {
    // Snapshot the current background for Undo. Playback keeps the old
    // Hap layer running (same playOrigin → BPM/phase stays locked) while
    // the new take bakes off-thread, then crossfades in.
    LoopHist prev = snapshotCurrentComposite();
    if (prev != null) pushHist(undoHist, prev);
  }

  HapLoopStore store = hapRec;
  hapRec = new HapLoopStore();
  File file = hapRecFile;
  hapRecFile = null;

  if (first) {
    hapLayers.add(store);
    hapLayerFiles.add(file);
    LoopLayer meta = new LoopLayer();
    meta.take = currentTake;
    meta.number = 1;
    meta.w = store.w > 0 ? store.w : capW;
    meta.h = store.h > 0 ? store.h : capH;
    meta.path = file != null ? file.getAbsolutePath() : "";
    meta.saved = true;
    meta.blend = blendKind;
    meta.inkPlate = recInkPlate;
    layers.add(meta);
    activeLayer = 0;
  } else {
    // Keep hapLayers on the old background only — no gap, no extra reader.
    beginFlattenAsync(file, blendKind, store, recInkPlate);
  }

  loopReady = true;
  selectedLayer = -1;
  ensureLoopPixels();
  if (first) loopImgHead = -1;
  mode = MODE_PLAY;
  markDirty();
  int takes = undoHist.size() + max(1, layerCount());
  if (recFromStop) {
    recFromStop = false;
    // Keep the frames playing through the Hap load. They come off only after
    // the new picture has faded in over them — otherwise the playback drops out.
    boolean clearFrames = stopClearThisBake && hasStop();
    stopClearThisBake = false;
    if (hasStop()) {
      // Play the stack under the new Hap either way, so the load has no gap.
      // A double-tap wipes the stack once the Hap is in. A single tap leaves it.
      stopAwaitHap = true;
      stopReleaseClears = clearFrames;
      stopCover = 0;
      stopCoverAt = 0;
      stopCoverImg = null;
      if (!stopPlaying) {
        stopPlaying = true;
        stopOrigin = millis();
        stopInvalidateImg();
      }
      if (!clearFrames) dashBakeKeptAt = millis();
    } else {
      stopPlaying = false;
      stopHold = -1;
      stopInvalidateImg();
    }
    note(first
      ? ("Stoptrick baked  ·  length " + fmtSec(loopFrames / (float) capFps)
          + (clearFrames ? "  ·  clear" : ""))
      : (clearFrames ? "Stoptrick baked  ·  clear" : "Stoptrick baked  ·  baking…"));
    luckyPadSyncPlay();
    luckyPadRequestPreview(true);
  } else if (first) {
    beginLoopIntro();
    note("Length locked  " + fmtSec(loopFrames / (float) capFps));
  }
  else note("Overdub  ·  baking new background…");
}

File historyDir() {
  ensureProjectDirs();
  File dir = new File(projectDir, "history");
  dir.mkdirs();
  return dir;
}

LoopHist snapshotLayer(File src, LoopLayer meta, int frames) {
  if (src == null || !src.exists()) return null;
  int take = meta != null ? meta.take : currentTake;
  int blend = meta != null ? meta.blend : blendKind;
  File dest = new File(historyDir(), "layer-" + System.currentTimeMillis() + "-" + take + ".hap1");
  if (!src.renameTo(dest)) {
    try {
      java.nio.file.Files.copy(src.toPath(), dest.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
      src.delete();
    } catch (Exception e) {
      println("History save failed: " + e.getMessage());
      return null;
    }
  }
  return new LoopHist(dest, take, frames, capW, capH, capFps, blend);
}

/** Copy (keep source) into history — used before overdub flatten. */
LoopHist copyFileToHist(File src, LoopLayer meta, int frames) {
  if (src == null || !src.exists()) return null;
  int take = meta != null ? meta.take : currentTake;
  int blend = meta != null ? meta.blend : blendKind;
  File dest = new File(historyDir(), "layer-" + System.currentTimeMillis() + "-" + take + ".hap1");
  try {
    java.nio.file.Files.copy(src.toPath(), dest.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
  } catch (Exception e) {
    println("History copy failed: " + e.getMessage());
    return null;
  }
  return new LoopHist(dest, take, frames, capW, capH, capFps, blend);
}

/** Snapshot whatever is currently playing so Undo can restore the pre-overdub background. */
LoopHist snapshotCurrentComposite() {
  if (layerCount() <= 0 || loopFrames <= 0) return null;
  if (layerCount() == 1) {
    File src = hapLayerFiles.get(0);
    LoopLayer meta = layers.isEmpty() ? null : layers.get(0);
    return copyFileToHist(src, meta, loopFrames);
  }
  File dest = new File(historyDir(), "layer-" + System.currentTimeMillis() + "-snap.hap1");
  if (!bakeCompositeTo(dest)) return null;
  int blend = layers.isEmpty() ? blendKind : layers.get(layers.size() - 1).blend;
  return new LoopHist(dest, currentTake, loopFrames, capW, capH, capFps, blend);
}

/** Delete a Hap file undo does not need. Undo copies already live in history/. */
void discardHapFile(File f) {
  deleteHapNow(f);
}

void deleteHapNow(File f) {
  if (f == null || !f.exists()) return;
  if (!f.delete()) println("Could not delete " + f.getAbsolutePath());
}

void collectHapFiles(File dir, ArrayList<File> into) {
  if (dir == null || !dir.isDirectory()) return;
  File[] kids = dir.listFiles();
  if (kids == null) return;
  for (int i = 0; i < kids.length; i++) {
    File k = kids[i];
    if (k.isDirectory()) collectHapFiles(k, into);
    else if (k.getName().endsWith(".hap1")) into.add(k);
  }
}

boolean fileListed(File[] keep, File f) {
  if (f == null || keep == null) return false;
  String p = pathKey(f);
  for (int i = 0; i < keep.length; i++) {
    File k = keep[i];
    if (k != null && p.equals(pathKey(k))) return true;
  }
  return false;
}

String pathKey(File f) {
  try {
    return f.getCanonicalPath();
  } catch (Exception e) {
    return f.getAbsolutePath();
  }
}

/** Delete project Hap files except the ones still needed for the MP4 archive. */
void deleteLooseHaps(File[] keep) {
  if (!projectOpen || projectDir == null || projectDir.length() == 0) return;
  ArrayList<File> found = new ArrayList<File>();
  collectHapFiles(new File(projectDir, "takes"), found);
  collectHapFiles(new File(projectDir, "history"), found);
  collectHapFiles(new File(projectDir, "bin"), found);
  for (int i = 0; i < found.size(); i++) {
    File f = found.get(i);
    if (fileListed(keep, f)) continue;
    deleteHapNow(f);
  }
}

boolean flattenInFlight() {
  return flattenBusy || flattenReady || flattenIncoming != null || flattenFade > 0.001f;
}

/**
 * Bake off the draw thread using private Hap readers (same files the play
 * head is reading). Old background keeps looping with unchanged playOrigin.
 */
void beginFlattenAsync(File newFile, int newBlend, HapLoopStore spareStore) {
  beginFlattenAsync(newFile, newBlend, spareStore, false);
}

void beginFlattenAsync(File newFile, int newBlend, HapLoopStore spareStore, boolean topInk) {
  if (newFile == null || layerCount() < 1 || hapLayerFiles.isEmpty()) {
    if (spareStore != null) spareStore.close();
    if (newFile != null && newFile.exists()) discardHapFile(newFile);
    return;
  }
  int[] pendingAlpha = recLoopAlpha;
  int[] pendingLive = recLiveAlpha;
  recLoopAlpha = null;
  recLiveAlpha = null;
  cancelFlatten(false);
  flattenCancel.set(false);
  flattenBusy = true;
  flattenReady = false;
  flattenFailed = false;
  flattenIncoming = null;
  flattenFade = 0;
  flattenNewFile = newFile;
  flattenNewBlend = newBlend;
  flattenNewTake = currentTake;
  // Burn Loop-FX into the old plate so the dub matches what you mixed.
  flattenBakeLoopFx = fxAffectLoop && fxStackActive(fxLive);
  flattenFxSnap = flattenBakeLoopFx ? fxSnapshotActive(fxLive) : null;
  if (flattenBakeLoopFx) fxClearOutRuntime();
  // Drop the temporary store's reader — bake reopens the file itself.
  if (spareStore != null) spareStore.close();

  final File oldFile = hapLayerFiles.get(0);
  final int oldBlend = layers.isEmpty() ? blendKind : layers.get(0).blend;
  final boolean baseInk = !layers.isEmpty() && layers.get(0).inkPlate;
  final boolean topIsInk = topInk;
  final int frames = loopFrames;
  final int w = capW;
  final int h = capH;
  final int fps = capFps;
  final int[] bgAlpha = fitLoopAlpha(pendingAlpha, frames);
  final int[] topAlpha = fitLoopAlpha(pendingLive, frames);
  final boolean bakeFx = flattenBakeLoopFx && flattenFxSnap != null && !flattenFxSnap.isEmpty();
  final ArrayList<FxUnit> fxSnap = flattenFxSnap;
  flattenBgAlpha = bgAlpha;
  final File dest = new File(takeFolder(currentTake),
    "layer-" + String.format("%02d", undoHist.size() + 1) + "-flat.hap1");
  if (dest.exists()) dest.delete();
  flattenFile = dest;

  Thread t = new Thread(new Runnable() {
    public void run() {
      ArrayList<HapLoopStore> readers = new ArrayList<HapLoopStore>();
      try {
        HapLoopStore a = new HapLoopStore();
        HapLoopStore b = new HapLoopStore();
        if (!a.openExisting(oldFile) || !b.openExisting(newFile)) {
          flattenFailed = true;
          return;
        }
        readers.add(a);
        readers.add(b);
        int[] blends = new int[] { oldBlend, newBlend };
        if (flattenCancel.get()) {
          flattenFailed = true;
          return;
        }
        if (!bakeCompositeToStores(dest, readers, blends, frames, w, h, fps, bgAlpha, topAlpha,
            bakeFx ? fxSnap : null, baseInk, topIsInk)) {
          flattenFailed = true;
          return;
        }
        if (flattenCancel.get()) {
          if (dest.exists()) dest.delete();
          flattenFailed = true;
          return;
        }
        flattenReady = true;
      } catch (Exception e) {
        flattenFailed = true;
        println("Flatten bake failed: " + e.getMessage());
      } finally {
        for (int i = 0; i < readers.size(); i++) readers.get(i).close();
        flattenBusy = false;
      }
    }
  }, "hap-flatten");
  t.setDaemon(true);
  t.start();
}

/** Snapshot bake used by Undo when more than one live layer still exists. */
boolean bakeCompositeTo(File dest) {
  if (dest == null || loopFrames <= 0 || layerCount() <= 0) return false;
  ArrayList<HapLoopStore> stores = new ArrayList<HapLoopStore>(hapLayers);
  int[] blends = new int[stores.size()];
  for (int i = 0; i < blends.length; i++) {
    blends[i] = (i < layers.size()) ? layers.get(i).blend : BLEND_MULTIPLY;
  }
  return bakeCompositeToStores(dest, stores, blends, loopFrames, capW, capH, capFps, null, null, null, false, false);
}

/**
 * Encode a layer stack into one Hap file.
 * Uses private pixel buffers so the draw thread can keep playing.
 * loopFxSnap: when non-null, burn those FX into the old (background) plate before compositing.
 * baseInk/topInk: explicit Draw plates — never guess from dark Multiply video (causes grain).
 */
boolean bakeCompositeToStores(File dest, ArrayList<HapLoopStore> stores, int[] blends,
    int frames, int w, int h, int fps, int[] baseAlpha, int[] topAlpha, ArrayList<FxUnit> loopFxSnap,
    boolean baseInk, boolean topInk) {
  if (dest == null || stores == null || stores.isEmpty() || frames <= 0) return false;
  int[] pix = new int[w * h];
  int[] scratch = new int[w * h];
  int[] scratchB = stores.size() >= 2 ? new int[w * h] : null;
  boolean bakeFx = loopFxSnap != null && !loopFxSnap.isEmpty();
  HapLoopStore out = new HapLoopStore();
  out.prepare(w, h, fps);
  if (!out.beginRecord(dest)) {
    if (out.failMessage().length() > 0) println(out.failMessage());
    return false;
  }
  for (int f = 0; f < frames; f++) {
    if (flattenCancel.get()) {
      out.cancelRecord();
      if (dest.exists()) dest.delete();
      return false;
    }
    java.util.Arrays.fill(pix, 0xFF000000);
    boolean any = false;
    int baseA = 255;
    if (baseAlpha != null && f < baseAlpha.length) baseA = baseAlpha[f];

    // Two-layer overdub: ink-on-black Hap plates crush Multiply. Prefer video
    // as base and stamp non-black ink on top (Draw-first then camera overdub).
    if (stores.size() == 2 && scratchB != null) {
      HapLoopStore a = stores.get(0);
      HapLoopStore b = stores.get(1);
      boolean gotA = a.copyFrame(f, scratch);
      boolean gotB = b.copyFrame(f, scratchB);
      if (!gotA && !gotB) {
        out.cancelRecord();
        if (dest.exists()) dest.delete();
        return false;
      }
      // Old loop plate → burn Loop-FX (matches FX Affect Loop preview).
      if (bakeFx && gotA) applyFxStackForBake(loopFxSnap, scratch, w, h);
      int topA = 255;
      if (topAlpha != null && f < topAlpha.length) topA = topAlpha[f];
      if (gotA && gotB) {
        boolean aInk = baseInk;
        boolean bInk = topInk;
        if (aInk && !bInk) {
          // Old Draw plate + new camera: video under, ink over.
          if (topA > 0) {
            if (topA >= 255) System.arraycopy(scratchB, 0, pix, 0, pix.length);
            else blendInto(pix, scratchB, topA, BLEND_NORMAL);
          }
          if (baseA > 0) blendInkOnto(pix, scratch, baseA);
          any = topA > 0 || baseA > 0;
        } else if (bInk && !aInk) {
          // Old camera + new Draw plate: video under, ink over.
          if (baseA > 0) {
            if (baseA >= 255) System.arraycopy(scratch, 0, pix, 0, pix.length);
            else blendInto(pix, scratch, baseA, BLEND_NORMAL);
          }
          if (topA > 0) blendInkOnto(pix, scratchB, topA);
          any = topA > 0 || baseA > 0;
        }
      }
      if (!any && gotA) {
        if (baseA >= 255) System.arraycopy(scratch, 0, pix, 0, pix.length);
        else if (baseA > 0) blendInto(pix, scratch, baseA, BLEND_NORMAL);
        any = baseA > 0;
        if (gotB && topA > 0) {
          int blend = (blends != null && blends.length > 1) ? blends[1] : BLEND_MULTIPLY;
          blendInto(pix, scratchB, topA, blend);
          any = true;
        }
      } else if (!any && gotB && topA > 0) {
        if (topA >= 255) System.arraycopy(scratchB, 0, pix, 0, pix.length);
        else blendInto(pix, scratchB, topA, BLEND_NORMAL);
        any = true;
      }
    } else {
      for (int i = 0; i < stores.size(); i++) {
        HapLoopStore src = stores.get(i);
        if (!src.copyFrame(f, scratch)) continue;
        if (bakeFx && i == 0) applyFxStackForBake(loopFxSnap, scratch, w, h);
        // Background loop was ridden with the opacity fader — print that, not full strength.
        if (i == 0 && baseAlpha != null && stores.size() > 1) {
          if (baseA <= 0) {
            any = true;
            continue;
          }
          if (!any && baseA >= 255) System.arraycopy(scratch, 0, pix, 0, pix.length);
          else blendInto(pix, scratch, baseA, BLEND_NORMAL);
          any = true;
          continue;
        }
        // Live overdub rides the live fader. Print it on the new layer.
        int layerA = 255;
        if (topAlpha != null && i == stores.size() - 1 && stores.size() > 1) {
          layerA = f < topAlpha.length ? topAlpha[f] : 255;
        }
        if (layerA <= 0) {
          any = true;
          continue;
        }
        if (!any) {
          if (layerA >= 255) System.arraycopy(scratch, 0, pix, 0, pix.length);
          else blendInto(pix, scratch, layerA, BLEND_NORMAL);
          any = true;
        } else {
          int blend = (blends != null && i < blends.length) ? blends[i] : BLEND_MULTIPLY;
          blendInto(pix, scratch, layerA, blend);
        }
      }
    }
    if (!any) {
      out.cancelRecord();
      if (dest.exists()) dest.delete();
      return false;
    }
    int spins = 0;
    while (!out.offerFrame(pix)) {
      if (flattenCancel.get() || ++spins > 8000) {
        out.cancelRecord();
        if (dest.exists()) dest.delete();
        return false;
      }
      try { Thread.sleep(1); } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        out.cancelRecord();
        if (dest.exists()) dest.delete();
        return false;
      }
    }
  }
  if (!out.finishRecord(frames)) {
    if (dest.exists()) dest.delete();
    return false;
  }
  if (out.frameCount < frames) out.padToFrames(frames);
  out.close();
  return dest.exists();
}

/** Draw-thread: pick up finished bake and crossfade without resetting playOrigin. */
void serviceFlatten() {
  if (flattenFailed) {
    flattenFailed = false;
    File nf = flattenNewFile;
    flattenNewFile = null;
    flattenFile = null;
    flattenReady = false;
    flattenBakeLoopFx = false;
    flattenFxSnap = null;
    fxClearOutRuntime();
    if (nf != null && nf.exists()) discardHapFile(nf);
    if (stopAwaitHap) releaseStopHapHold(false);
    note("Overdub bake failed — previous background kept");
    return;
  }
  if (flattenReady && flattenIncoming == null) {
    flattenReady = false;
    File dest = flattenFile;
    if (dest == null || !dest.exists()) {
      if (stopAwaitHap) releaseStopHapHold(false);
      note("Overdub bake missing");
      flattenNewFile = null;
      return;
    }
    HapLoopStore baked = new HapLoopStore();
    if (!baked.openExisting(dest)) {
      if (baked.failMessage().length() > 0) println(baked.failMessage());
      if (dest.exists()) dest.delete();
      if (flattenNewFile != null && flattenNewFile.exists()) discardHapFile(flattenNewFile);
      flattenNewFile = null;
      flattenFile = null;
      if (stopAwaitHap) releaseStopHapHold(false);
      note("Overdub open failed — previous background kept");
      return;
    }
    flattenIncoming = baked;
    flattenPrintedOpacity = flattenBgAlpha != null;
    flattenFade = 0;
    flattenFadeAt = millis();
    loopImgHead = -1;
    note("Overdub ready  ·  fading in");
  }
  if (flattenIncoming == null) return;
  float t = (millis() - flattenFadeAt) / (float) BAKE_FADE_MS;
  flattenFade = constrain(t, 0, 1);
  loopImgHead = -1; // force per-frame composite during fade
  if (flattenFade >= 0.999f) {
    // Draw one frame of the Hap fully over the frames, then drop them.
    boolean covered = !stopAwaitHap || stopCover >= 0.98f
      || millis() - flattenFadeAt > BAKE_FADE_MS + 80;
    if (covered) commitFlattenSwap();
  }
}

void commitFlattenSwap() {
  HapLoopStore baked = flattenIncoming;
  File dest = flattenFile;
  File newFile = flattenNewFile;
  int keepBlend = flattenNewBlend;
  int keepTake = flattenNewTake > 0 ? flattenNewTake : currentTake;
  boolean printed = flattenPrintedOpacity && baked != null;
  boolean burnedFx = flattenBakeLoopFx && baked != null;
  flattenIncoming = null;
  flattenFile = null;
  flattenNewFile = null;
  flattenFade = 0;
  flattenReady = false;
  flattenBusy = false;
  flattenPrintedOpacity = false;
  flattenBgAlpha = null;
  flattenBakeLoopFx = false;
  flattenFxSnap = null;
  fxClearOutRuntime();
  if (printed) loopOpacity = 1f;

  while (layerCount() > 0) {
    HapLoopStore old = hapLayers.remove(hapLayers.size() - 1);
    File oldFile = hapLayerFiles.remove(hapLayerFiles.size() - 1);
    old.close();
    if (oldFile != null && oldFile.exists() && (dest == null || !oldFile.equals(dest))) discardHapFile(oldFile);
  }
  layers.clear();
  if (newFile != null && newFile.exists() && (dest == null || !newFile.equals(dest))) discardHapFile(newFile);

  if (baked == null) {
    loopReady = false;
    mode = MODE_LIVE;
    if (stopAwaitHap) releaseStopHapHold(false);
    return;
  }
  hapLayers.add(baked);
  hapLayerFiles.add(dest);
  LoopLayer meta = new LoopLayer();
  meta.take = keepTake;
  meta.number = 1;
  meta.w = baked.w;
  meta.h = baked.h;
  meta.path = dest != null ? dest.getAbsolutePath() : "";
  meta.saved = true;
  meta.blend = keepBlend;
  // Flattened composite is full-frame video — never treat as sparse ink again.
  meta.inkPlate = false;
  layers.add(meta);
  activeLayer = 0;
  selectedLayer = -1;
  loopImgHead = -1;
  loopReady = true;
  mode = MODE_PLAY;
  // playOrigin untouched — loop phase / BPM sync preserved
  markDirty();
  if (stopAwaitHap) releaseStopHapHold(true);
  if (burnedFx) {
    // Look is in the Hap now — don't re-apply Loop FX on playback.
    fxAllOffStack(fxLive);
    fxAffectLoop = false;
    fxFbLoop = null;
    fxTrailLoop = null;
    fxClearSlit(FX_TGT_LOOP);
    fxClearRgbDelay(FX_TGT_LOOP);
    loopImgHead = -1;
    syncFlatFxFromLive();
    note("Overdub baked  ·  loop FX burned in  ·  " + (undoHist.size() + 1) + " takes");
  } else {
    note("Overdub baked  ·  " + (undoHist.size() + 1) + " takes");
  }
}

/** Drop the hold. finished=false is a failed load and leaves the stack playing. */
void releaseStopHapHold(boolean finished) {
  if (!stopAwaitHap) return;
  boolean wipe = finished && stopReleaseClears;
  stopAwaitHap = false;
  stopReleaseClears = false;
  stopCover = 0;
  stopCoverAt = 0;
  stopCoverImg = null;
  if (wipe && hasStop()) {
    stopClear(false);
  } else if (finished && hasStop()) {
    // OnlyBake / keep frames: do NOT force stopPlaying=false + stopHold=-1 —
    // that left thumbs in the strip but alpha fell back to onion (often invisible).
    // Stack was playing under the Hap cover fade; keep it playing.
    if (!stopPlaying) {
      stopPlaying = true;
      stopOrigin = millis() - (long) max(0, stopCount() - 1) * stopIntervalMs();
    }
    stopInvalidateImg();
  }
  luckyPadSyncPlay();
  luckyPadRequestPreview(true);
}

boolean stopHapCovering() {
  return stopAwaitHap && stopCover > 0.001f && stopCoverImg != null;
}

int stopHapCoverAlpha() {
  float o = stopCover * shownLoopOpacity();
  return constrain(round(o * 255), 0, 255);
}

void publishStopCoverFrom(int[] src) {
  if (src == null) return;
  int n = capW * capH;
  if (src.length < n) return;
  if (stopCoverImg == null || stopCoverImg.width != capW || stopCoverImg.height != capH
      || stopCoverImg == loopImg) {
    stopCoverImg = createImage(capW, capH, ARGB);
  }
  stopCoverImg.loadPixels();
  arrayCopy(src, 0, stopCoverImg.pixels, 0, n);
  stopCoverImg.updatePixels();
  stopCover = flattenFade;
}

/** First take is already the loop — fade that picture over the frames once it is readable. */
void serviceStopHapCover() {
  if (!stopAwaitHap || flattenInFlight()) return;
  if (!hasLoop() || !syncLoopImage()) return;
  if (stopCoverAt == 0) {
    stopCoverAt = millis();
    stopCoverImg = loopImg;
  }
  stopCover = constrain((millis() - stopCoverAt) / (float) BAKE_FADE_MS, 0, 1);
  if (stopCover >= 0.999f && millis() - stopCoverAt >= BAKE_FADE_MS + 40) {
    releaseStopHapHold(true);
  }
}

void paintHapCoverGfx(PGraphics pg) {
  if (pg == null || !stopHapCovering()) return;
  int a = stopHapCoverAlpha();
  if (a <= 0) return;
  pg.blendMode(BLEND);
  pg.tint(255, a);
  pg.image(stopCoverImg, 0, 0, capW, capH);
  pg.noTint();
}

void paintHapCoverPreview(float x, float y, float w, float h) {
  if (!stopHapCovering()) return;
  int a = stopHapCoverAlpha();
  if (a <= 0) return;
  blendMode(BLEND);
  tint(255, a);
  image(stopCoverImg, x, y, w, h);
  noTint();
}

void blendHapCover(int[] dst) {
  if (dst == null || !stopHapCovering()) return;
  int a = stopHapCoverAlpha();
  if (a <= 0 || stopCoverImg == null) return;
  stopCoverImg.loadPixels();
  if (stopCoverImg.pixels == null || stopCoverImg.pixels.length != dst.length) return;
  blendInto(dst, stopCoverImg.pixels, a, BLEND_NORMAL);
}

void cancelFlatten(boolean binNew) {
  flattenCancel.set(true);
  flattenBusy = false;
  flattenReady = false;
  flattenFailed = false;
  flattenFade = 0;
  flattenPrintedOpacity = false;
  flattenBgAlpha = null;
  flattenBakeLoopFx = false;
  flattenFxSnap = null;
  fxClearOutRuntime();
  if (flattenIncoming != null) {
    flattenIncoming.close();
    flattenIncoming = null;
  }
  if (flattenFile != null && flattenFile.exists()) flattenFile.delete();
  flattenFile = null;
  if (binNew && flattenNewFile != null && flattenNewFile.exists()) discardHapFile(flattenNewFile);
  else if (!binNew && flattenNewFile != null && flattenNewFile.exists()) {
    // leave file for caller
  }
  flattenNewFile = null;
  if (stopAwaitHap) releaseStopHapHold(false);
}

/** Sync fallback used by redo when multiple stores briefly exist. */
boolean flattenPlayLayers() {
  if (layerCount() <= 1) return true;
  if (flattenInFlight()) return false;
  File dest = new File(takeFolder(currentTake),
    "layer-" + String.format("%02d", layerCount()) + "-flat.hap1");
  if (dest.exists()) dest.delete();
  if (!bakeCompositeTo(dest)) return false;

  int keepBlend = layers.isEmpty() ? blendKind : layers.get(layers.size() - 1).blend;
  int keepTake = layers.isEmpty() ? currentTake : layers.get(layers.size() - 1).take;

  while (layerCount() > 0) {
    HapLoopStore old = hapLayers.remove(hapLayers.size() - 1);
    File oldFile = hapLayerFiles.remove(hapLayerFiles.size() - 1);
    old.close();
    if (oldFile != null && oldFile.exists() && !oldFile.equals(dest)) discardHapFile(oldFile);
  }
  layers.clear();

  HapLoopStore baked = new HapLoopStore();
  if (!baked.openExisting(dest)) {
    if (baked.failMessage().length() > 0) println(baked.failMessage());
    if (dest.exists()) dest.delete();
    loopReady = false;
    return false;
  }
  hapLayers.add(baked);
  hapLayerFiles.add(dest);
  LoopLayer meta = new LoopLayer();
  meta.take = keepTake;
  meta.number = 1;
  meta.w = baked.w;
  meta.h = baked.h;
  meta.path = dest.getAbsolutePath();
  meta.saved = true;
  meta.blend = keepBlend;
  layers.add(meta);
  activeLayer = 0;
  selectedLayer = -1;
  loopImgHead = -1;
  loopReady = true;
  return true;
}

void lerpPixels(int[] dst, int[] from, int[] to, float t) {
  if (dst == null || from == null || to == null) return;
  int n = min(dst.length, min(from.length, to.length));
  float u = constrain(t, 0, 1);
  float v = 1f - u;
  for (int i = 0; i < n; i++) {
    int a = from[i];
    int b = to[i];
    int r = (int) (((a >> 16) & 255) * v + ((b >> 16) & 255) * u);
    int g = (int) (((a >> 8) & 255) * v + ((b >> 8) & 255) * u);
    int bl = (int) ((a & 255) * v + (b & 255) * u);
    dst[i] = 0xFF000000 | (r << 16) | (g << 8) | bl;
  }
}

int[] undoStepChoices() {
  return new int[] { 0, 5, 10, 20, 40 };
}

int sanitizeUndoSteps(int n) {
  int[] choices = undoStepChoices();
  int best = DEFAULT_UNDO_STEPS;
  int bestD = 1 << 30;
  for (int i = 0; i < choices.length; i++) {
    int d = abs(choices[i] - n);
    if (d < bestD) {
      bestD = d;
      best = choices[i];
    }
  }
  return best;
}

void setUndoSteps(int n) {
  int next = sanitizeUndoSteps(n);
  if (next == undoSteps) return;
  undoSteps = next;
  trimHist(undoHist);
  trimHist(redoHist);
  markDirty();
  note(undoSteps <= 0 ? "Undo off" : ("Undo  " + undoSteps + " steps"));
}

/** Keep at most undoSteps Hap snapshots. Older steps are deleted. */
void pushHist(ArrayList<LoopHist> stack, LoopHist entry) {
  if (entry == null || entry.file == null) return;
  if (undoSteps <= 0) {
    deleteHapNow(entry.file);
    return;
  }
  stack.add(entry);
  trimHist(stack);
}

void trimHist(ArrayList<LoopHist> stack) {
  int cap = max(0, undoSteps);
  while (stack.size() > cap) {
    LoopHist old = stack.remove(0);
    if (old != null) deleteHapNow(old.file);
  }
}

void clearHist(ArrayList<LoopHist> stack) {
  for (int i = 0; i < stack.size(); i++) {
    LoopHist h = stack.get(i);
    if (h != null) deleteHapNow(h.file);
  }
  stack.clear();
}

void forgetHist(ArrayList<LoopHist> stack) {
  stack.clear();
}

boolean restoreLayer(LoopHist entry) {
  if (entry == null || entry.file == null || !entry.file.exists()) return false;
  File live = new File(takeFolder(entry.take > 0 ? entry.take : ++takeCount),
    "layer-" + String.format("%02d", layerCount() + 1) + ".hap1");
  if (live.exists()) live.delete();
  if (!entry.file.renameTo(live)) {
    try {
      java.nio.file.Files.copy(entry.file.toPath(), live.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
      entry.file.delete();
    } catch (Exception e) {
      note("Undo failed");
      println(e.getMessage());
      return false;
    }
  }
  HapLoopStore store = new HapLoopStore();
  if (!store.openExisting(live)) {
    note("Undo open failed");
    if (store.failMessage().length() > 0) println(store.failMessage());
    return false;
  }
  hapLayers.add(store);
  hapLayerFiles.add(live);
  LoopLayer meta = new LoopLayer();
  meta.take = entry.take > 0 ? entry.take : currentTake;
  meta.number = layerCount();
  meta.w = store.w;
  meta.h = store.h;
  meta.path = live.getAbsolutePath();
  meta.saved = true;
  meta.blend = entry.blend;
  layers.add(meta);
  loopFrames = lockedFrames > 0 ? lockedFrames : store.frameCount;
  if (lockedFrames <= 0) lockedFrames = loopFrames;
  loopReady = true;
  activeLayer = layerCount() - 1;
  selectedLayer = -1;
  ensureLoopPixels();
  loopImgHead = -1;
  mode = MODE_PLAY;
  if (playOrigin == 0) playOrigin = millis();
  return true;
}

void serviceRecord() {
  if (recWait) {
    if (mode != MODE_PLAY || !hasLoop()) {
      recWait = false;
      recWaitHead = -1;
    } else {
      int head = currentHead();
      boolean wrapped = recWaitHead >= 0 && head < recWaitHead;
      recWaitHead = head;
      if (wrapped) {
        recWait = false;
        recWaitHead = -1;
        beginRec();
        luckyPadSyncPlay();
        luckyPadRequestPreview(true);
      }
    }
  }
  if (mode != MODE_REC) return;
  int now = millis();
  int interval = sampleIntervalMs();
  // Never skip sample slots. If the encode queue is full, keep nextSampleAt
  // so the loop length still matches wall-clock recording time.
  int guard = 0;
  while (now >= nextSampleAt && guard++ < 8) {
    if (!sampleRec()) break;
    if (mode != MODE_REC) return;
    nextSampleAt += interval;
  }
}

/**
 * Pixels a live take writes: frozen still while V/FRZ is held, otherwise
 * the updating camera (grade + Live FX).
 */
int[] liveRecordPixels() {
  if (liveFrozen() && liveFreezePixels != null && liveFreezePixels.length >= capW * capH) {
    return liveFreezePixels;
  }
  if (liveFxReady && liveFxImg != null) {
    liveFxImg.loadPixels();
    if (liveFxImg.pixels != null && liveFxImg.pixels.length >= capW * capH) return liveFxImg.pixels;
  }
  if (livePixels != null) {
    ensureRecordPixels();
    return livePixels;
  }
  return null;
}

/** @return true if a frame was accepted into the encode queue */
boolean sampleRec() {
  int target = recTargetFrames();
  if (recFrameCount >= target) {
    commitRec();
    return false;
  }
  if (recFromStop || stopIsRecordSource()) {
    int[] px = stopPixelsForHapBake();
    if (px == null) return false;
    px = stampTextOnRecord(px);
    if (!hapRec.offerFrame(px)) return false;
    noteRecLoopAlpha();
    recFrameCount++;
    return true;
  }
  int[] src = liveRecordPixels();
  if (src == null) return false;
  src = stampTextOnRecord(src);
  if (!hapRec.offerFrame(src)) return false;
  noteRecLoopAlpha();
  recFrameCount++;
  return true;
}

/**
 * Hap/DXT1 drops alpha. Soft white ink (RGB≈255, a small) would encode as an
 * opaque white canvas. Premultiply Draw plates onto black before offerFrame.
 */
int[] stopPixelsForHapBake() {
  int[] px = stopCurrentPixels();
  if (px == null) return null;
  if (!stopHeadIsInkPlate()) return px;
  int[] flat = new int[px.length];
  arrayCopy(px, flat);
  stopFlattenInkOpaque(flat);
  return flat;
}

/** Overdub: loop fader ducks the old plate; live fader prints into the new layer. Stoptrick bake rides the loop fader. */
void armRecLoopAlpha() {
  recLoopAlpha = null;
  recLiveAlpha = null;
  if (!lengthLocked() || !hasLoop()) return;
  int n = max(1, recTargetFrames());
  recLoopAlpha = new int[n];
  java.util.Arrays.fill(recLoopAlpha, -1);
  recLiveAlpha = new int[n];
  java.util.Arrays.fill(recLiveAlpha, -1);
}

void noteRecLoopAlpha() {
  if (recFrameCount < 0) return;
  if (recLoopAlpha != null && recFrameCount < recLoopAlpha.length) {
    recLoopAlpha[recFrameCount] = constrain(round(loopOpacity * 255), 0, 255);
  }
  if (recLiveAlpha != null && recFrameCount < recLiveAlpha.length) {
    // Live overdub: bake the live fader you mixed with. Stoptrick bake follows loop fader.
    int bus = recFromStop ? round(loopOpacity * 255) : round(liveOpacity * 255);
    recLiveAlpha[recFrameCount] = constrain(bus, 0, 255);
  }
}

/** Null when every sampled frame was full opacity — bake stays unchanged. */
int[] fitLoopAlpha(int[] src, int frames) {
  if (src == null || frames <= 0) return null;
  int[] out = new int[frames];
  boolean dim = false;
  int last = 255;
  for (int i = 0; i < frames; i++) {
    int a = (i < src.length && src[i] >= 0) ? src[i] : last;
    if (a < 0) a = 255;
    if (a > 255) a = 255;
    if (a < 255) dim = true;
    last = a;
    out[i] = a;
  }
  return dim ? out : null;
}

/** Loop opacity rises 0→1 once, right after the first take locks. */
void beginLoopIntro() {
  loopIntroOn = true;
  loopIntro = 0;
  loopIntroAt = millis();
}

void endLoopIntro() {
  loopIntroOn = false;
  loopIntro = 1;
}

/** Remember the loop that is on screen, before undo/redo swaps it. */
void captureLoopHistFade() {
  loopHistSrcValid = false;
  if (!hasLoop() || !syncLoopImage() || loopPixels == null) return;
  int n = capW * capH;
  if (loopPixels.length != n) return;
  if (loopHistSrc == null || loopHistSrc.length != n) loopHistSrc = new int[n];
  arrayCopy(loopPixels, loopHistSrc);
  loopHistSrcValid = true;
}

void endLoopHistFade() {
  boolean was = loopHistFade;
  loopHistFade = false;
  loopHistGhost = false;
  loopHistAmt = 0;
  if (was) loopImgHead = -1;
}

/**
 * After the loop stack changes: dissolve from the captured plate into the new one.
 * Nothing left to play → the old plate fades out over live.
 * A loop appearing from empty eases in like the first take.
 */
void startLoopHistFade() {
  endLoopIntro();
  boolean had = loopHistFade;
  loopHistFade = false;
  loopHistGhost = false;
  if (loopHistSrcValid && hasLoop()) {
    loopHistFade = true;
    loopHistGhost = false;
    loopHistAmt = 1;
    loopHistAt = millis();
    loopImgHead = -1;
    return;
  }
  if (loopHistSrcValid && !hasLoop()) {
    int n = capW * capH;
    if (loopHistSrc == null || loopHistSrc.length < n) return;
    if (loopHistImg == null || loopHistImg.width != capW || loopHistImg.height != capH) {
      loopHistImg = createImage(capW, capH, ARGB);
    }
    loopHistImg.loadPixels();
    arrayCopy(loopHistSrc, 0, loopHistImg.pixels, 0, n);
    loopHistImg.updatePixels();
    loopHistFade = true;
    loopHistGhost = true;
    loopHistAmt = 1;
    loopHistAt = millis();
    return;
  }
  if (had) loopImgHead = -1;
  if (hasLoop()) beginLoopIntro();
}

void tickLoopHistFade() {
  if (!loopHistFade) return;
  float t = (millis() - loopHistAt) / (float) LOOP_INTRO_MS;
  if (t >= 1f) {
    endLoopHistFade();
    return;
  }
  loopHistAmt = 1f - t;
}

void tickLoopIntro() {
  if (!loopIntroOn) return;
  float t = (millis() - loopIntroAt) / (float) LOOP_INTRO_MS;
  if (t >= 1f) {
    endLoopIntro();
    return;
  }
  loopIntro = t;
}

/** Display opacity. While a printed-opacity crossfade is on screen, pixels already include it. */
float shownLoopOpacity() {
  float o = loopOpacity;
  if (flattenPrintedOpacity && flattenFade > 0.001f) o = 1f;
  if (loopIntroOn) o *= loopIntro;
  if (loopHistGhost) o *= loopHistAmt;
  return o;
}

void ensureLoopPixels() {
  int n = capW * capH;
  if (loopPixels == null || loopPixels.length != n) loopPixels = new int[n];
  if (layerScratch == null || layerScratch.length != n) layerScratch = new int[n];
  if (layerScratchB == null || layerScratchB.length != n) layerScratchB = new int[n];
  if (loopImg == null || loopImg.width != capW || loopImg.height != capH) {
    loopImg = createImage(capW, capH, ARGB);
    loopImgHead = -1;
  }
}

/**
 * Composite open Hap play layers at current head into loopImg.
 * During async overdub bake we keep serving the old background; once the
 * new bake is open we crossfade at the same playhead (BPM/phase intact).
 */
boolean syncLoopImage() {
  if (!loopAudible()) return false;
  ensureLoopPixels();
  int head = currentHead();
  // Loop FX must re-apply every frame (feedback / slit / fades).
  boolean loopFxOn = fxAffectLoop && fxStackActive(fxLive);
  if (head == loopImgHead && loopImg != null && flattenIncoming == null && !loopHistFade && !loopFxOn) return true;

  java.util.Arrays.fill(loopPixels, 0xFF000000);
  boolean any = false;
  int top = layerCount() - 1;
  if (activeLayer >= 0 && activeLayer < top) top = activeLayer;
  // Hold the previous background while baking / before fade completes.
  if (flattenInFlight() && top > 0) top = 0;
  if (top == 1 && layerCount() >= 2) {
    HapLoopStore a = hapLayers.get(0);
    HapLoopStore b = hapLayers.get(1);
    a.setPlayHead(head);
    b.setPlayHead(head);
    boolean gotA = a.copyFrame(head, layerScratch);
    boolean gotB = b.copyFrame(head, layerScratchB);
    if (gotA && gotB) {
      boolean aInk = layers.size() > 0 && layers.get(0).inkPlate;
      boolean bInk = layers.size() > 1 && layers.get(1).inkPlate;
      if (aInk && !bInk) {
        arrayCopy(layerScratchB, loopPixels);
        blendInkOnto(loopPixels, layerScratch, 255);
        any = true;
      } else if (bInk && !aInk) {
        arrayCopy(layerScratch, loopPixels);
        blendInkOnto(loopPixels, layerScratchB, 255);
        any = true;
      }
    }
    if (!any && gotA) {
      arrayCopy(layerScratch, loopPixels);
      any = true;
      if (gotB) {
        int blend = layers.size() > 1 ? layers.get(1).blend : BLEND_MULTIPLY;
        blendInto(loopPixels, layerScratchB, 255, blend);
      }
    } else if (!any && gotB) {
      arrayCopy(layerScratchB, loopPixels);
      any = true;
    }
  } else {
    for (int i = 0; i <= top; i++) {
      HapLoopStore store = hapLayers.get(i);
      store.setPlayHead(head);
      if (!store.copyFrame(head, layerScratch)) continue;
      if (!any) {
        arrayCopy(layerScratch, loopPixels);
        any = true;
      } else {
        int blend = (i < layers.size()) ? layers.get(i).blend : BLEND_MULTIPLY;
        blendInto(loopPixels, layerScratch, 255, blend);
      }
    }
  }
  if (!any) return false;

  if (flattenIncoming != null && flattenFade > 0.001f) {
    int n = capW * capH;
    if (flattenFadeScratch == null || flattenFadeScratch.length != n) {
      flattenFadeScratch = new int[n];
    }
    flattenIncoming.setPlayHead(head);
    if (flattenIncoming.copyFrame(head, flattenFadeScratch)) {
      if (stopAwaitHap) {
        // Old loop stays under the frames. The new Hap fades in above them.
        publishStopCoverFrom(flattenFadeScratch);
      } else {
        if (flattenPrintedOpacity) {
          int a = constrain(round(loopOpacity * 255), 0, 255);
          if (a < 255) {
            if (flattenHoldScratch == null || flattenHoldScratch.length != n) flattenHoldScratch = new int[n];
            arrayCopy(loopPixels, flattenHoldScratch);
            java.util.Arrays.fill(loopPixels, 0xFF000000);
            if (a > 0) blendInto(loopPixels, flattenHoldScratch, a, BLEND_NORMAL);
          }
        }
        lerpPixels(loopPixels, loopPixels, flattenFadeScratch, flattenFade);
      }
    }
  }

  synchronized (loopComposeLock) {
    if (fxAffectLoop && fxStackActive(fxLive)) {
      applyFxStack(fxLive, loopPixels, capW, capH, FX_TGT_LOOP);
    }
    applyLoopFxCurves(loopPixels);
  }
  if (loopHistFade && !loopHistGhost && loopHistSrcValid && loopHistAmt > 0.001f
      && loopHistSrc != null && loopHistSrc.length == loopPixels.length) {
    float u = 1f - loopHistAmt;
    if (u <= 0.001f) arrayCopy(loopHistSrc, loopPixels);
    else lerpPixels(loopPixels, loopHistSrc, loopPixels, u);
  }
  loopImg.loadPixels();
  arrayCopy(loopPixels, loopImg.pixels);
  loopImg.updatePixels();
  loopImgHead = head;
  return true;
}

int lastLayerClickAt = 0;
String lastLayerClickId = "";

boolean layerDoubleClick(String id) {
  int now = millis();
  boolean twice = id.equals(lastLayerClickId) && now - lastLayerClickAt < 420;
  lastLayerClickAt = now;
  lastLayerClickId = id;
  return twice;
}

void selectLayer(int index) {
  if (index == SEL_STOP) {
    fxCancelNudge();
    selectedLayer = SEL_STOP;
    return;
  }
  if (index < 0 || index >= layerCount()) selectedLayer = -1;
  else selectedLayer = index;
}

void nudgeLayerSelect(int dir) {
  int n = layerCount();
  // Order: layers… → stoptrick → live(-1)
  int pos;
  if (selectedLayer == SEL_STOP) pos = n;
  else if (selectedLayer < 0) pos = n + 1;
  else pos = selectedLayer;
  int max = n + 1; // last slot is live
  pos = constrain(pos + dir, 0, max);
  if (pos < n) selectedLayer = pos;
  else if (pos == n && (hasStop() || stopOnion)) selectedLayer = SEL_STOP;
  else if (pos == n) selectedLayer = -1;
  else selectedLayer = -1;
}

void activateSelectedLayer() {
  if (!hasLoop()) return;
  if (selectedLayer < 0 || selectedLayer >= layerCount()) {
    activeLayer = layerCount() - 1;
    note("All layers");
    return;
  }
  activeLayer = selectedLayer;
  note("Layer  " + (activeLayer + 1));
}

int shownBlend() {
  if (selectedLayer >= 0 && selectedLayer < layers.size()) return layers.get(selectedLayer).blend;
  return blendKind;
}

void setShownBlend(int kind) {
  kind = kind == BLEND_SCREEN ? BLEND_SCREEN : BLEND_MULTIPLY;
  if (selectedLayer >= 0 && selectedLayer < layers.size()) {
    layers.get(selectedLayer).blend = kind;
    loopImgHead = -1;
    return;
  }
  if (blendKind != kind) {
    blendKind = kind;
    markDirty();
  }
}

String blendTargetName() {
  if (selectedLayer == SEL_STOP) return "Stoptrick";
  if (selectedLayer >= 0 && selectedLayer < layers.size()) return "Layer " + (selectedLayer + 1);
  return "Live";
}

boolean popLastLayer(ArrayList<LoopHist> toStack) {
  if (layerCount() <= 0) return false;
  int i = layerCount() - 1;
  HapLoopStore store = hapLayers.remove(i);
  File file = hapLayerFiles.remove(i);
  LoopLayer meta = layers.isEmpty() ? null : layers.remove(layers.size() - 1);
  store.close();
  LoopHist snap = snapshotLayer(file, meta, loopFrames);
  pushHist(toStack, snap);
  activeLayer = layerCount() - 1;
  if (selectedLayer >= layerCount()) selectedLayer = -1;
  loopImgHead = -1;
  if (layerCount() == 0) {
    loopReady = false;
    loopFrames = lengthLocked() ? lockedFrames : 0;
    mode = MODE_LIVE;
  } else {
    loopReady = true;
    mode = MODE_PLAY;
  }
  return true;
}

void undo() {
  recWait = false;
  recWaitHead = -1;
  if (mode == MODE_REC) {
    cancelRecKeepLoop();
    return;
  }
  if (flattenInFlight()) {
    cancelFlatten(true);
    // Drop the just-recorded take; keep playing the previous background.
    if (!undoHist.isEmpty()) {
      LoopHist dropped = undoHist.remove(undoHist.size() - 1);
      // snapshot was a copy of current — discard it, current file still live
      if (dropped != null && dropped.file != null && dropped.file.exists()) dropped.file.delete();
    }
    note("Overdub cancelled  ·  previous background");
    return;
  }
  if (stopSelected() && hasStop()) {
    stopPopLast();
    return;
  }
  // Flattened overdubs: previous backgrounds live in undoHist (not as live readers).
  if (layerCount() == 1 && !undoHist.isEmpty()) {
    captureLoopHistFade();
    HapLoopStore store = hapLayers.remove(0);
    File file = hapLayerFiles.remove(0);
    LoopLayer meta = layers.isEmpty() ? null : layers.remove(0);
    store.close();
    LoopHist snap = snapshotLayer(file, meta, loopFrames);
    pushHist(redoHist, snap);
    LoopHist prev = undoHist.remove(undoHist.size() - 1);
    if (!restoreLayer(prev)) {
      note("Undo failed");
      return;
    }
    startLoopHistFade();
    note("Undo  ·  " + (undoHist.size() + 1) + " takes");
    return;
  }
  if (layerCount() > 0) {
    captureLoopHistFade();
    if (!popLastLayer(redoHist)) return;
    startLoopHistFade();
    note(layerCount() == 0
      ? (lengthLocked()
        ? ("No layers  ·  length locked  " + fmtSec(lockedFrames / (float) capFps))
        : "Loop empty")
      : ("Undo  " + layerCount() + " layers left"));
    return;
  }
  note(lengthLocked() ? "Length still locked — X X to reset" : "Nothing to undo");
}

void redo() {
  recWait = false;
  recWaitHead = -1;
  if (mode == MODE_REC) return;
  if (flattenInFlight()) {
    note("Still baking");
    return;
  }
  if (redoHist.isEmpty()) {
    note("Nothing to redo");
    return;
  }
  // Flattened path: replace the current single play layer with the redo bake.
  if (layerCount() == 1) {
    captureLoopHistFade();
    HapLoopStore store = hapLayers.remove(0);
    File file = hapLayerFiles.remove(0);
    LoopLayer meta = layers.isEmpty() ? null : layers.remove(0);
    store.close();
    LoopHist snap = snapshotLayer(file, meta, loopFrames);
    pushHist(undoHist, snap);
    LoopHist next = redoHist.remove(redoHist.size() - 1);
    if (!restoreLayer(next)) {
      note("Redo failed");
      return;
    }
    startLoopHistFade();
    note("Redo  ·  " + (undoHist.size() + 1) + " takes");
    return;
  }
  captureLoopHistFade();
  LoopHist next = redoHist.remove(redoHist.size() - 1);
  if (!restoreLayer(next)) return;
  if (layerCount() > 1) flattenPlayLayers();
  startLoopHistFade();
  note("Redo  ·  " + (undoHist.size() + layerCount()) + " takes");
}

boolean requestClear() {
  // X X clears the Hap loop (length unlock) and all frame stacks
  // (stoptrick stills, draw plates, live draw canvas).
  boolean loopStuff = hasLoop() || mode == MODE_REC || lengthLocked()
    || !undoHist.isEmpty() || !redoHist.isEmpty();
  boolean frameStuff = stopFrameStackActive() || drawHasInk();
  if (!loopStuff) {
    if (frameStuff) {
      if (millis() - clearArm < 900) {
        clearAllFrameStacks();
        clearArm = 0;
        note("Frame stacks cleared");
      } else {
        clearArm = millis();
        note("Press X again to clear frame stacks");
      }
      return true;
    }
    note("Nothing to clear");
    return false;
  }
  if (millis() - clearArm < 900) {
    // Defer to draw thread — GL texture reads from key/UI threads crash JOGL.
    pendingClearLoop = true;
    clearArm = 0;
  } else {
    clearArm = millis();
    note(frameStuff
      ? "Press X again to clear loop + frames"
      : "Press X again to clear loop");
  }
  return true;
}

// Short dissolve: last program frame → live only after Clear.
static final int CLEAR_FADE_MS = 280;
boolean pendingClearLoop = false;
boolean clearFading = false;
float clearFade = 0; // 1 = hold, 0 = live only
int clearFadeAt = 0;
int[] clearHoldPixels;
PImage clearHoldImg;
PGraphics clearFadeGfx;

/** Must run on the animation/draw thread (after a published frame). */
void servicePendingClear() {
  if (!pendingClearLoop) return;
  pendingClearLoop = false;
  clearAllFrameStacks();
  clearAndArchiveLoop();
}

void beginClearFade() {
  int n = capW * capH;
  if (n < 2) return;
  if (clearHoldPixels == null || clearHoldPixels.length != n) clearHoldPixels = new int[n];
  boolean ok = false;
  // Prefer CPU buffers — avoid loadPixels() on live OpenGL PGraphics.
  if (loopPixels != null && loopPixels.length == n) {
    int la = constrain(round(shownLoopOpacity() * 255), 0, 255);
    if (la >= 255) arrayCopy(loopPixels, clearHoldPixels);
    else {
      java.util.Arrays.fill(clearHoldPixels, 0xFF000000);
      if (la > 0) blendInto(clearHoldPixels, loopPixels, la, BLEND_NORMAL);
    }
    if (liveShowing() && outputIncludesLive()) {
      int[] liveSrc = liveCompositePixelsBase();
      if (liveSrc != null && liveSrc.length == n) {
        int a = constrain(round(liveOpacity * 255), 0, 255);
        if (a > 0) blendInto(clearHoldPixels, liveSrc, a, liveMixBlend());
      }
    }
    ok = true;
  } else if (monitorImg != null && monitorImg.pixels != null && monitorImg.pixels.length == n) {
    arrayCopy(monitorImg.pixels, clearHoldPixels);
    ok = true;
  } else if (gpuGradeActive && viewImage != null && !(viewImage instanceof PGraphics)) {
    try {
      copyFramePixels(viewImage, clearHoldPixels);
      ok = true;
    } catch (Throwable t) {
      ok = false;
    }
  }
  if (!ok) return;
  if (clearHoldImg == null || clearHoldImg.width != capW || clearHoldImg.height != capH) {
    clearHoldImg = createImage(capW, capH, ARGB);
  }
  clearHoldImg.loadPixels();
  arrayCopy(clearHoldPixels, clearHoldImg.pixels);
  clearHoldImg.updatePixels();
  clearFading = true;
  clearFade = 1;
  clearFadeAt = millis();
}

void tickClearFade() {
  if (!clearFading) return;
  float t = (millis() - clearFadeAt) / (float) CLEAR_FADE_MS;
  clearFade = constrain(1f - t, 0, 1);
  if (clearFade <= 0.001f) {
    clearFade = 0;
    clearFading = false;
  }
}

void applyClearFadePixels(int[] neu) {
  if (!clearFading || clearHoldPixels == null || neu == null || clearFade <= 0.001f) return;
  int n = min(neu.length, clearHoldPixels.length);
  float f = clearFade;
  float inv = 1f - f;
  for (int i = 0; i < n; i++) {
    int a = clearHoldPixels[i];
    int b = neu[i];
    int r = (int) (((a >> 16) & 255) * f + ((b >> 16) & 255) * inv);
    int g = (int) (((a >> 8) & 255) * f + ((b >> 8) & 255) * inv);
    int bl = (int) ((a & 255) * f + (b & 255) * inv);
    neu[i] = 0xFF000000 | (r << 16) | (g << 8) | bl;
  }
}

/** GPU path: opaque hold tinted over the new live-only program = crossfade. */
PImage applyClearFadeImage(PImage neu) {
  if (!clearFading || clearHoldImg == null || clearFade <= 0.001f) return neu;
  // Never draw a PGraphics into itself.
  if (neu == clearFadeGfx) return neu;
  clearFadeGfx = ensureFrame(clearFadeGfx);
  clearFadeGfx.beginDraw();
  clearFadeGfx.background(0);
  clearFadeGfx.blendMode(BLEND);
  clearFadeGfx.noTint();
  if (neu != null) clearFadeGfx.image(neu, 0, 0, capW, capH);
  clearFadeGfx.tint(255, constrain(round(clearFade * 255), 0, 255));
  clearFadeGfx.image(clearHoldImg, 0, 0, capW, capH);
  clearFadeGfx.noTint();
  clearFadeGfx.endDraw();
  return clearFadeGfx;
}

void releaseLoopState() {
  layers.clear();
  loopFrames = 0;
  loopReady = false;
  lockedFrames = 0;
  loopImgHead = -1;
  recWait = false;
  recWaitHead = -1;
  endLoopIntro();
  endLoopHistFade();
  activeLayer = -1;
  selectedLayer = -1;
  mode = MODE_LIVE;
}

/**
 * X X: write the playing loop to export/*.mp4, then delete project Hap files.
 * Playback unlocks immediately. The MP4 encode runs off the draw thread.
 * Hap files the encoder still needs stay until the file is written.
 */
void clearAndArchiveLoop() {
  final int frames = loopFrames;
  final int ew = capW;
  final int eh = capH;
  final int efps = max(1, capFps);

  if (hasLoop()) beginClearFade();

  File bakedFile = null;
  int bakedBlend = flattenNewBlend;
  if (frames > 0 && flattenIncoming != null && flattenFile != null && flattenFile.exists()) {
    bakedFile = flattenFile;
    flattenFile = null;
  }

  File[] keepFiles;
  int[] keepBlends;
  if (bakedFile != null) {
    keepFiles = new File[] { bakedFile };
    keepBlends = new int[] { bakedBlend };
  } else if (frames > 0 && layerCount() > 0) {
    File[] tmp = new File[layerCount()];
    int[] tb = new int[layerCount()];
    int n = 0;
    for (int i = 0; i < layerCount(); i++) {
      File f = hapLayerFiles.get(i);
      if (f == null || !f.exists()) continue;
      tmp[n] = f;
      tb[n] = (i < layers.size()) ? layers.get(i).blend : BLEND_MULTIPLY;
      n++;
    }
    keepFiles = new File[n];
    keepBlends = new int[n];
    for (int i = 0; i < n; i++) {
      keepFiles[i] = tmp[i];
      keepBlends[i] = tb[i];
    }
  } else {
    keepFiles = new File[0];
    keepBlends = new int[0];
  }

  cancelFlatten(true);
  if (mode == MODE_REC) hapRec.cancelRecord();
  if (hapRecFile != null && !fileListed(keepFiles, hapRecFile)) deleteHapNow(hapRecFile);
  hapRecFile = null;

  while (layerCount() > 0) {
    HapLoopStore store = hapLayers.remove(hapLayers.size() - 1);
    hapLayerFiles.remove(hapLayerFiles.size() - 1);
    store.close();
  }
  releaseLoopState();
  forgetHist(undoHist);
  forgetHist(redoHist);
  deleteLooseHaps(keepFiles);

  if (keepFiles.length == 0) {
    note("Loop cleared — length unlocked");
    return;
  }
  if (findFfmpeg() == null) {
    exportStatus = "ffmpeg not found";
    note("ffmpeg not found — Hap kept");
    println("Loop archive: ffmpeg not found — Hap kept");
    for (int i = 0; i < keepFiles.length; i++) {
      if (keepFiles[i] != null) println("  " + keepFiles[i].getAbsolutePath());
    }
    return;
  }
  startHapArchive(keepFiles, keepBlends, frames, ew, eh, efps);
}

void startHapArchive(final File[] files, final int[] blends, final int frames, final int w, final int h, final int fps) {
  if (files == null || files.length == 0 || frames < 1 || w < 2 || h < 2) {
    note("Loop cleared — length unlocked");
    return;
  }
  final HapLoopStore[] stores = new HapLoopStore[files.length];
  int n = frames;
  for (int i = 0; i < files.length; i++) {
    stores[i] = new HapLoopStore();
    boolean opened = stores[i].openExisting(files[i]);
    if (!opened || stores[i].w != w || stores[i].h != h || stores[i].frameCount < 1) {
      String why = stores[i].failMessage();
      if (opened) why = "Hap size mismatch";
      for (int j = 0; j <= i; j++) if (stores[j] != null) stores[j].close();
      exportStatus = (why != null && why.length() > 0) ? why : "Hap open failed";
      note("MP4 failed — Hap kept");
      println("Loop archive: " + exportStatus);
      return;
    }
    if (stores[i].frameCount < n) n = stores[i].frameCount;
  }
  final int exportFrames = n;
  snapshotTextForExport();
  archiveBusy = true;
  exportStatus = "Saving MP4…";
  note("Saving loop as MP4…");
  Thread t = new Thread(new Runnable() {
    public void run() {
      File out = null;
      try {
        out = encodeLoopMp4(stores, blends, exportFrames, w, h, fps);
      } catch (Throwable ex) {
        out = null;
        exportStatus = "MP4 failed";
        println("Loop archive failed: " + ex.getMessage());
        ex.printStackTrace();
      } finally {
        for (int i = 0; i < stores.length; i++) {
          if (stores[i] != null) stores[i].close();
        }
        if (out != null && out.exists()) {
          for (int i = 0; i < files.length; i++) deleteHapNow(files[i]);
          exportStatus = out.getName();
          note("Saved  " + out.getName());
          println("Loop archive: " + out.getAbsolutePath());
        } else {
          if (exportStatus == null || exportStatus.length() == 0 || exportStatus.equals("Saving MP4…")) {
            exportStatus = "MP4 failed";
          }
          note("ffmpeg not found".equals(exportStatus) ? "ffmpeg not found — Hap kept" : "MP4 failed — Hap kept");
          println("Loop archive failed; Hap kept");
          for (int i = 0; i < files.length; i++) {
            if (files[i] != null) println("  " + files[i].getAbsolutePath());
          }
        }
        archiveBusy = false;
      }
    }
  }, "hap-archive");
  t.setDaemon(true);
  t.start();
}

void clearLoop() {
  if (hasLoop()) beginClearFade();
  cancelFlatten(true);
  if (mode == MODE_REC) {
    hapRec.cancelRecord();
    if (hapRecFile != null && hapRecFile.exists()) hapRecFile.delete();
    hapRecFile = null;
  }
  while (layerCount() > 0) {
    HapLoopStore store = hapLayers.remove(hapLayers.size() - 1);
    File file = hapLayerFiles.remove(hapLayerFiles.size() - 1);
    store.close();
    if (file != null && file.exists()) {
      File bin = new File(projectDir, "bin");
      bin.mkdirs();
      File dest = new File(bin, "layer-" + System.currentTimeMillis() + ".hap1");
      if (!file.renameTo(dest)) file.delete();
    }
  }
  releaseLoopState();
  clearHist(undoHist);
  clearHist(redoHist);
}

void renderStack(PImage dest, boolean withLive) {
  if (dest == null) return;
  dest.loadPixels();
  int[] dst = dest.pixels;
  boolean base = loopAudible() && syncLoopImage() && loopPixels != null && loopPixels.length == dst.length;
  java.util.Arrays.fill(dst, 0xFF000000);
  if (base) {
    int la = constrain(round(shownLoopOpacity() * 255), 0, 255);
    if (la >= 255) arrayCopy(loopPixels, dst);
    else if (la > 0) blendInto(dst, loopPixels, la, BLEND_NORMAL);
  } else if (loopHistGhost && loopHistSrc != null && loopHistSrc.length == dst.length) {
    int la = constrain(round(shownLoopOpacity() * 255), 0, 255);
    if (la > 0) blendInto(dst, loopHistSrc, la, BLEND_NORMAL);
  }
  // Live under onion so the ghost reads over camera; then current draw ink on top.
  if (withLive && outputIncludesLive()) {
    int[] liveSrc = liveCompositePixels();
    boolean haveLive = liveSrc != null && liveSrc.length == dst.length && liveShowing();
    if (haveLive) {
      int a = constrain(round(liveOpacity * 255), 0, 255);
      if (a > 0) blendInto(dst, liveSrc, a, liveMixBlend());
    }
  }
  // CPU publish path feeds Syphon/beamer — honor external onion toggle.
  int stopA = stopOverlayAlpha(true);
  if (stopA > 0) {
    int[] sp = stopCurrentPixels();
    if (sp != null && sp.length == dst.length) blendInto(dst, sp, stopA, stopOverlayBlend());
  }
  if (withLive && drawModeOn() && drawImg != null) {
    drawImg.loadPixels();
    int inkA = liveBusAlpha();
    if (inkA > 0 && drawImg.pixels != null && drawImg.pixels.length == dst.length) {
      blendInto(dst, drawImg.pixels, inkA, BLEND_NORMAL);
    }
  }
  blendHapCover(dst);
  dest.updatePixels();
}

void blendInto(int[] dst, int[] src, int alpha, int blend) {
  int n = dst.length;
  boolean screen = blend == BLEND_SCREEN;
  boolean normal = blend == BLEND_NORMAL;
  for (int i = 0; i < n; i++) {
    int s = src[i];
    int sa = (s >>> 24) & 255;
    if (sa == 0) continue;
    int a = (sa * alpha + 127) / 255;
    if (a <= 0) continue;
    int d = dst[i];
    int sr = (s >> 16) & 255;
    int sg = (s >> 8) & 255;
    int sb = s & 255;
    int dr = (d >> 16) & 255;
    int dg = (d >> 8) & 255;
    int db = d & 255;
    int mr, mg, mb;
    if (normal) {
      mr = sr;
      mg = sg;
      mb = sb;
    } else if (screen) {
      mr = 255 - ((255 - sr) * (255 - dr) + 127) / 255;
      mg = 255 - ((255 - sg) * (255 - dg) + 127) / 255;
      mb = 255 - ((255 - sb) * (255 - db) + 127) / 255;
    } else {
      mr = (sr * dr + 127) / 255;
      mg = (sg * dg + 127) / 255;
      mb = (sb * db + 127) / 255;
    }
    int r, g, b;
    if (a >= 255) {
      r = mr;
      g = mg;
      b = mb;
    } else {
      int inv = 255 - a;
      r = (mr * a + dr * inv + 127) / 255;
      g = (mg * a + dg * inv + 127) / 255;
      b = (mb * a + db * inv + 127) / 255;
    }
    dst[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
  }
}

/**
 * Fallback only (legacy / export without ink flags). Dark Multiply video must
 * NOT count as ink — that path stamped speckles and looked like grain.
 * Real ink: nearly all black, some bright marks, almost no mid-gray mush.
 */
boolean pixelsLookLikeInkOnBlack(int[] px) {
  if (px == null || px.length < 64) return false;
  int step = max(1, px.length / 4096);
  int black = 0, mid = 0, bright = 0, samples = 0;
  for (int i = 0; i < px.length; i += step) {
    samples++;
    int c = px[i];
    int r = (c >> 16) & 255;
    int g = (c >> 8) & 255;
    int b = c & 255;
    int y = (r * 3 + g * 6 + b) / 10;
    if (y < 8) black++;
    else if (y < 48) mid++;
    else bright++;
  }
  if (samples < 8) return false;
  // ≥94% black, some ink, mid-tones rarer than ink (not DXT mush / dark video).
  return black * 100 >= samples * 94
    && bright >= max(2, samples / 400)
    && mid * 3 <= bright;
}

/** Normal-blend only non-near-black source pixels (recover Hap-cleared ink). */
void blendInkOnto(int[] dst, int[] src, int alpha) {
  if (dst == null || src == null || alpha <= 0) return;
  int n = min(dst.length, src.length);
  for (int i = 0; i < n; i++) {
    int s = src[i];
    int sr = (s >> 16) & 255;
    int sg = (s >> 8) & 255;
    int sb = s & 255;
    if (sr < 10 && sg < 10 && sb < 10) continue;
    int sa = (s >>> 24) & 255;
    if (sa == 0) continue;
    int a = (sa * alpha + 127) / 255;
    if (a <= 0) continue;
    int d = dst[i];
    int dr = (d >> 16) & 255;
    int dg = (d >> 8) & 255;
    int db = d & 255;
    int r, g, b;
    if (a >= 255) {
      r = sr;
      g = sg;
      b = sb;
    } else {
      int inv = 255 - a;
      r = (sr * a + dr * inv + 127) / 255;
      g = (sg * a + dg * inv + 127) / 255;
      b = (sb * a + db * inv + 127) / 255;
    }
    dst[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
  }
}

void disposeHapLoop() {
  cancelFlatten(true);
  hapRec.close();
  for (int i = 0; i < hapLayers.size(); i++) hapLayers.get(i).close();
  hapLayers.clear();
  hapLayerFiles.clear();
}
