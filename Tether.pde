TetherClient tether;
PImage tetherImg;
long tetherSeenSeq = -1;
int[] tetherCopy;

float tetherFocus = 0.5;
float tetherBias = 0;
boolean tetherLocked = false;
boolean tetherAutoFocus = true;
boolean tetherAutoExposure = true;
boolean tetherSuppress = false;
int tetherUserUntil = 0;
int tetherCam = 1;
String[] tetherCams = new String[0];
boolean tetherFocusAssist = true;
boolean tetherPushedModes = false;
float tetherReticleX = -1;
float tetherReticleY = -1;
int tetherReticleUntil = 0;

void ensureTether() {
  // Java TCP on fixed port 7878 — paint/ref need the same socket path.
  if (!H264Dec.loaded) {
    H264Dec.load(sketchPath("data/libh264dec.dylib"));
    if (!H264Dec.loaded && H264Dec.fail.length() > 0) println(H264Dec.fail);
  }
  if (tether == null) tether = new TetherClient();
}

void startTether() {
  ensureTether();
  stopCamera();
  stopSyphonClient();
  tetherSeenSeq = -1;
  if (!tether.running) tether.start();
  inputError = tether.connected ? "" : "Looking for LuckyTether on the phone…";
  // Mirror comes from per-source memory (default off for tether).
}

void stopTether() {
  if (tether != null) tether.stop();
  tetherImg = null;
  tetherSeenSeq = -1;
  tetherReticleX = -1;
  tetherPushedModes = false;
}

void markTetherUser() {
  tetherUserUntil = millis() + 900;
  tetherSuppress = true;
}

boolean tetherCanApplyStatus() {
  return millis() >= tetherUserUntil;
}

void ensureTetherImage(int w, int h) {
  // createImage is always density-1 with pixels.length == w*h.
  // createGraphics(P2D) inherits retina density — writing w*h into a 2w×2h
  // buffer left a squashed strip at the top (preview + beamer).
  if (tetherImg != null && tetherImg.width == w && tetherImg.height == h
      && tetherImg.pixels != null && tetherImg.pixels.length >= w * h) {
    return;
  }
  tetherImg = createImage(w, h, ARGB);
}

void refreshTetherFrame() {
  if (tether == null || !tether.running) return;
  long seq = tether.frameSeq.get();
  if (seq == tetherSeenSeq) return;
  tetherCopy = tether.copyFrame(tetherCopy);
  if (tetherCopy == null) return;
  int w = tether.frameW;
  int h = tether.frameH;
  if (w < 2 || h < 2) return;
  if (tetherCopy.length < w * h) return;
  ensureTetherImage(w, h);
  tetherImg.loadPixels();
  arrayCopy(tetherCopy, 0, tetherImg.pixels, 0, w * h);
  tetherImg.updatePixels();
  try {
    g.removeCache(tetherImg);
  } catch (Exception e) {
  }
  tetherSeenSeq = seq;
  inputError = "";
  liveFrameDirty = true;
}

void syncTetherStatus() {
  if (tether == null) return;
  if (!tether.connected) {
    tetherPushedModes = false;
    if (sourceMode == SRC_TETHER) inputError = tether.status;
    return;
  }
  if (!tetherPushedModes) {
    tetherPushedModes = true;
    markTetherUser();
    tetherSend("{\"c\":\"af\",\"v\":" + (tetherAutoFocus ? 1 : 0) + "}");
    tetherSend("{\"c\":\"ae\",\"v\":" + (tetherAutoExposure ? 1 : 0) + "}");
    if (!tetherAutoFocus) tetherSend("{\"c\":\"focus\",\"v\":" + tetherNum(tetherFocus, 4) + "}");
    tetherSend("{\"c\":\"bias\",\"v\":" + tetherNum(tetherBias, 3) + "}");
  }
  if (tetherCanApplyStatus()) {
    if (tether.lensPos >= 0 && tether.lensPos <= 1) tetherFocus = tether.lensPos;
    tetherBias = constrain(tether.bias, -2, 2);
    tetherLocked = tether.locked != 0;
    if (tether.af >= 0) tetherAutoFocus = tether.af != 0;
    if (tether.ae >= 0) tetherAutoExposure = tether.ae != 0;
    else if (tether.locked != 0) tetherAutoExposure = false;
    tetherCam = tether.cam;
  }
  if (tether.cams != null && tether.cams.length > 0) tetherCams = tether.cams;
  if (tetherSuppress && tetherCanApplyStatus()) tetherSuppress = false;
}

String tetherNum(float v, int decimals) {
  // Always '.' — Processing nf() can emit ',' under German locale and break JSON.
  return String.format(java.util.Locale.US, "%." + decimals + "f", v);
}

void tetherSend(String json) {
  ensureTether();
  tether.sendControl(json);
}

boolean tetherLive() {
  return tether != null && tether.running && tether.connected;
}

/** LuckyTether is camera-only — never arm phone paint (ink is LuckyPad on iPad). */
void tetherPaintArm(boolean on) {
  tetherPaintArmedSent = false;
  if (tetherLive()) tetherSend("{\"c\":\"paint\",\"v\":0}");
}

int tetherLoopPushAt = 0;
PImage tetherRefPlate;
volatile boolean tetherLoopPushBusy = false;
Thread tetherLoopPushThread;

/** In-memory JPEG — never touch the filesystem on the draw path. */
byte[] tetherEncodeJpeg(int[] argb, int w, int h, float quality) throws Exception {
  return TetherClient.encodeJpeg(argb, w, h, quality);
}

/** No Mac→phone video — reverse JPEGs delayed the live cam. */
void tetherPushOnion() {
}

/** Disabled — Mac→phone video starved the live cam on the same TCP socket. */
void tetherPushLoopUnderlay() {
}

boolean tetherPaintArmedSent = false;

void tetherSetFocus(float v) {
  markTetherUser();
  tetherFocus = constrain(v, 0, 1);
  tetherAutoFocus = false;
  tetherLocked = !tetherAutoFocus && !tetherAutoExposure;
  tetherSend("{\"c\":\"focus\",\"v\":" + tetherNum(tetherFocus, 4) + "}");
}

void tetherSetBias(float v) {
  markTetherUser();
  tetherBias = constrain(v, -2, 2);
  tetherSend("{\"c\":\"bias\",\"v\":" + tetherNum(tetherBias, 3) + "}");
}

void tetherSetAutoFocus(boolean on) {
  markTetherUser();
  tetherAutoFocus = on;
  tetherLocked = !tetherAutoFocus && !tetherAutoExposure;
  if (on) tetherSend("{\"c\":\"af\",\"v\":1}");
  else tetherSend("{\"c\":\"focus\",\"v\":" + tetherNum(tetherFocus, 4) + "}");
  markDirty();
}

void tetherSetAutoExposure(boolean on) {
  markTetherUser();
  tetherAutoExposure = on;
  tetherLocked = !tetherAutoFocus && !tetherAutoExposure;
  tetherSend("{\"c\":\"ae\",\"v\":" + (on ? 1 : 0) + "}");
  markDirty();
}

void tetherToggleLock() {
  markTetherUser();
  boolean lock = !tetherLocked;
  tetherAutoFocus = !lock;
  tetherAutoExposure = !lock;
  tetherLocked = lock;
  if (lock) {
    tetherSend("{\"c\":\"lock\",\"v\":1}");
  } else {
    tetherSend("{\"c\":\"lock\",\"v\":0}");
  }
}

void tetherSetCam(int idx) {
  markTetherUser();
  tetherCam = idx;
  tetherReticleX = -1;
  tetherSend("{\"c\":\"cam\",\"v\":" + idx + "}");
}

boolean tetherLensEnabled(int idx) {
  if (tetherCams == null || tetherCams.length == 0) return idx == 1;
  String a = idx == 0 ? "0.5x" : idx == 2 ? "2x" : "1x";
  String b = idx == 0 ? "0.5×" : idx == 2 ? "2×" : "1×";
  for (int i = 0; i < tetherCams.length; i++) {
    if (tetherCams[i].equals(a) || tetherCams[i].equals(b)) return true;
  }
  return false;
}

void tetherTapNormalized(float nx, float ny) {
  markTetherUser();
  // Focus-assist tap only — do not flip Auto focus / Auto exposure on.
  tetherReticleX = constrain(nx, 0, 1);
  tetherReticleY = constrain(ny, 0, 1);
  tetherReticleUntil = millis() + 1600;
  tetherSend("{\"c\":\"tap\",\"x\":" + tetherNum(tetherReticleX, 4)
    + ",\"y\":" + tetherNum(tetherReticleY, 4) + "}");
}

/** Image-normalized tap from stage click (letterboxed cover). */
boolean tetherTapAtStage(float mx, float my) {
  if (!tetherFocusAssist || sourceMode != SRC_TETHER) return false;
  if (drawModeOn()) return false;
  if (previewIw < 2 || previewIh < 2) return false;
  if (mx < previewIx || my < previewIy || mx > previewIx + previewIw || my > previewIy + previewIh) return false;
  float aspect = tetherImg != null && tetherImg.height > 0
    ? tetherImg.width / (float) tetherImg.height
    : capW / (float) capH;
  float viewAspect = previewIw / previewIh;
  float ix = previewIx, iy = previewIy, iw = previewIw, ih = previewIh;
  if (viewAspect > aspect) {
    iw = previewIh * aspect;
    ix = previewIx + (previewIw - iw) * 0.5f;
  } else {
    ih = previewIw / aspect;
    iy = previewIy + (previewIh - ih) * 0.5f;
  }
  if (mx < ix || my < iy || mx > ix + iw || my > iy + ih) return false;
  float nx = (mx - ix) / iw;
  float ny = (my - iy) / ih;
  tetherTapNormalized(nx, ny);
  note("Focus " + round(nx * 100) + "% · " + round(ny * 100) + "%");
  return true;
}

void drawTetherReticle() {
  if (tetherReticleX < 0 || millis() > tetherReticleUntil) return;
  if (previewIw < 2) return;
  float aspect = tetherImg != null && tetherImg.height > 0
    ? tetherImg.width / (float) tetherImg.height
    : capW / (float) capH;
  float viewAspect = previewIw / previewIh;
  float ix = previewIx, iy = previewIy, iw = previewIw, ih = previewIh;
  if (viewAspect > aspect) {
    iw = previewIh * aspect;
    ix = previewIx + (previewIw - iw) * 0.5f;
  } else {
    ih = previewIw / aspect;
    iy = previewIy + (previewIh - ih) * 0.5f;
  }
  float cx = ix + tetherReticleX * iw;
  float cy = iy + tetherReticleY * ih;
  float s = 28;
  float a = map(constrain(tetherReticleUntil - millis(), 0, 1600), 0, 1600, 40, 220);
  noFill();
  stroke(color(#e8c547), a);
  strokeWeight(1.5);
  rect(cx - s * 0.5f, cy - s * 0.5f, s, s, 3);
  noStroke();
}
