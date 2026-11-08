// Stoptrick: frame-by-frame stills from live, looping over the base Hap stack.
// Shoot → stack → play at own fps → Bake onto Hap:
//   layer 1: free length until Bake again; layer 2+: one locked loop.
// Clear frames / C wipes the stoptrick+draw frame stack.
// X X clears the Hap loop and also clears / stops all frame stacks
// (stoptrick stills + draw ink plates + live draw canvas).
// After a bake, frames keep playing until the new Hap has faded over them.

static final int MAX_STOP_FRAMES = 240;
static final int SEL_STOP = -2;

ArrayList<int[]> stopFrames = new ArrayList<int[]>();
/** Parallel to stopFrames: true = draw ink plate (ARGB), false = camera still. */
ArrayList<Boolean> stopFrameInk = new ArrayList<Boolean>();
int stopFps = 6;
boolean stopPlaying = false;
boolean stopOnion = true;
/** Onion strength while shooting (0–1). Drawn over live, under current draw ink. */
float stopOnionAmt = 0.32f;
/** When false, onion is preview-only — Syphon / beamer stay clean while shooting. */
boolean stopOnionExternal = false;
/** After a successful "-" / Bake commit, wipe the stoptrick stack. */
boolean stopClearOnBake = true;
long stopOrigin = 0;
int stopHold = -1; // paused scrub index; -1 = last shot
int stopImgHead = -1;
PImage stopImg;
PImage stopOnionImg; // ink plate with onion alpha baked (GPU-safe)
int[] stopScratch;
/** Cached: current stop head is a draw ink plate (has transparent pixels). */
boolean stopImgIsInkPlate = false;
int stopInkPlateHead = -2;
int stopOnionImgHead = -2;
int stopOnionImgAlpha = -1;

/** Playback framing for the stop frame stack (separate from live cam framing). */
float stopZoom = 1;
float stopPanX = 0;
float stopPanY = 0;
float stopTwist = 0;
PGraphics stopViewGfx; // GPU blit scratch (may be retina density)
PImage stopViewImg;    // CPU capW×capH result for composite / image()
boolean stopViewDirty = true;
int stopViewHead = -1;
float stopViewZoom = -999;
float stopViewPanX, stopViewPanY, stopViewTwist;

void dirtyStopView() {
  stopViewDirty = true;
}

void resetStopFrameView() {
  stopZoom = 1;
  stopPanX = 0;
  stopPanY = 0;
  stopTwist = 0;
  dirtyStopView();
}

void applyStopZoom(float next) {
  next = constrain(next, LIVE_ZOOM_MIN, LIVE_ZOOM_MAX);
  if (abs(next - stopZoom) < 0.0001f) return;
  stopZoom = next;
  dirtyStopView();
  markDirty();
}

void applyStopPan(float x, float y) {
  // No ±1 box clamp — stack framing may leave the preview frame.
  if (abs(x - stopPanX) < 0.0001f && abs(y - stopPanY) < 0.0001f) return;
  stopPanX = x;
  stopPanY = y;
  dirtyStopView();
  markDirty();
}

void applyStopTwist(float deg) {
  float next = deg;
  while (next > 180) next -= 360;
  while (next < -180) next += 360;
  if (abs(next - stopTwist) < 0.01f) return;
  stopTwist = next;
  dirtyStopView();
  markDirty();
}

boolean stopFramingActive() {
  return abs(stopZoom - 1) > 0.001f
    || abs(stopPanX) > 0.001f || abs(stopPanY) > 0.001f
    || abs(stopTwist) > 0.05f;
}

/**
 * Rebuild framed stop view when head or framing changes (camera stills only).
 * Always land in stopViewImg at capW×capH — P2D retina buffers are denser and
 * must not be fed straight into blendInto (length mismatch → silent no-op).
 */
void ensureStopViewFramed() {
  if (!syncStopImage() || stopImg == null) return;
  if (stopHeadIsInkPlate()) return;
  if (!stopViewDirty && stopViewImg != null && stopViewHead == stopImgHead
      && abs(stopViewZoom - stopZoom) < 0.0001f
      && abs(stopViewPanX - stopPanX) < 0.0001f
      && abs(stopViewPanY - stopPanY) < 0.0001f
      && abs(stopViewTwist - stopTwist) < 0.01f) {
    return;
  }
  stopViewGfx = ensureFrame(stopViewGfx);
  frameCoverInto(stopViewGfx, stopImg, false, stopZoom, stopPanX, stopPanY, stopTwist);
  if (stopViewImg == null || stopViewImg.width != capW || stopViewImg.height != capH) {
    stopViewImg = createImage(capW, capH, ARGB);
  }
  stopViewImg.loadPixels();
  copyFramePixels(stopViewGfx, stopViewImg.pixels);
  stopViewImg.updatePixels();
  stopViewHead = stopImgHead;
  stopViewZoom = stopZoom;
  stopViewPanX = stopPanX;
  stopViewPanY = stopPanY;
  stopViewTwist = stopTwist;
  stopViewDirty = false;
}

/**
 * Framed camera still before Live FX (playback base for the Live FX bus).
 * Ink plates are returned as-is; null when empty.
 */
int[] stopFramedPixelsRaw() {
  if (!hasStop()) return null;
  int head = constrain(stopHead(), 0, stopCount() - 1);
  if (stopHeadIsInkPlate()) return stopFrames.get(head);
  if (!stopFramingActive()) return stopFrames.get(head);
  ensureStopViewFramed();
  if (stopViewImg != null) {
    stopViewImg.loadPixels();
    if (stopViewImg.pixels != null && stopViewImg.pixels.length == capW * capH) {
      return stopViewImg.pixels;
    }
  }
  return stopFrames.get(head);
}

/**
 * Play uses the Live-FX plate for camera stills only.
 * Draw ink must stay sparse ARGB — flattening over black (Live FX bus) would
 * erase loop/live underlay on Mac Draw and LuckyPad during Play.
 */
boolean stopPlayUsesLiveFxPlate() {
  return stopPlaying && liveFxReady && liveFxImg != null && !stopHeadIsInkPlate();
}

/** Image used when drawing the stop stack (framed camera still, or raw ink plate). */
PImage stopDisplayImage() {
  if (!syncStopImage() || stopImg == null) return null;
  if (stopPlayUsesLiveFxPlate()) return liveFxImg;
  if (stopHeadIsInkPlate()) return stopImg;
  if (!stopFramingActive()) return stopImg;
  ensureStopViewFramed();
  return stopViewImg != null ? stopViewImg : stopImg;
}

boolean hasStop() {
  return !stopFrames.isEmpty();
}

/** Majority of stack frames are Draw ink plates (for Hap ink-path metadata). */
boolean stopStackMostlyInk() {
  if (stopFrameInk == null || stopFrameInk.isEmpty()) return false;
  int ink = 0;
  for (int i = 0; i < stopFrameInk.size(); i++) {
    if (stopFrameInk.get(i)) ink++;
  }
  return ink * 2 >= stopFrameInk.size();
}

int stopCount() {
  return stopFrames.size();
}

int stopIntervalMs() {
  return max(1, round(1000f / max(1, stopFps)));
}

boolean stopSelected() {
  return selectedLayer == SEL_STOP;
}

/** Playing, paused hold, or onion of last frame while shooting. */
boolean stopVisible() {
  if (!hasStop()) return false;
  return stopPlaying || stopHold >= 0 || stopOnion;
}

/** Space samples stoptrick instead of live when the stack is playing. */
boolean stopIsRecordSource() {
  return stopPlaying && hasStop();
}

/** Stoptrick bake in progress (recording, or waiting for the loop wrap). */
boolean stopBakeOn() {
  return (mode == MODE_REC && recFromStop) || (recWait && stopIsRecordSource());
}

int stopHead() {
  int n = stopCount();
  if (n <= 0) return 0;
  if (!stopPlaying) {
    if (stopHold < 0) return n - 1;
    return constrain(stopHold, 0, n - 1);
  }
  long elapsed = millis() - stopOrigin;
  if (elapsed < 0) elapsed = 0;
  int f = (int) (elapsed / stopIntervalMs());
  int m = f % n;
  if (m < 0) m += n;
  return m;
}

void ensureStopImg() {
  if (stopImg == null || stopImg.width != capW || stopImg.height != capH) {
    stopImg = createImage(capW, capH, ARGB);
    stopImgHead = -1;
  }
  int n = capW * capH;
  if (stopScratch == null || stopScratch.length != n) stopScratch = new int[n];
}

void stopInvalidateImg() {
  stopImgHead = -1;
  stopInkPlateHead = -2;
  stopOnionImgHead = -2;
  stopOnionImgAlpha = -1;
  dirtyStopView();
}

boolean syncStopImage() {
  if (!hasStop()) return false;
  ensureStopImg();
  int head = constrain(stopHead(), 0, stopCount() - 1);
  if (head == stopImgHead && stopImg != null) return true;
  int[] src = stopFrames.get(head);
  if (src == null || src.length != stopImg.pixels.length) return false;
  stopImg.loadPixels();
  arrayCopy(src, stopImg.pixels);
  stopImg.updatePixels();
  stopImgHead = head;
  stopImgIsInkPlate = stopFrameIsInk(head);
  stopInkPlateHead = head;
  stopOnionImgHead = -2;
  return true;
}

boolean stopFrameIsInk(int head) {
  if (head < 0 || head >= stopCount()) return false;
  if (head < stopFrameInk.size()) return stopFrameInk.get(head);
  // Legacy / unmatched: detect sparse ARGB
  return stopPixelsAreInkPlate(stopFrames.get(head));
}

/** Draw commits store sparse ARGB; camera shots are opaque. Sample for alpha holes. */
boolean stopPixelsAreInkPlate(int[] px) {
  if (px == null || px.length == 0) return false;
  int n = px.length;
  int step = max(1, n / 8192);
  for (int i = 0; i < n; i += step) {
    if (((px[i] >>> 24) & 255) < 255) return true;
  }
  return ((px[n - 1] >>> 24) & 255) < 255;
}

boolean stopHeadIsInkPlate() {
  if (!hasStop()) return false;
  int head = constrain(stopHead(), 0, stopCount() - 1);
  if (head == stopInkPlateHead) return stopImgIsInkPlate;
  stopImgIsInkPlate = stopFrameIsInk(head);
  stopInkPlateHead = head;
  return stopImgIsInkPlate;
}

/**
 * Ink-plate onion for GPU: bake strength into per-pixel alpha.
 * tint()+image() on ARGB often drops large opaque fills (rects) while soft stamps survive.
 */
PImage stopOnionPlate(int alpha) {
  if (!syncStopImage() || stopImg == null) return null;
  alpha = constrain(alpha, 0, 255);
  // Camera stills: Live-FX plate while playing. Draw ink: keep sparse stopImg.
  PImage src = stopImg;
  if (stopPlayUsesLiveFxPlate()) src = liveFxImg;
  else if (!stopHeadIsInkPlate()) return stopDisplayImage();
  if (alpha >= 255) return src;
  if (src == stopImg && stopOnionImg != null && stopOnionImgHead == stopImgHead && stopOnionImgAlpha == alpha) {
    return stopOnionImg;
  }
  if (stopOnionImg == null || stopOnionImg.width != capW || stopOnionImg.height != capH) {
    stopOnionImg = createImage(capW, capH, ARGB);
  }
  src.loadPixels();
  stopOnionImg.loadPixels();
  int n = src.pixels.length;
  for (int i = 0; i < n; i++) {
    int s = src.pixels[i];
    int sa = (s >>> 24) & 255;
    if (sa == 0) {
      stopOnionImg.pixels[i] = 0;
      continue;
    }
    int na = (sa * alpha + 127) / 255;
    if (na <= 0) stopOnionImg.pixels[i] = 0;
    else stopOnionImg.pixels[i] = (na << 24) | (s & 0x00FFFFFF);
  }
  stopOnionImg.updatePixels();
  stopOnionImgHead = stopImgHead;
  stopOnionImgAlpha = alpha;
  return stopOnionImg;
}

int[] stopCurrentPixels() {
  if (!hasStop()) return null;
  int head = constrain(stopHead(), 0, stopCount() - 1);
  // Camera stills on the Live FX bus while playing — not Draw ink plates.
  if (stopPlayUsesLiveFxPlate()) {
    liveFxImg.loadPixels();
    if (liveFxImg.pixels != null && liveFxImg.pixels.length == capW * capH) {
      return liveFxImg.pixels;
    }
  }
  if (stopHeadIsInkPlate()) return stopFrames.get(head);
  // Framed playback pixels for onion / bake / composite.
  if (!stopFramingActive()) return stopFrames.get(head);
  ensureStopViewFramed();
  if (stopViewImg != null) {
    stopViewImg.loadPixels();
    if (stopViewImg.pixels != null && stopViewImg.pixels.length == capW * capH) {
      return stopViewImg.pixels;
    }
  }
  return stopFrames.get(head);
}

/** Sparse Draw ink → opaque over black (Live FX expect solid plates). */
void stopFlattenInkOpaque(int[] px) {
  if (px == null) return;
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    int a = (c >>> 24) & 255;
    if (a >= 255) {
      px[i] = c | 0xFF000000;
      continue;
    }
    if (a <= 0) {
      px[i] = 0xFF000000;
      continue;
    }
    float u = a / 255f;
    px[i] = packRgb(((c >> 16) & 255) * u, ((c >> 8) & 255) * u, (c & 255) * u);
  }
}

void stopPushFrame(int[] frame) {
  stopPushFrame(frame, false);
}

void stopPushFrame(int[] frame, boolean inkPlate) {
  if (frame == null) return;
  if (stopCount() >= MAX_STOP_FRAMES) {
    note("Stoptrick full  ·  " + MAX_STOP_FRAMES + " frames");
    return;
  }
  stopFrames.add(frame);
  stopFrameInk.add(inkPlate);
  stopHold = -1;
  stopInvalidateImg();
  selectedLayer = SEL_STOP;
  if (stopPlaying) {
    // Keep phase continuous when shooting into a running loop.
    stopOrigin = millis() - (long) (stopCount() - 1) * stopIntervalMs();
  }
}

void stopCapture() {
  if (!liveValid && sourceMode != SRC_TEST) {
    note("No source");
    return;
  }
  if (stopCount() >= MAX_STOP_FRAMES) {
    note("Stoptrick full  ·  " + MAX_STOP_FRAMES + " frames");
    return;
  }
  // Bake the same pixels the preview shows: grade + Live FX (+ live curve).
  ensureRecordPixels();
  prepareLiveFx(); // no-op if already built this frame
  int[] src = null;
  if (liveFxReady && liveFxImg != null) {
    liveFxImg.loadPixels();
    src = liveFxImg.pixels;
  } else if (livePixels != null) {
    src = livePixels;
  }
  if (src == null) {
    note("No frame");
    return;
  }
  int[] frame = new int[src.length];
  arrayCopy(src, frame);
  stopPushFrame(frame);
  note("Shot  " + stopCount());
}

/** Play / hold / any committed frames on the shared stoptrick+draw stack. */
boolean stopFrameStackActive() {
  return stopPlaying || stopHold >= 0 || hasStop();
}

void stopFrameStackPlayback() {
  if (!stopPlaying && stopHold < 0) return;
  stopPlaying = false;
  stopHold = -1;
  stopInvalidateImg();
  luckyPadSyncPlay();
  luckyPadRequestPreview(true);
}

/** Wipe stoptrick+draw frame stack and the live draw canvas. */
void clearAllFrameStacks() {
  boolean hadStack = hasStop() || stopPlaying || stopHold >= 0;
  boolean hadDraw = drawHasInk() || (drawImg != null && drawDirty);
  if (hasStop() || stopPlaying || stopHold >= 0) stopClear(false);
  else stopFrameStackPlayback();
  if (drawImg != null) drawClearCanvas();
  if (hadStack || hadDraw) {
    luckyPadSyncPlay();
    luckyPadRequestPreview(true);
  }
}

void stopTogglePlay() {
  if (!hasStop()) {
    note("No stoptrick frames");
    luckyPadSyncPlay();
    return;
  }
  if (stopPlaying) {
    // Freeze on the frame that is showing now — not the last shot.
    stopHold = stopHead();
    stopPlaying = false;
    stopInvalidateImg();
    selectedLayer = SEL_STOP;
    note("Stoptrick hold  ·  " + (stopHold + 1) + "/" + stopCount());
  } else {
    // Resume from the held frame so play doesn't jump.
    int n = stopCount();
    int from = stopHold >= 0 ? constrain(stopHold, 0, n - 1) : 0;
    stopPlaying = true;
    stopOrigin = millis() - (long) from * stopIntervalMs();
    stopHold = -1;
    stopInvalidateImg();
    selectedLayer = SEL_STOP;
    note("Stoptrick play  ·  " + stopCount() + " @ " + stopFps + " fps");
  }
  luckyPadSyncPlay();
  luckyPadRequestPreview(true);
}

void stopStep(int dir) {
  if (!hasStop()) return;
  if (stopPlaying) stopPlaying = false;
  int n = stopCount();
  int head = stopHead();
  stopHold = (head + dir) % n;
  if (stopHold < 0) stopHold += n;
  stopInvalidateImg();
  selectedLayer = SEL_STOP;
  note("Frame  " + (stopHold + 1) + " / " + n);
}

void stopSelectFrame(int index) {
  if (!hasStop()) return;
  int n = stopCount();
  if (index < 0 || index >= n) return;
  if (stopPlaying) stopPlaying = false;
  stopHold = index;
  stopInvalidateImg();
  selectedLayer = SEL_STOP;
}

void stopPopLast() {
  if (!hasStop()) {
    note("No stoptrick frames");
    return;
  }
  int last = stopFrames.size() - 1;
  stopFrames.remove(last);
  if (last < stopFrameInk.size()) stopFrameInk.remove(last);
  stopInvalidateImg();
  if (!hasStop()) {
    stopPlaying = false;
    stopHold = -1;
    if (selectedLayer == SEL_STOP) selectedLayer = -1;
    note("Stoptrick empty");
  } else {
    if (stopHold >= stopCount()) stopHold = -1;
    note("Removed  ·  " + stopCount() + " left");
  }
}

void stopClear() {
  stopClear(true);
}

/** Wipe the stoptrick stack. announce=false leaves the current status line. */
void stopClear(boolean announce) {
  if (!hasStop() && !stopPlaying) return;
  stopAwaitHap = false;
  stopCover = 0;
  stopCoverAt = 0;
  stopCoverImg = null;
  stopFrames.clear();
  stopFrameInk.clear();
  stopPlaying = false;
  stopHold = -1;
  // Clear frames → identity framing (pan / zoom / twist / pinch).
  resetStopFrameView();
  framePinchOn = false;
  frameDragOn = false;
  stopInvalidateImg();
  stopImg = null;
  stopOnionImg = null;
  if (selectedLayer == SEL_STOP) selectedLayer = -1;
  if (announce) note("Stoptrick cleared");
  luckyPadSyncPlay();
  luckyPadRequestPreview(true);
}

void stopSetFps(int fps) {
  fps = constrain(fps, 1, 25);
  if (stopFps == fps) return;
  int head = stopHead();
  stopFps = fps;
  if (stopPlaying && hasStop()) {
    stopOrigin = millis() - (long) head * stopIntervalMs();
  }
  stopInvalidateImg();
  markDirty();
  note("Stoptrick  " + stopFps + " fps");
}

boolean stopFpsNudgeLatched = false;

/** Opt = faster, Ctrl = slower — when stoptrick is the selected layer. */
void stopNudgeFps(int dir) {
  // Ignore OS key-repeat while the modifier is held.
  if (stopFpsNudgeLatched) return;
  stopFpsNudgeLatched = true;
  stopSetFps(stopFps + (dir < 0 ? -1 : 1));
}

void stopClearFpsNudgeLatch() {
  stopFpsNudgeLatched = false;
}

/** Cmd alone toggles onion when stoptrick is selected. */
void stopToggleOnion() {
  setStopOnion(!stopOnion);
}

void setStopOnion(boolean on) {
  if (stopOnion == on) return;
  stopOnion = on;
  markDirty();
  luckyPadSyncOnion();
  luckyPadRequestPreview(true);
  note(stopOnion ? "Onion skin on" : "Onion skin off");
}

void stopResetBuffers() {
  stopFrames.clear();
  stopFrameInk.clear();
  stopPlaying = false;
  stopHold = -1;
  stopImg = null;
  stopOnionImg = null;
  stopViewGfx = null;
  stopViewImg = null;
  stopScratch = null;
  resetStopFrameView();
  stopInvalidateImg();
  stopImgIsInkPlate = false;
  if (selectedLayer == SEL_STOP) selectedLayer = -1;
}

/** Preview / local stoptrick alpha. */
int stopOverlayAlpha() {
  return stopOverlayAlpha(false);
}

/**
 * Stoptrick overlay alpha — same in Stoptrick and Draw.
 * Play / hold (frame stack) → LIVE fader.
 * Recorded Hap loop → LOOP fader (via shownLoopOpacity in the loop plate).
 * Onion while shooting: stopOnionAmt × liveOpacity; optional on external.
 */
int stopOverlayAlpha(boolean forExternal) {
  if (!hasStop()) return 0;
  // Frame-stack play / scrub hold — LIVE mix, not the loop fader.
  if (stopPlaying || stopHold >= 0) {
    return constrain(round(liveOpacity * 255), 0, 255);
  }
  // Bake without play: keep stack readable under the Hap cover (loop fader).
  if (stopBakeOn()) {
    return constrain(round(shownLoopOpacity() * 255), 0, 255);
  }
  if (!stopOnion) return 0;
  if (forExternal && !stopOnionExternal) return 0;
  int base = constrain(round(stopOnionAmt * 255), 0, 255);
  if (base <= 0) return 0;
  return constrain(round(base * liveOpacity), 0, 255);
}

void stopToggleOnionExternal() {
  stopOnionExternal = !stopOnionExternal;
  markDirty();
  note(stopOnionExternal ? "Onion on external" : "Onion preview only");
}

/**
 * Play and onion use Multiply/Screen over a loop base.
 * Draw ink plates (rect/ellipse/etc. with transparency) must stay Normal —
 * Multiply/Screen treats clear pixels as black and punches out the underlay.
 */
int stopOverlayBlend() {
  if (stopHeadIsInkPlate()) return BLEND_NORMAL;
  if (loopAudible() && hasLoop()) return blendKind;
  return BLEND_NORMAL;
}

/**
 * Live opacity: Multiply/Screen over a visible loop base; Normal when fading live
 * alone (no loop / loop at 0%) so the slider dims continuously against black.
 */
int liveMixBlend() {
  if (loopAudible() && hasLoop() && loopOpacity > 0.001f) return blendKind;
  return BLEND_NORMAL;
}
