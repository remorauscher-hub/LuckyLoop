/**
 * LuckyLoop
 * Space starts recording. The next press saves the loop and plays it.
 * The live image sits on top with Multiply or Screen.
 * Each further recording becomes another layer.
 *
 * Libraries (sketchbook): Video, Syphon
 * iPhone: LuckyTether (SRC_TETHER), Continuity webcam, or Syphon.
 * iPad: LuckyPad — Draw ink over USB / same network (separate from Tether).
 */

import processing.video.*;
import codeanticode.syphon.*;
import java.awt.GraphicsDevice;
import java.awt.GraphicsEnvironment;
import java.awt.Rectangle;

static final int SRC_CAM = 0;
static final int SRC_SYPHON = 1;
static final int SRC_TEST = 2;
static final int SRC_TETHER = 3;

static final int TEST_CHECK = 0;
static final int TEST_BARS = 1;
static final int TEST_GRID = 2;

static final int MODE_LIVE = 0;
static final int MODE_REC = 1;
static final int MODE_PLAY = 2;
static final int MODE_DUB = 3; // unused — kept so old settings/UI ids don't break

static final int BLEND_MULTIPLY = 0;
static final int BLEND_SCREEN = 1;
static final int BLEND_NORMAL = 2;

static final int SCALE_FIT = 0;
static final int SCALE_FILL = 1;
static final int SCALE_ONE = 2;

static final int MAX_LAYERS = 256; // soft UI cap only — overdub is unlimited in engine
static final int MAX_SECONDS = 60;

int sourceMode = SRC_CAM;
int testPattern = TEST_CHECK;
int mode = MODE_LIVE;
int blendKind = BLEND_MULTIPLY;

int capW = 1920;
int capH = 1080;
int capFps = 25;

float liveOpacity = 1;
float loopOpacity = 1;
boolean liveInOutput = true;
boolean mirror = true;
boolean syphonOut = true;
boolean blackout = false;       // target (button / MIDI)
float blackoutAmt = 0;          // 0 = program, 1 = solid black
float blackoutFadeFrom = 0;
int blackoutFadeAt = 0;
static final int BLACKOUT_FADE_MS = 220;
PGraphics blackoutGfx;
boolean showGrid = false;
/** Operator inset of the framed camera before grade and FX. Never recorded. */
boolean rawPipDesktop = true;
/** Same inset on the external screen only — not Syphon, not the loop. */
boolean rawPipExternal = false;
/** 0..1 opacity of the external inset. Eases when the toggle changes. */
float rawPipExtAmt = 0;
float rawPipExtFrom = 0;
int rawPipExtAt = 0;
static final int RAW_PIP_FADE_MS = 1500;
PGraphics rawPipTex;
float rawPipX, rawPipY, rawPipW, rawPipH;
boolean settingsOpen = false;
boolean outputFullscreen = true;
/** AWT GraphicsDevice id of the selected external screen, e.g. "Display 4". */
String outputDisplayId = "";
boolean beamerOpen = false;

String cameraName = "";
String inputError = "";
String hudNote = "";
int hudNoteUntil = 0;
int clearArm = 0;
boolean spaceLatch = false;
boolean enterLatch = false;
boolean zeroLatch = false;
int zeroTapAt = 0;
/** V / k-live piano hold: press = freeze, release = restore. */
int freezeHoldN = 0;
boolean freezeHoldRestore = true;
boolean freezeKeyLatch = false;
boolean freezeMouseLatch = false;
boolean pendingShoot = false;
boolean settingsDirty = false;
int lastSave = 0;
volatile boolean beamerClosedPending = false;
boolean bootBeamer = false;
int beamerReopenAt = 0;

PFont uiFont;
PFont font10;
PFont font11;
PFont font12;
PImage monitorImg;
PImage outputImg;
PImage blackImg;
PImage liveFreezeImg;
int[] livePixels;
int[] liveFreezePixels;
boolean liveValid = false;

final Object pubLock = new Object();
int[] published;
int publishedW;
int publishedH;

volatile GpuOutput gpuOut;
volatile boolean beamerOpening;
PImage beamerPresent;
ArrayList<Hit> hits = new ArrayList<Hit>();

float sliderX, sliderY, sliderW;
boolean draggingOpacity = false;
int dragCorner = -1;
int activeCorner = 0;
float previewBoxX, previewBoxY, previewBoxW, previewBoxH;

void settings() {
  // Usable desktop only — keep Mac menu bar (clock) + Dock visible.
  // Size here in settings(); never call surface.setSize/setLocation/setResizable
  // after the P3D/JOGL animator starts (NEWT deadlock on macOS).
  // P3D/NEWT: size() is the drawing surface; the OS title bar sits OUTSIDE that,
  // so subtract chrome or the window overflows and macOS auto-hides the menu bar.
  final int WIN_CHROME_H = 52; // macOS title bar + small safety margin
  final int MENU_BAR_H = 37;   // fallback when insets are 0 at launch
  int w = displayWidth;
  int h = max(640, displayHeight - MENU_BAR_H - WIN_CHROME_H);
  try {
    java.awt.GraphicsEnvironment ge = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment();
    java.awt.GraphicsDevice gd = ge.getDefaultScreenDevice();
    java.awt.Rectangle b = gd.getDefaultConfiguration().getBounds();
    java.awt.Insets in = java.awt.Toolkit.getDefaultToolkit()
      .getScreenInsets(gd.getDefaultConfiguration());
    int top = max(in.top, MENU_BAR_H);
    int bot = max(in.bottom, 0);
    w = max(1024, b.width - in.left - in.right);
    h = max(640, b.height - top - bot - WIN_CHROME_H);
  } catch (Throwable ignored) {
  }
  size(w, h, P3D);
  pixelDensity(displayDensity());
}

void setup() {
  surface.setTitle("LuckyLoop");
  hint(DISABLE_DEPTH_TEST);
  frameRate(60);
  loadUiFonts();
  initMidiBinds();
  initMidiInput();
  initCurves();
  clampDisplay();
  allocateBuffers();
  resetCornersIfNeeded();
  thread("scanInputs");
  queueMidiScan();
  MacMenu.load(dataPath("libmacmenu.dylib"));
  if (!MacMenu.loaded && MacMenu.fail.length() > 0) println(MacMenu.fail);
  else if (MacMenu.loaded) {
    MacMenu.install();
    MacMenu.keepDesktopChrome();
  }
  bootProject();
  ensureAllFxRacks();
  startLuckyPad(); // browse early — USB iPad ready when Draw opens
  if (beamerOpen) {
    bootBeamer = true;
    beamerOpen = false;
  }
  println("LuckyLoop ready. Space records.");
}

public void dispose() {
  flushNotesIfDirty();
  disposeHapLoop();
  stopLuckyPad();
  stopTether();
  if (CamCtl.loaded) {
    try {
      CamCtl.releaseStage();
    } catch (Throwable t) {
    }
  }
  if (MidiCtl.loaded) {
    try { MidiCtl.stop(); } catch (Throwable t) {}
  }
  closeMidi();
  super.dispose();
}

void loadUiFonts() {
  int d = max(1, (int) pixelDensity);
  String face = dataPath("SourceCodePro-Medium.otf");
  if (!new java.io.File(face).exists()) face = dataPath("SourceCodePro-Regular.otf");
  if (!new java.io.File(face).exists()) face = dataPath("RobotoMono-Regular.ttf");
  if (!new java.io.File(face).exists()) face = "Menlo";
  font10 = makeUiFont(face, 11 * d);
  font11 = makeUiFont(face, 13 * d);
  font12 = makeUiFont(face, 15 * d);
  uiFont = font11;
  textFont(font11, 13);
}

PFont makeUiFont(String face, float size) {
  try {
    return createFont(face, size, true);
  } catch (RuntimeException e) {
    return createFont("Menlo", size, true);
  }
}

void ui(int px) {
  textFont(px <= 10 ? font10 : px >= 12 ? font12 : font11, px);
}

boolean inputsApplied = false;
volatile boolean camerasReady = false;

void scanInputs() {
  camerasScanning = true;
  try {
    ensureCamCtl();
    for (int i = 0; i < 6; i++) {
      refreshCameras();
      if (cameras != null && cameras.length > 0) break;
      delay(700);
    }
    refreshSyphon();
  } catch (Throwable t) {
    inputError = "Cameras: " + t.getMessage();
    println(t);
  }
  camerasReady = true;
  camerasScanning = false;
  println("Cameras: " + cameras.length);
  System.out.flush();
}

void refreshInputsAsync() {
  if (camerasScanning) return;
  camerasScanning = true;
  camerasReady = false;
  inputError = "";
  note("Refreshing inputs");
  thread("scanInputsRefresh");
}

void scanInputsRefresh() {
  try {
    ensureCamCtl();
    refreshCameras();
    refreshSyphon();
  } catch (Throwable t) {
    inputError = "Refresh: " + t.getMessage();
    println(t);
  }
  camerasReady = true;
  camerasScanning = false;
  if (sourceMode == SRC_CAM) startCamera();
  else if (sourceMode == SRC_SYPHON) connectSyphon();
  else if (sourceMode == SRC_TETHER) startTether();
  note(cameras.length + " camera" + (cameras.length == 1 ? "" : "s")
    + ", " + syEntries.size() + " Syphon");
  println("Cameras: " + cameras.length + "  Syphon: " + syEntries.size());
  System.out.flush();
}

void draw() {
  try {
    drawFrame();
  } catch (Exception e) {
    e.printStackTrace();
    note("Error, see console");
  }
}

void drawFrame() {
  bootNotesIfNeeded();
  if (!inputsApplied && camerasReady) {
    inputsApplied = true;
    applySource();
  }
  if (syphonOut && server == null && frameCount > 5) ensureSyphonServer();
  if (bootBeamer && frameCount >= 45) {
    bootBeamer = false;
    openBeamer();
  }
  if (beamerReopenAt > 0 && frameCount >= beamerReopenAt) {
    beamerReopenAt = 0;
    openBeamer();
  }
  if (beamerClosedPending) {
    beamerClosedPending = false;
    closeBeamer();
    settingsDirty = true;
  }
  serviceBeamer();

  serviceMidi();
  serviceCameraWatchdog();
  serviceCameraIdentity();
  serviceHardware();
  if (sourceMode == SRC_TETHER) syncTetherStatus();
  serviceDrawPad();
  serviceLiveFraming();
  serviceTextPlace();
  serviceMacMenu();

  // Quiet vertical wash — preview stays the focus.
  noStroke();
  for (int i = 0; i < height; i += 2) {
    float t = i / (float) height;
    fill(lerpColor(color(#0b0b0d), color(#121214), t));
    rect(0, i, width, 2);
  }
  hits.clear();
  if (slds != null) slds.clear();
  if (mapFrames != null) mapFrames.clear();
  if (nums != null) nums.clear();
  refreshLive();
  applyGrade();
  holdCamGrade();
  tickInputFade();
  servicePendingClear();
  tickClearFade();
  tickBlackoutFade();
  tickRawPipExternalFade();
  tickFxFades();
  tickTextFades();
  tickFxNudge();
  tickFxCmdTap();
  prepareLiveFx();
  updateInputFadeView();
  // Shoot on Enter is deferred here so capture runs on the draw thread
  // (external key events + key-repeat must not allocate/GL mid-handler).
  if (pendingShoot) {
    pendingShoot = false;
    if (drawModeOn()) drawCommit();
    else stopCapture();
  }
  serviceRecord();
  serviceFlatten();
  serviceStopHapCover();
  tickLoopIntro();
  tickLoopHistFade();
  publishFrames();
  if (beamerOpen && gpuOut != null && beamerPresent != null) {
    gpuOut.present(beamerPresent, rawPipExternalImage());
  }
  storeFeedback();
  drawInterface();

  String hot = hitTest(mouseX, mouseY);
  if (fineId != null || curveDrag >= 0 || frameDragOn || framePinchOn || textPlaceDrag
      || (textPlaceOn && notesModeOn() && overLivePreview(mouseX, mouseY))) cursor(MOVE);
  else if (textLineOn
      || (notesModeOn() && !textPlaceOn && overLivePreview(mouseX, mouseY)
          && (textSel < 0 || textHitField(mouseX, mouseY) < 0))) cursor(CROSS);
  else if (editId != null || fxFilterFocus
      || (hot != null && (hot.startsWith("num-") || hot.equals("fx-filter")))
      || overNotesEditor(mouseX, mouseY)) cursor(TEXT);
  else cursor(hot != null || dragCorner >= 0 || (liveFramingAllowed() && overLivePreview(mouseX, mouseY)) ? HAND : ARROW);
  flushSettings(false);
}

public void exit() {
  flushNotesIfDirty();
  stopDrawPad();
  stopFramePad();
  stopCamera();
  stopSyphonClient();
  stopLuckyPad();
  stopTether();
  if (gpuOut != null) gpuOut.close();
  super.exit();
}

void note(String s) {
  hudNote = s;
  hudNoteUntil = millis() + 2400;
}

void markDirty() {
  settingsDirty = true;
}

void flushSettings(boolean force) {
  boolean notesDirty = textStoreDirty();
  if (!settingsDirty && !notesDirty) return;
  if (!force && millis() - lastSave < 500) return;
  lastSave = millis();
  if (settingsDirty) {
    settingsDirty = false;
    saveSettings();
  }
  flushNotesIfDirty();
}

void allocateBuffers() {
  livePixels = new int[capW * capH];
  rawPixels = new int[capW * capH];
  java.util.Arrays.fill(livePixels, 0xFF101114);
  java.util.Arrays.fill(rawPixels, 0xFF101114);
  feedbackBuf = null;
  gradeTmp = null;
  fxFbLive = null;
  fxFbLoop = null;
  fxFbOut = null;
  fxTrailLive = null;
  fxTrailLoop = null;
  fxTrailOut = null;
  fxScratch = null;
  fxScratch2 = null;
  liveFxImg = null;
  liveFxReady = false;
  liveFeatherImg = null;
  liveFeatherPixels = null;
  liveFeatherFrame = -1;
  liveFreezeImg = null;
  liveFreezePixels = null;
  inputHoldImg = null;
  inputHoldPixels = null;
  inputFadeImg = null;
  inputFading = false;
  inputFade = 0;
  clearHoldImg = null;
  clearHoldPixels = null;
  clearFadeGfx = null;
  blackoutGfx = null;
  clearFading = false;
  clearFade = 0;
  pendingClearLoop = false;
  liveValid = false;
  loopPixels = null;
  loopImg = null;
  loopImgHead = -1;
  stopResetBuffers();
  drawResetBuffers();
  monitorImg = createImage(capW, capH, ARGB);
  outputImg = createImage(capW, capH, ARGB);
  blackImg = createImage(capW, capH, RGB);
  blackImg.loadPixels();
  java.util.Arrays.fill(blackImg.pixels, 0xFF000000);
  blackImg.updatePixels();
  scaleGfx = null;
  liveCropGfx = null;
  stopViewGfx = null;
  stopViewImg = null;
  liveCropEdit = false;
  liveCropDrag = -1;
  testGfx = null;
  releaseGradeGpu();
}

void publish(int[] src) {
  synchronized (pubLock) {
    if (published == null || published.length != src.length) published = new int[src.length];
    System.arraycopy(src, 0, published, 0, src.length);
    publishedW = capW;
    publishedH = capH;
  }
}

public boolean copyPublished(int[] dest) {
  synchronized (pubLock) {
    if (published == null || dest == null || dest.length != published.length) return false;
    System.arraycopy(published, 0, dest, 0, dest.length);
    return true;
  }
}

public int publishedWidth() {
  synchronized (pubLock) { return publishedW; }
}

public int publishedHeight() {
  synchronized (pubLock) { return publishedH; }
}

boolean blackoutSolid() {
  return blackoutAmt >= 0.999f;
}

boolean blackoutVisible() {
  return blackoutAmt > 0.001f;
}

void setBlackout(boolean on) {
  if (on == blackout) return;
  blackout = on;
  blackoutFadeFrom = blackoutAmt;
  blackoutFadeAt = millis();
}

void toggleBlackout() {
  setBlackout(!blackout);
}

void tickBlackoutFade() {
  float target = blackout ? 1 : 0;
  if (abs(blackoutAmt - target) < 0.0005f) {
    blackoutAmt = target;
    return;
  }
  float t = constrain((millis() - blackoutFadeAt) / (float) BLACKOUT_FADE_MS, 0, 1);
  t = t * t * (3f - 2f * t);
  blackoutAmt = lerp(blackoutFadeFrom, target, t);
  if (t >= 1) blackoutAmt = target;
}

/** Darken program toward black by blackoutAmt (GPU / image path). */
PImage applyBlackoutImage(PImage src) {
  if (blackoutAmt < 0.001f) return src;
  if (blackoutAmt >= 0.999f) return blackImg;
  if (src == null) return blackImg;
  if (src == blackoutGfx) return src;
  blackoutGfx = ensureFrame(blackoutGfx);
  blackoutGfx.beginDraw();
  blackoutGfx.background(0);
  blackoutGfx.blendMode(BLEND);
  blackoutGfx.tint(255, constrain(round((1f - blackoutAmt) * 255), 0, 255));
  blackoutGfx.image(src, 0, 0, capW, capH);
  blackoutGfx.noTint();
  blackoutGfx.endDraw();
  return blackoutGfx;
}

/** Whether live (camera) belongs in the program composite. */
boolean outputIncludesLive() {
  if (blackoutSolid()) return false;
  // Frame-stack play normally owns the LIVE fader (camera off — stack is the plate).
  // Draw + Live underlay: keep the camera under the playing frames (ink reads on live).
  if (stopPlaying && hasStop()) {
    if (drawModeOn() && drawLiveUnderlay && !liveFrozen()) return true;
    return false;
  }
  // Draw: no-loop always wants live; over a loop FRZ/checkbox gate via drawWantsLiveUnderlay.
  if (!drawWantsLiveUnderlay()) return false;
  return true;
}

/** Live-bus mix, 0–255. Camera, draw ink, and text share this fader. */
int liveBusAlpha() {
  return constrain(round(liveOpacity * 255), 0, 255);
}

boolean liveFrozen() {
  return !liveInOutput;
}

/**
 * Freeze holds the last live look on the monitor and in the live take.
 * Draw never uses the freeze plate (loop / stoptrick onion are the underlays).
 */
boolean liveFreezeOnMonitor() {
  if (!liveFrozen()) return false;
  if (drawModeOn()) return false;
  return true;
}

void setLiveInOutput(boolean on) {
  if (on == liveInOutput) return;
  if (!on) snapLiveFreeze();
  liveInOutput = on;
  markDirty();
}

void toggleLiveInOutput() {
  setLiveInOutput(!liveInOutput);
  note(liveInOutput ? "LIVE ON" : "LIVE FREEZE");
}

/** Framed camera before grade and FX. Display-only — recording reads the graded bus. */
PImage rawCameraImage() {
  if (!liveValid || sourceGfx == null || sourceGfx.width < 2 || sourceGfx.height < 2) return null;
  return sourceGfx;
}

PImage camGradeHold;

/** Camera grade after applyGrade, before Live FX overwrites the CPU pixels. */
void holdCamGrade() {
  if (gpuGradeActive && gradedView != null) return;
  if (!rawPipDesktop && rawPipExtAmt < 0.004f) return;
  if (!liveValid || livePixels == null) return;
  int n = capW * capH;
  if (livePixels.length < n) return;
  if (camGradeHold == null || camGradeHold.width != capW || camGradeHold.height != capH) {
    camGradeHold = createImage(capW, capH, ARGB);
  }
  camGradeHold.loadPixels();
  arrayCopy(livePixels, 0, camGradeHold.pixels, 0, n);
  camGradeHold.updatePixels();
}

/** Framed camera with the full cam grade: curve, light, color, detail. No FX. */
PImage camSettingsImage() {
  if (gpuGradeActive && gradedView != null && gradedView.width > 1) return gradedView;
  if (camGradeHold != null && camGradeHold.width == capW && camGradeHold.height == capH) return camGradeHold;
  return rawCameraImage();
}

PImage desktopPipImage() {
  return camSettingsImage();
}

void placeRawPip(float x, float y, float w, float h) {
  float pw = constrain(w * 0.22f, 88, min(340, w * 0.46f));
  float ph = pw * capH / (float) max(1, capW);
  if (ph > h * 0.46f) {
    ph = h * 0.46f;
    pw = ph * capW / (float) max(1, capH);
  }
  rawPipX = x + 10;
  rawPipY = y + 10;
  rawPipW = pw;
  rawPipH = ph;
}

void setRawPipDesktop(boolean on) {
  if (rawPipDesktop == on) return;
  rawPipDesktop = on;
  markDirty();
  note(on ? "raw-preview" : "raw-preview off");
}

void setRawPipExternal(boolean on) {
  if (rawPipExternal == on) return;
  rawPipExternal = on;
  rawPipExtFrom = rawPipExtAmt;
  rawPipExtAt = millis();
  markDirty();
  note(on ? "raw-preview external" : "raw-preview external off");
}

void tickRawPipExternalFade() {
  float target = rawPipExternal ? 1 : 0;
  if (abs(rawPipExtAmt - target) < 0.0005f) {
    rawPipExtAmt = target;
    return;
  }
  float t = constrain((millis() - rawPipExtAt) / (float) RAW_PIP_FADE_MS, 0, 1);
  t = t * t * (3f - 2f * t);
  rawPipExtAmt = lerp(rawPipExtFrom, target, t);
  if (t >= 1) rawPipExtAmt = target;
}

/**
 * Small inset for the external window only.
 * Drawn as its own quad in GpuOutput — the program texture is not copied or modified,
 * so the loop recorder and Syphon never see it.
 */
PImage rawPipExternalImage() {
  float show = rawPipExtAmt * (1f - blackoutAmt);
  if (show < 0.004f) return null;
  PImage raw = camSettingsImage();
  if (raw == null) return null;
  int pw = constrain(round(capW * 0.22f), 96, 640);
  int ph = max(54, round(pw * capH / (float) max(1, capW)));
  if (rawPipTex == null || rawPipTex.width != pw || rawPipTex.height != ph) {
    try {
      rawPipTex = createGraphics(pw, ph, P2D);
      int scale = rawPipTex.pixelWidth > 0 ? max(1, rawPipTex.pixelWidth / max(1, rawPipTex.width)) : 1;
      rawPipTex.pixelDensity = scale;
    } catch (Throwable t) {
      rawPipTex = null;
      return null;
    }
  }
  int a = constrain(round(show * 255), 0, 255);
  if (a < 2 || rawPipTex == null) return null;
  rawPipTex.beginDraw();
  rawPipTex.background(0, 0);
  rawPipTex.blendMode(BLEND);
  rawPipTex.imageMode(CORNER);
  rawPipTex.tint(255, a);
  rawPipTex.image(raw, 0, 0, pw, ph);
  rawPipTex.noTint();
  rawPipTex.noFill();
  rawPipTex.stroke(255, a);
  rawPipTex.strokeWeight(max(1f, pw / 160f));
  rawPipTex.rect(0.5f, 0.5f, pw - 1f, ph - 1f);
  rawPipTex.noStroke();
  rawPipTex.fill(255, a);
  rawPipTex.textAlign(LEFT, CENTER);
  if (font10 != null) rawPipTex.textFont(font10, 10);
  String lab = "raw-preview";
  float tw = (font10 != null ? rawPipTex.textWidth(lab) : 72) + 10;
  rawPipTex.fill(0, min(160, a));
  rawPipTex.rect(0, 0, tw, 16);
  rawPipTex.fill(255, a);
  rawPipTex.text(lab, 5, 8);
  rawPipTex.endDraw();
  return rawPipTex;
}

/** Piano freeze (V / keyboard GUI): press holds a still, release restores prior live/freeze. */
void beginFreezeHold() {
  if (freezeHoldN == 0) {
    freezeHoldRestore = liveInOutput;
    setLiveInOutput(false);
    note("LIVE FREEZE");
  }
  freezeHoldN++;
}

void endFreezeHold() {
  if (freezeHoldN <= 0) return;
  freezeHoldN--;
  if (freezeHoldN > 0) return;
  setLiveInOutput(freezeHoldRestore);
  note(liveInOutput ? "LIVE ON" : "LIVE FREEZE");
}

void clearFreezeHolds() {
  if (freezeHoldN > 0) {
    freezeHoldN = 0;
    setLiveInOutput(freezeHoldRestore);
  }
  freezeKeyLatch = false;
  freezeMouseLatch = false;
}

/** Hold the current graded / FX live look as a still. */
void snapLiveFreeze() {
  int n = capW * capH;
  if (n < 1) return;
  if (liveFreezePixels == null || liveFreezePixels.length != n) liveFreezePixels = new int[n];
  if (liveFxReady && liveFxImg != null) {
    liveFxImg.loadPixels();
    arrayCopy(liveFxImg.pixels, 0, liveFreezePixels, 0, min(n, liveFxImg.pixels.length));
  } else if (gpuGradeActive && gradedView != null) {
    copyFramePixels(gradedView, liveFreezePixels);
  } else if (livePixels != null && livePixels.length == n) {
    arrayCopy(livePixels, liveFreezePixels);
  } else {
    java.util.Arrays.fill(liveFreezePixels, 0xFF101114);
  }
  if (liveFreezeImg == null || liveFreezeImg.width != capW || liveFreezeImg.height != capH) {
    liveFreezeImg = createImage(capW, capH, ARGB);
  }
  liveFreezeImg.loadPixels();
  arrayCopy(liveFreezePixels, liveFreezeImg.pixels);
  liveFreezeImg.updatePixels();
}

/** Pixels used when compositing the live layer (updating or frozen), before edge feather. */
int[] liveCompositePixelsBase() {
  if (liveFreezeOnMonitor() && liveFreezePixels != null) return liveFreezePixels;
  if (inputFading && inputFadeImg != null && inputFade > 0.001f) {
    inputFadeImg.loadPixels();
    return inputFadeImg.pixels;
  }
  // Draw CPU stack needs livePixels; GPU grade usually only keeps gradedView.
  ensureRecordPixels();
  if (liveValid && livePixels != null && livePixels.length == capW * capH) return livePixels;
  // Match liveCompositeSourceBase — graded / Live-FX frames when raw bus is empty.
  PImage src = liveCompositeSourceBase();
  if (src != null && src.width == capW && src.height == capH) {
    src.loadPixels();
    if (src.pixels != null && src.pixels.length == capW * capH) return src.pixels;
  }
  return null;
}

/** Pixels used when compositing the live layer (updating or frozen). */
int[] liveCompositePixels() {
  if (liveFeatherOn()) {
    prepareLiveFeather();
    if (liveFeatherPixels != null) return liveFeatherPixels;
  }
  return liveCompositePixelsBase();
}

/** Image used when compositing / previewing the live layer, before edge feather. */
PImage liveCompositeSourceBase() {
  if (liveFreezeOnMonitor() && liveFreezeImg != null) return liveFreezeImg;
  PImage faded = inputLiveSource();
  if (faded != null) return faded;
  return liveFxSource();
}

/** Image used when compositing / previewing the live layer. */
PImage liveCompositeSource() {
  if (liveFeatherOn()) {
    prepareLiveFeather();
    if (liveFeatherImg != null) return liveFeatherImg;
  }
  return liveCompositeSourceBase();
}

void publishFrames() {
  if (gpuGradeActive && gradedView != null) {
    publishGpuFrames();
    return;
  }
  viewImage = null;
  if (blackoutSolid()) {
    viewImage = blackImg;
    sendSyphon(blackImg);
    if (beamerOpen) prepareBeamerGpu(blackImg);
    return;
  }
  renderStack(monitorImg, true);
  applyOutCurves(monitorImg.pixels);
  applyClearFadePixels(monitorImg.pixels);
  monitorImg.updatePixels();
  viewImage = monitorImg;
  PImage outgoing = applyFeedToProgram(monitorImg);
  PImage ext = applyBlackoutImage(withDrawCursorExternal(outgoing));
  sendSyphon(ext);
  if (beamerOpen) prepareBeamerGpu(ext);
}

void sendSyphon(PImage img) {
  if (!syphonOut || img == null) return;
  try {
    ensureSyphonServer();
    if (server != null) server.sendImage(img);
  } catch (Throwable t) {
    syphonOut = false;
    syphonStatus = "Syphon output stopped";
    note("Syphon output unavailable");
    println(t);
  }
}

void keyPressed() {
  if (key == CODED && keyCode == 157) metaHeld = true; // VK_META
  else if (keyEvent != null && keyEvent.isMetaDown()) metaHeld = true;
  if (key == CODED && keyCode == ALT) setDrawAlt(true);
  else if (keyEvent != null && keyEvent.isAltDown()) setDrawAlt(true);
  if (editId != null) {
    if (key == ESC) {
      key = 0;
      cancelEdit();
      return;
    }
    typeEdit(key, keyCode);
    return;
  }
  if (fxFilterFocus) {
    if (key == ESC) {
      key = 0;
      if (fxFilter.length() > 0) fxFilter = "";
      else fxFilterFocus = false;
      return;
    }
    // Space always records (like Live) — never type into the filter.
    if (key == ' ') {
      if (spaceLatch) return;
      spaceLatch = true;
      onSpace();
      return;
    }
    fxFilterType(key, keyCode);
    return;
  }
  if (key == ESC) {
    key = 0;
    if (fxFilter.length() > 0) {
      fxFilter = "";
      return;
    }
    if (fxKeyMapFrom >= 0) {
      fxCancelKeyMap();
      note("Map cancelled");
      return;
    }
    if (notesModeOn() && textLineOn) {
      textLineOn = false;
      return;
    }
    if (notesModeOn() && textPlaceOn) {
      textPlaceOn = false;
      textPlaceDrag = false;
      note("Place off");
      return;
    }
    if (notesModeOn() && (textSel >= 0 || notesFocus)) {
      deselectText();
      return;
    }
    if (midiMapMode) toggleMidiMap();
    return;
  }
  boolean shift = keyEvent != null && keyEvent.isShiftDown();
  boolean cmd = keyEvent != null && keyEvent.isMetaDown();
  boolean ctrl = keyEvent != null && keyEvent.isControlDown();
  boolean alt = keyEvent != null && keyEvent.isAltDown();
  // Place on: Space starts / locks the take. Typing stays off so pinch can perform.
  if (key == ' ' && textPlaceRecords()) {
    if (spaceLatch) return;
    spaceLatch = true;
    onSpace();
    return;
  }
  // Cmd+D duplicates the selected text field, including while typing.
  if (cmd && notesModeOn() && (key == 'd' || key == 'D')) {
    if (textDupLatch) return;
    textDupLatch = true;
    duplicateSelectedText();
    return;
  }
  // Cmd + / Cmd − sizes the whole active field by 1 pt, including while typing.
  if (cmd && notesModeOn() && (notesFocus || textSel >= 0)) {
    int plus = com.jogamp.newt.event.KeyEvent.VK_PLUS;
    int eq = com.jogamp.newt.event.KeyEvent.VK_EQUALS;
    boolean bigger = key == '+' || key == '=' || keyCode == plus || keyCode == eq
      || keyCode == java.awt.event.KeyEvent.VK_ADD;
    boolean smaller = key == '-' || key == '_'
      || keyCode == java.awt.event.KeyEvent.VK_SUBTRACT
      || keyCode == java.awt.event.KeyEvent.VK_MINUS
      || keyCode == com.jogamp.newt.event.KeyEvent.VK_MINUS;
    if (bigger || smaller) {
      nudgeSelectedTextSize(bigger ? 1 : -1);
      return;
    }
  }
  // Cmd+Enter toggles Place (pinch) without inserting a line break.
  if (cmd && notesModeOn() && (key == ENTER || key == RETURN || key == '\n' || key == '\r'
      || keyCode == ENTER || keyCode == RETURN)) {
    if (enterLatch) return;
    enterLatch = true;
    toggleTextPlace();
    return;
  }
  // Text editor focused → all app shortcuts muted; only typing / Esc.
  if (notesModeOn() && notesFocus) {
    notesHandleKey(key, keyCode, shift, cmd, alt);
    return;
  }
  // FX key map: next QWERTZ / ASDF key moves the armed effect onto that key.
  if (fxKeyMapFrom >= 0) {
    int fxIdx = fxKeyIndex(key);
    if (fxIdx >= 0) {
      fxCommitKeyMap(fxIdx);
      fxMapIgnore = key;
    }
    return;
  }
  if (fxMapIgnore != 0 && fxKeyIndex(key) >= 0 && fxKeyIndex(key) == fxKeyIndex(fxMapIgnore)) return;
  if (cmd) {
    if ((key == 'n' || key == 'N') && shift) {
      runFileAction(4);
      return;
    }
    if (key == 'o' || key == 'O') {
      runFileAction(1);
      return;
    }
    if ((key == 'r' || key == 'R') && shift) {
      runFileAction(2);
      return;
    }
    if ((key == 's' || key == 'S') && shift) {
      runFileAction(6);
      return;
    }
    if (key == 's' || key == 'S') {
      runFileAction(3);
      return;
    }
    if (key == 'z' || key == 'Z') {
      if (shift) {
        if (drawModeOn()) drawOrStopRedo();
        else redo();
      } else {
        if (drawModeOn()) drawOrStopUndo();
        else undo();
      }
      return;
    }
    // Cmd alone: stoptrick selected → onion; else FX double-tap toggle / cycle.
    // 157 = VK_META on macOS; Processing has no META constant.
    if (key == CODED && keyCode == 157) {
      if (stopSelected()) {
        stopToggleOnion();
        return;
      }
      fxCmdAlone(shift);
      return;
    }
    // Cmd + FX key → cycle that slot's Mode/Dir (no toggle)
    int fxIdx = fxSlotForKey(fxKeyIndex(key));
    if (fxIdx >= 0) {
      fxCmdPending = false;
      fxCycleMode(fxIdx, shift ? -1 : 1);
      return;
    }
  }
  // Opt = +amount / +fps, Ctrl = −amount / −fps. Shift = fine (FX). Hold repeats (FX).
  // When stoptrick is selected: Opt/Ctrl step FPS only (never walk Hue mid-bake).
  if (alt && !cmd && !ctrl) {
    boolean altAlone = key == CODED && keyCode == ALT;
    if (stopSelected()) {
      if (altAlone) stopNudgeFps(1);
      return;
    }
    if (altAlone) {
      if (!drawModeOn()) {
        // Ignore OS key-repeat on the modifier; our hold ticker drives repeats.
        if (fxHoldDir != 1) {
          fxNudgeFocusedAmount(1, shift);
          fxStartNudgeHold(1, -1, shift);
        }
        return;
      }
    } else {
      int fxIdx = fxSlotForKey(fxKeyIndex(key));
      if (fxIdx >= 0) {
        if (fxHoldDir != 1 || fxHoldIdx != fxIdx) {
          fxNudgeAmount(fxIdx, 1, shift);
          fxStartNudgeHold(1, fxIdx, shift);
        }
        return;
      }
    }
  }
  if (ctrl && !cmd && !alt) {
    if (stopSelected()) {
      if (key == CODED && keyCode == CONTROL) stopNudgeFps(-1);
      return;
    }
    if (key == CODED && keyCode == CONTROL) {
      if (fxHoldDir != -1) {
        fxNudgeFocusedAmount(-1, shift);
        fxStartNudgeHold(-1, -1, shift);
      }
      return;
    }
    int fxIdx = fxSlotForKey(fxKeyIndex(key));
    if (fxIdx >= 0) {
      if (fxHoldDir != -1 || fxHoldIdx != fxIdx) {
        fxNudgeAmount(fxIdx, -1, shift);
        fxStartNudgeHold(-1, fxIdx, shift);
      }
      return;
    }
  }
  onKey(key, keyCode, shift);
}

void keyTyped() {
  if (editId != null || fxFilterFocus) return;
  if (!notesModeOn() || !notesFocus || textPlaceOn) return;
  if (keyEvent != null && (keyEvent.isMetaDown() || keyEvent.isControlDown())) return;
  notesAcceptChar(key);
}

void keyReleased() {
  fxReleaseKey(key);
  if (fxMapIgnore != 0 && fxKeyIndex(key) == fxKeyIndex(fxMapIgnore)) fxMapIgnore = 0;
  if (key == ' ') spaceLatch = false;
  if (key == '0' || keyCode == 48 || keyCode == 96) zeroLatch = false;
  if ((key == 'v' || key == 'V') && freezeKeyLatch) {
    freezeKeyLatch = false;
    endFreezeHold();
  }
  if (key == 'd' || key == 'D') textDupLatch = false;
  if (key == ENTER || key == RETURN || key == '\n' || key == '\r'
      || keyCode == ENTER || keyCode == RETURN) {
    enterLatch = false;
  }
  if (key == '-' || key == '_') dashLatch = false;
  if (key == CODED && keyCode == 157) metaHeld = false; // VK_META
  else if (keyEvent != null && !keyEvent.isMetaDown()) metaHeld = false;
  if (key == CODED && keyCode == ALT) {
    setDrawAlt(false);
    fxStopNudgeHoldDir(1);
    stopClearFpsNudgeLatch();
  } else if (keyEvent != null && !keyEvent.isAltDown()) {
    setDrawAlt(false);
    fxStopNudgeHoldDir(1);
    stopClearFpsNudgeLatch();
  }
  if (key == CODED && keyCode == CONTROL) {
    fxStopNudgeHoldDir(-1);
    stopClearFpsNudgeLatch();
  } else if (keyEvent != null && !keyEvent.isControlDown()) {
    fxStopNudgeHoldDir(-1);
    stopClearFpsNudgeLatch();
  }
}

void focusLost() {
  fxMapIgnore = 0;
  fxKeyHeldSlot = -1;
  if (fxKeyMapFrom >= 0) fxCancelKeyMap();
  spaceLatch = false;
  textDupLatch = false;
  enterLatch = false;
  zeroLatch = false;
  dashLatch = false;
  clearFreezeHolds();
  metaHeld = false;
  setDrawAlt(false);
  drawHslEnd();
  if (drawShapeOn) drawShapeCancel();
  fxStopNudgeHold();
  stopClearFpsNudgeLatch();
  super.focusLost();
}

void cycleInspector() {
  if (inspectorTab >= 3) inspectorTab = lastWorkTab;
  else inspectorTab = (inspectorTab + 1) % 3;
  lastWorkTab = inspectorTab;
}

void toggleGlobal() {
  if (inspectorTab == 3) inspectorTab = lastWorkTab;
  else {
    if (inspectorTab <= 2) lastWorkTab = inspectorTab;
    inspectorTab = 3;
  }
}

public void onKey(char k, int code, boolean shift) {
  if (midiMapMode) {
    boolean wipe = k == BACKSPACE || k == DELETE || code == BACKSPACE || code == DELETE;
    if (wipe) clearMidiPick();
    return;
  }
  if (k == ' ') {
    if (spaceLatch) return;
    spaceLatch = true;
    onSpace();
    return;
  }
  // Quiet program keys: 1–6 modes, 7–9 / ß extras, 0 = live frame 100% (double = FX off + defaults), ´ text peek
  // Numpad 0 (keyCode 96) often arrives without key=='0' on macOS/NEWT.
  if (k == '0' || code == 48 || code == 96) {
    if (zeroLatch) return;
    zeroLatch = true;
    int now = millis();
    boolean twice = now - zeroTapAt < FX_TAP_MS;
    zeroTapAt = now;
    resetLiveFrame();
    if (twice) {
      fxResetAll();
      setRawPipExternal(false);
      boolean hadText = !textFields.isEmpty();
      if (hadText) removeAllText();
      note(hadText
        ? "LIVE FRAME  100%  ·  FX RESET  ·  TEXT CLEARED"
        : "LIVE FRAME  100%  ·  FX RESET  ·  AFFECT LIVE");
    }
    return;
  }
  if (handleProgKey(k)) return;
  // FX rack: a s d f g h j k l ö ä #
  if (fxHandleKey(k)) return;
  // Performance: y x c v b n m , . -
  if (handlePerfKey(k, shift)) return;

  if (k == CODED && (code == LEFT || code == RIGHT || code == UP || code == DOWN)) {
    // Arrows navigate FX keyboard GUI; Shift+←/→ keeps layer / stop-step.
    if (shift && (code == LEFT || code == RIGHT)) {
      if ((stopModeOn() || drawModeOn()) && hasStop()) stopStep(code == RIGHT ? 1 : -1);
      else nudgeLayerSelect(code == RIGHT ? 1 : -1);
      return;
    }
    if (fxNavArrow(code)) return;
    return;
  }
  if (code == ENTER || code == RETURN || k == '\n' || k == '\r') {
    if (enterLatch) return;
    enterLatch = true;
    if (stopModeOn() || drawModeOn()) requestShoot();
    else activateSelectedLayer();
    return;
  }
  if (k == CODED && outputEditOn()) {
    nudgeCorner(code, shift);
    return;
  }
  if (k == BACKSPACE) {
    if (drawModeOn()) drawOrStopUndo();
    else if (stopModeOn()) stopPopLast();
    else undo();
  } else if (k == TAB) {
    cycleInspector();
  } else if (k == '[') {
    liveOpacity = max(0, liveOpacity - 0.05);
    markDirty();
  } else if (k == ']') {
    liveOpacity = min(1, liveOpacity + 0.05);
    markDirty();
  } else if ((k == 'r' || k == 'R') && outputEditOn()) {
    resetCorners();
  } else if ((k == 'i' || k == 'I') && outputEditOn()) {
    insetCorners(0.03);
  }
}

boolean handleProgKey(char k) {
  // Modes — also clickable in the top strip
  if (k == '1') { setTopMode(TOP_LIVE); return true; }
  if (k == '2') { setTopMode(TOP_STOP); return true; }
  if (k == '3') { setTopMode(TOP_DRAW); return true; }
  if (k == '4') { setTopMode(TOP_NOTES); return true; }
  if (k == '5') { setTopMode(TOP_FX); return true; }
  if (k == '6') { setTopMode(TOP_OUTPUT); return true; }
  if (k == '7') { showGrid = !showGrid; markDirty(); return true; }
  if (k == '8') { toggleBeamer(); return true; }
  if (k == '9') { toggleBlackout(); return true; }
  // '0' handled in onKey (incl. numpad) → resetLiveFrame; double → FX off + defaults
  if (k == '\u00DF' || k == 'ß') {
    liveOpacity = max(0, liveOpacity - 0.05);
    markDirty();
    return true;
  }
  // Acute key — show text fields on the preview outside Text mode
  if (k == '\u00B4' || k == '´' || k == '`') {
    toggleNotesPreview();
    return true;
  }
  return false;
}

boolean handlePerfKey(char k, boolean shift) {
  char low = Character.toLowerCase(k);
  if (low == 'y') {
    if (drawModeOn()) {
      if (shift) drawOrStopRedo();
      else drawOrStopUndo();
    } else if (stopModeOn()) stopPopLast();
    else if (shift) redo();
    else undo();
    return true;
  }
  if (low == 'x') {
    // Single X and the confirming second X. Live included: this is not a Text-mode key.
    boolean faded = textFadeOut();
    if (!requestClear() && faded) note("Text off");
    return true;
  }
  if (k == DELETE) { requestClear(); return true; }
  if (low == 'c') {
    // Capture is Enter — C clears stoptrick frames (loop stays).
    if (hasStop()) stopClear();
    else note("No stoptrick frames");
    return true;
  }
  if (low == 'v') {
    if (!freezeKeyLatch) {
      freezeKeyLatch = true;
      beginFreezeHold();
    }
    return true;
  }
  if (low == 'b') { toggleBlackout(); return true; }
  if (low == 'n') {
    setShownBlend(shownBlend() == BLEND_MULTIPLY ? BLEND_SCREEN : BLEND_MULTIPLY);
    return true;
  }
  if (low == 'm') { stopTogglePlay(); return true; }
  if (k == ',' || k == '<') {
    if (hasStop()) stopStep(-1);
    else nudgeLayerSelect(-1);
    return true;
  }
  if (k == '.' || k == '>') {
    if (hasStop()) stopStep(1);
    else nudgeLayerSelect(1);
    return true;
  }
  if (k == '-' || k == '_') {
    if (dashLatch) return true;
    dashLatch = true;
    pressBakeDash();
    return true;
  }
  return false;
}

public void clearSpaceLatch() {
  spaceLatch = false;
}

public void clearEnterLatch() {
  enterLatch = false;
}

/** Queue a stoptrick/draw capture for the next draw() — safe across windows. */
void requestShoot() {
  pendingShoot = true;
}

int fileActionAt = 0;

void serviceMacMenu() {
  if (!MacMenu.loaded) return;
  if (frameCount == 20 || frameCount == 90 || frameCount % 180 == 0) {
    MacMenu.install();
    MacMenu.keepDesktopChrome(); // laptop: menu bar + clock stay visible
  }
  // Beamer: cover menu bar / clock on the external only (not the laptop).
  if (beamerOpen && (frameCount <= 90 || frameCount % 30 == 0)) {
    MacMenu.shieldProgramOut();
  }
  int action = MacMenu.poll();
  if (action != 0) runFileAction(action);
}

void runFileAction(int action) {
  if (millis() - fileActionAt < 400) return;
  fileActionAt = millis();
  if (action == 1) requestOpenProject();
  else if (action == 2) revealProject();
  else if (action == 3) saveProjectNow();
  else if (action == 4) requestNewProject();
  else if (action == 5) clearRecentProjects();
  else if (action == 6) requestSaveProjectAs();
  else if (action >= 100 && action < 100 + MAX_RECENT_PROJECTS) openRecentProject(action - 100);
}

void nudgeCorner(int code, boolean shift) {
  float step = shift ? 0.01 : 0.0025;
  if (code == LEFT) corners[activeCorner][0] -= step;
  else if (code == RIGHT) corners[activeCorner][0] += step;
  else if (code == UP) corners[activeCorner][1] -= step;
  else if (code == DOWN) corners[activeCorner][1] += step;
  else return;
  corners[activeCorner][0] = constrain(corners[activeCorner][0], -0.2, 1.2);
  corners[activeCorner][1] = constrain(corners[activeCorner][1], -0.2, 1.2);
  markDirty();
}

boolean cmdDown() {
  return mouseEvent != null && mouseEvent.isMetaDown();
}

void mousePressed() {
  String id = hitTest(mouseX, mouseY);
  if (fxKeyMapFrom >= 0 && (id == null || !(id.startsWith("fx-map#") || id.startsWith("fx-kb#")))) {
    fxCancelKeyMap();
  }
  if (editId != null && (id == null || !id.equals("num-" + editId))) commitEdit();
  if (fxFilterFocus && (id == null || !(id.equals("fx-filter") || id.equals("fx-filter-clear")))) {
    fxFilterFocus = false;
  }
  if (notesModeOn() && overLivePreview(mouseX, mouseY)) {
    textFontOpen = false;
    boolean shift = mouseEvent != null && mouseEvent.isShiftDown();
    textPreviewPointerDown(mouseX, mouseY, shift);
    return;
  }
  if (textFontOpen && (id == null || !(id.equals("text-font") || id.startsWith("text-font#")))) {
    textFontOpen = false;
  }
  if (notesModeOn()) {
    boolean notesChrome = id != null && (id.startsWith("notes-") || id.startsWith("text-") || id.equals("feed-air"));
    if (!notesChrome) {
      notesFocus = false;
      flushNotesIfDirty();
    }
  }
  if (id != null && id.equals("text-hsl")) {
    textHslDrag = true;
    textHslApply(mouseX, mouseY);
    return;
  }
  if (midiMapMode) {
    if (id != null && (id.equals("midi-map") || id.equals("gear") || id.startsWith("tab-")
        || id.startsWith("midi-in#") || id.equals("midi-refresh") || id.startsWith("midi-bind#")
        || id.startsWith("top-") || id.equals("proj-open") || id.equals("proj-save") || id.equals("proj-show"))) {
      onClick(id);
      return;
    }
    // Hits drawn on map frames (midi-pick#…) are topmost and use the real bind id.
    if (id != null && id.startsWith("midi-pick#")) {
      selectMidiPick(id.substring(10));
      return;
    }
    String mapHit = mapFrameHit(mouseX, mouseY);
    if (mapHit != null) {
      selectMidiPick(mapHit);
      return;
    }
    if (id == null) {
      midiPickId = null;
      midiPending = false;
      note("Selection cleared");
      return;
    }
    String bind = bindForHit(id);
    if (bind != null) selectMidiPick(bind);
    else note("Not mappable");
    return;
  }
  if (outputEditOn() && previewBoxW > 1) {
    int c = pickCornerPx(mouseX, mouseY, previewBoxX, previewBoxY, previewBoxW, previewBoxH, 18);
    if (c >= 0) {
      dragCorner = c;
      activeCorner = c;
      return;
    }
  }
  if (liveCropEdit && (id == null || id.equals("lay#live") || overLivePreview(mouseX, mouseY))) {
    if (beginLiveCropDrag(mouseX, mouseY)) return;
  }
  // Draw owns the preview — paint even if a stray hit overlaps the frame.
  // Desktop ink always works (phone paint is disarmed; tether must not block the mouse).
  if (drawModeOn() && !midiMapMode && overLivePreview(mouseX, mouseY)) {
    drawMouseStroke(mouseX, mouseY, true);
    return;
  }
  if (id == null) {
    // Framing drag first — focus-assist tap waits for mouseReleased if no drag.
    if (beginFrameDrag(mouseX, mouseY)) return;
    if (tetherTapAtStage(mouseX, mouseY)) return;
    return;
  }
  if (id.equals("lay#live")) {
    selectLayer(-1);
    if (layerDoubleClick(id)) activateSelectedLayer();
    return;
  }
  if (id.equals("lay#stop")) {
    selectLayer(SEL_STOP);
    if (layerDoubleClick(id) && hasStop()) stopTogglePlay();
    return;
  }
  if (id.startsWith("lay#")) {
    selectLayer(int(id.substring(4)));
    if (layerDoubleClick(id)) activateSelectedLayer();
    return;
  }
  if (id.equals("curve")) {
    curvePointerDown();
    return;
  }
  if (drawHslHit(id)) {
    drawHslBegin(id, mouseX, mouseY);
    return;
  }
  if (id.startsWith("sl-")) {
    if (cmdDown()) {
      applySlider(id, sliderDefault(id));
      flushSettings(true);
      return;
    }
    NumBox typed = findNum(id);
    boolean onNum = typed != null
      && mouseX >= typed.x && mouseX < typed.x + typed.w
      && mouseY >= typed.y && mouseY < typed.y + typed.h;
    // Value box: double-click types. Track: double-click resets that param.
    if (knobDoubleClick(id)) {
      if (onNum) {
        beginEdit(typed);
        return;
      }
      applySlider(id, sliderDefault(id));
      flushSettings(true);
      return;
    }
    dragSlider = id;
    Sld grabbed = findSld(id);
    if (grabbed != null && grabbed.radial) {
      knobGrabY = mouseY;
      knobGrabU = grabbed.unit;
    }
    setDraggedSlider();
    return;
  }
  onClick(id);
}

void mouseDragged() {
  if (curveDrag >= 0) {
    curveDragMove();
    return;
  }
  if (textPlaceDrag) {
    textPlaceDragMove(mouseX, mouseY);
    return;
  }
  if (textLineOn) {
    dragTextLine(mouseX, mouseY);
    return;
  }
  if (notesDraggingSelect) {
    notesPointerDrag(mouseX, mouseY);
    return;
  }
  if (textHslDrag) {
    textHslApply(mouseX, mouseY);
    return;
  }
  if (hslDragPad) {
    drawHslDrag(mouseX, mouseY);
    return;
  }
  if (fineId != null) {
    setFineSlider();
    return;
  }
  if (dragSlider != null) {
    setDraggedSlider();
    return;
  }
  if (liveCropDrag >= 0) {
    moveLiveCropDrag(mouseX, mouseY);
    return;
  }
  if (frameDragOn) {
    moveFrameDrag(mouseX, mouseY);
    return;
  }
  if (drawModeOn() && (drawTouching || drawShapeOn || mousePressed)) {
    drawMouseStroke(mouseX, mouseY, false);
    return;
  }
  if (dragCorner >= 0 && previewBoxW > 1) {
    corners[dragCorner][0] = constrain((mouseX - previewBoxX) / previewBoxW, -0.2, 1.2);
    corners[dragCorner][1] = constrain((mouseY - previewBoxY) / previewBoxH, -0.2, 1.2);
    markDirty();
  }
}

void mouseWheel(MouseEvent e) {
  if (dragSlider != null || fineId != null || editId != null || curveDrag >= 0) return;
  if (framePinchOn) return;
  if (notesWheelConsumes()) {
    notesScrollWheel(e.getCount());
    return;
  }
  String wheelHit = hitTest(mouseX, mouseY);
  if (wheelHit != null && wheelHit.equals("sl-feather")) {
    applySlider("sl-feather", constrain(liveFeather - e.getCount() * 3f, 0, 100));
    return;
  }
  // Two-finger scroll over live preview must not zoom — pinch only.
  if (overLivePreview(mouseX, mouseY) && liveFramingAllowed()) return;
  float x2 = dockX();
  if (mouseX < x2 || mouseX > width - 14) return;
  float delta = e.getCount() * 36;
  if (inspectorTab == 3) midiScroll = constrain(midiScroll + delta, 0, midiScrollMax);
  else if (fxViewOn()) fxScroll = constrain(fxScroll + delta, 0, fxScrollMax);
  else if (!outputEditOn() && !notesViewOn()) gradeScroll = constrain(gradeScroll + delta, 0, gradeScrollMax);
}

void mouseReleased() {
  if (freezeMouseLatch) {
    freezeMouseLatch = false;
    endFreezeHold();
  }
  if (textPlaceDrag) {
    textPlaceDrag = false;
    flushNotesIfDirty();
  }
  if (textLineOn) finishTextLine();
  if (notesDraggingSelect) notesPointerUp();
  if (fineId != null) {
    fineId = null;
    flushSettings(true);
  }
  if (curveDrag >= 0) {
    curveDrag = -1;
    flushSettings(true);
  }
  if (textHslDrag) {
    textHslDrag = false;
    flushNotesIfDirty();
  }
  if (hslDragPad) {
    drawHslEnd();
    flushSettings(true);
  }
  dragSlider = null;
  drawMouseReleased();
  endLiveCropDrag();
  endFrameDrag();
  if (dragCorner >= 0) {
    dragCorner = -1;
    flushSettings(true);
  }
}

public boolean settingsAreOpen() {
  return outputEditOn();
}

String editId = null;
String editText = "";
boolean editFresh = false;
float editX, editY, editW, editH, editMin, editMax;
String fineId = null;
float fineX, fineV;
int knobClickAt = 0;
String knobClickId = "";

boolean knobDoubleClick(String id) {
  int now = millis();
  boolean twice = id.equals(knobClickId) && now - knobClickAt < 420;
  knobClickAt = now;
  knobClickId = id;
  return twice;
}

void beginEdit(NumBox n) {
  editId = n.id;
  editText = editSeed(n.id, n.v);
  editFresh = true;
  editW = max(n.w, 48);
  editH = max(n.h, 16);
  editX = n.x - (editW - n.w) / 2f;
  editY = n.y - (editH - n.h) / 2f;
  editMin = n.minv;
  editMax = n.maxv;
}

void cancelEdit() {
  editId = null;
  editText = "";
  editFresh = false;
}

void commitEdit() {
  if (editId == null) return;
  String id = editId;
  float v = parseEdited(id, editText);
  float lo = editMin;
  float hi = editMax;
  cancelEdit();
  if (Float.isNaN(v)) return;
  applySlider(id, constrain(v, lo, hi));
  flushSettings(true);
}

void typeEdit(char k, int code) {
  if (code == ENTER || code == RETURN || k == '\n' || k == '\r') {
    commitEdit();
    return;
  }
  if (k == BACKSPACE || code == BACKSPACE) {
    editFresh = false;
    if (editText.length() > 0) editText = editText.substring(0, editText.length() - 1);
    return;
  }
  if (k == CODED || k == DELETE) return;
  char c = k == ',' ? '.' : k;
  if (!((c >= '0' && c <= '9') || c == '.' || c == '-' || c == '+')) return;
  if (editFresh) {
    editText = "";
    editFresh = false;
  }
  if ((c == '-' || c == '+') && editText.length() > 0) return;
  if (c == '.' && editText.indexOf('.') >= 0) return;
  if (editText.length() >= 7) return;
  editText += c;
}

String editSeed(String id, float v) {
  if (id.equals("sl-zoom") || id.equals("sl-hw-zoom")) return nf(v, 1, 2);
  if (id.equals("sl-hw-bias")) return hwUvc ? str(round(v * 100)) : nf(v, 1, 1);
  if (id.equals("sl-hue") || id.equals("sl-post") || id.equals("sl-pix") || id.equals("sl-brush") || id.equals("sl-feather") || id.equals("sl-stop-fps") || id.equals("notes-size")) return str(round(v));
  if (id.startsWith("sl-fx#")) {
    int param = int(id.substring(6));
    FxUnit u = fxFocusedUnit();
    if (u != null && fxParamRaw(u.type, param)) {
      if (fxParamFine(u.type, param)) return nf(v, 1, 2);
      return str(round(v));
    }
  }
  return str(round(v * 100));
}

float parseEdited(String id, String raw) {
  String s = raw == null ? "" : raw.trim().toLowerCase();
  s = s.replace(',', '.').replace("%", "").replace("°", "").replace("×", "").replace("+", "");
  if (s.length() == 0 || s.equals("off") || s.equals("aus") || s.equals("-") || s.equals(".")) return sliderDefault(id);
  try {
    float n = Float.parseFloat(s);
    if (id.equals("sl-hw-bias") && hwUvc) return n / 100f;
    if (id.equals("sl-zoom") || id.equals("sl-hw-zoom") || id.equals("sl-hw-bias") || id.equals("sl-hue") || id.equals("sl-post") || id.equals("sl-pix") || id.equals("sl-brush") || id.equals("sl-feather") || id.equals("sl-stop-fps")) return n;
    if (id.startsWith("sl-fx#")) {
      int param = int(id.substring(6));
      FxUnit u = fxFocusedUnit();
      if (u != null && fxParamRaw(u.type, param)) return n;
    }
    return n / 100f;
  } catch (NumberFormatException e) {
    return Float.NaN;
  }
}

float sliderDefault(String id) {
  if (id.equals("sl-zoom") || id.equals("sl-hw-zoom") || id.equals("sl-opac") || id.equals("sl-loop-opac")
    || id.equals("sl-mix-live") || id.equals("sl-mix-loop") || id.equals("sl-pix")
    || id.equals("sl-curve-white")) return 1;
  if (id.equals("sl-hw-focus") || id.equals("sl-tether-focus")) return 0.5f;
  if (id.equals("sl-onion")) return 0.32f;
  if (id.equals("sl-input-fade")) return 320;
  if (id.equals("sl-brush")) return 8;
  if (id.equals("sl-stop-fps")) return 6;
  // brush min is 1 in paint panel
  if (id.equals("sl-feather") || id.equals("sl-curve-black")) return 0;
  if (id.startsWith("sl-fx#")) {
    int param = int(id.substring(6));
    FxUnit u = fxFocusedUnit();
    if (u == null) return 0;
    if (param == 1) return fxDefaultAmount2(u.type);
    if (param == 2) return fxDefaultAmount3(u.type);
    if (param == 3) return fxDefaultAmount4(u.type);
    if (param == 0) return fxDefaultAmount(u.type);
    return 0;
  }
  return 0;
}

void setFineSlider() {
  NumBox n = findNum(fineId);
  if (n == null) return;
  float v = fineV + (mouseX - fineX) / 1200f * (n.maxv - n.minv);
  applySlider(fineId, constrain(v, n.minv, n.maxv));
}

void setDraggedSlider() {
  Sld s = findSld(dragSlider);
  if (s == null || s.w < 1) return;
  float t;
  if (s.radial) {
    t = constrain(knobGrabU - (mouseY - knobGrabY) / 110f, 0, 1);
  } else if (s.vert) {
    t = 1 - constrain((mouseY - s.track) / s.w, 0, 1);
  } else {
    t = constrain((mouseX - s.x) / s.w, 0, 1);
  }
  applySlider(s.id, s.minv + t * (s.maxv - s.minv));
}

void applySlider(String id, float v) {
  if (id.equals("sl-zoom")) { camZoom = constrain(v, LIVE_ZOOM_MIN, LIVE_ZOOM_MAX); liveFrameDirty = true; }
  else if (id.equals("sl-panx")) { camPanX = v; liveFrameDirty = true; }
  else if (id.equals("sl-pany")) { camPanY = v; liveFrameDirty = true; }
  else if (id.equals("sl-feather")) {
    liveFeather = abs(v) < 0.5f ? 0 : constrain(v, 0, 100);
    liveFeatherFrame = -1;
  }
  else if (id.equals("notes-size")) {
    NotesPad pad = selectedPad();
    if (pad != null) {
      pad.setSizePx(round(v));
      textGeomDirty = true;
    }
  }
  else if (id.equals("sl-expo")) camExposure = v;
  else if (id.equals("sl-bril")) camBrilliance = v;
  else if (id.equals("sl-high")) camHighlights = v;
  else if (id.equals("sl-shad")) camShadows = v;
  else if (id.equals("sl-contrast")) camContrast = v;
  else if (id.equals("sl-bright")) camBrightness = v;
  else if (id.equals("sl-black")) camBlack = v;
  else if (id.equals("sl-sat")) camSaturation = v;
  else if (id.equals("sl-vib")) camVibrance = v;
  else if (id.equals("sl-warm")) camWarmth = v;
  else if (id.equals("sl-tint")) camTint = v;
  else if (id.equals("sl-sharp")) camSharp = v < 0.01 ? 0 : v;
  else if (id.equals("sl-clar")) camClarity = v;
  else if (id.equals("sl-noise")) camNoise = v < 0.01 ? 0 : v;
  else if (id.equals("sl-vig")) camVignette = abs(v) < 0.01 ? 0 : v;
  else if (id.equals("sl-opac") || id.equals("sl-mix-live")) liveOpacity = constrain(v, 0, 1);
  else if (id.equals("sl-loop-opac") || id.equals("sl-mix-loop")) loopOpacity = constrain(v, 0, 1);
  else if (id.equals("sl-onion")) stopOnionAmt = constrain(v, 0, 1);
  else if (id.equals("sl-fb") || id.equals("sl-hue") || id.equals("sl-post") || id.equals("sl-thr") || id.equals("sl-pix")) {
    fxSetAmountFromSlider(id, v);
  } else if (fxApplySlider(id, v)) {
    // Focused FX param (sl-fx#0 … sl-fx#3)
  } else if (id.equals("sl-hw-bias")) {
    hwBias = v;
    hwBiasTouched = true;
    hwDirty = true;
    hwApplied = false;
  } else if (id.equals("sl-hw-focus")) {
    hwFocus = v;
    hwFocusTouched = true;
    hwDirty = true;
    hwApplied = false;
  } else if (id.equals("sl-tether-focus")) {
    tetherSetFocus(v);
  } else if (id.equals("sl-tether-bias")) {
    tetherSetBias(v);
  } else if (id.equals("sl-hw-zoom")) {
    hwZoom = v;
    hwZoomTouched = true;
    hwDirty = true;
    hwApplied = false;
  } else if (id.equals("sl-brush")) {
    drawBrush = constrain(v, DRAW_BRUSH_MIN, DRAW_BRUSH_MAX);
    luckyPadSyncBrush();
  } else if (id.equals("sl-stop-fps")) {
    stopSetFps(round(v));
  } else if (id.equals("sl-input-fade")) {
    inputFadeMs = abs(v) < 8 ? 0 : constrain(v, 0, 1500);
    if (inputFadeMs < 1) {
      inputFading = false;
      inputFade = 0;
    }
  } else if (id.equals("sl-curve-black")) {
    setInputCurveBlackX(constrain(v, 0, 1));
  } else if (id.equals("sl-curve-white")) {
    setInputCurveWhiteX(constrain(v, 0, 1));
  } else return;
  markDirty();
}

void onClick(String id) {
  if (fxKeyMapFrom >= 0 && id.startsWith("fx-kb#")) {
    fxCommitKeyMap(int(id.substring(6)));
    return;
  }
  if (id.startsWith("curve-ch#")) {
    setActiveCurveChannel(int(id.substring(9)));
    curveSel = -1;
    curveDrag = -1;
    markDirty();
  } else if (id.equals("proj-new")) requestNewProject();
  else if (id.equals("proj-open")) requestOpenProject();
  else if (id.equals("proj-save")) saveProjectNow();
  else if (id.equals("proj-show")) revealProject();
  else if (id.equals("proj-export")) requestLoopExport();
  else if (id.startsWith("proj-recent#")) openRecentProject(int(id.substring(12)));
  else if (id.equals("k-space")) onSpace();
  else if (id.equals("k-enter")) {
    if (stopModeOn() || drawModeOn()) requestShoot();
    else activateSelectedLayer();
  }
  else if (id.equals("k-shoot") || id.equals("k-frames")) {
    if (hasStop()) stopClear();
    else note("No stoptrick frames");
  }
  else if (id.equals("k-play")) stopTogglePlay();
  else if (id.equals("k-bake") || id.equals("k-dash")) {
    pressBakeDash();
  } else if (id.equals("k-opac-down")) {
    liveOpacity = max(0, liveOpacity - 0.05);
    markDirty();
  } else if (id.equals("k-opac-up")) {
    liveOpacity = min(1, liveOpacity + 0.05);
    markDirty();
  } else if (id.equals("k-grid")) {
    showGrid = !showGrid;
    markDirty();
  } else if (id.equals("k-syphon")) {
    syphonOut = !syphonOut;
    if (syphonOut) ensureSyphonServer();
    markDirty();
  } else if (id.equals("k-step-back")) {
    if (hasStop()) stopStep(-1);
    else nudgeLayerSelect(-1);
  } else if (id.equals("k-step-fwd")) {
    if (hasStop()) stopStep(1);
    else nudgeLayerSelect(1);
  } else if (id.equals("k-noop")) {
    // reserved keycap
  } else if (id.equals("k-undo")) {
    if (drawModeOn() || topMode == TOP_DRAW) drawOrStopUndo();
    else if (stopModeOn()) stopPopLast();
    else undo();
  } else if (id.equals("k-clear")) requestClear();
  else if (id.equals("work-live") || id.equals("anim-live") || id.equals("top-0")) setTopMode(TOP_LIVE);
  else if (id.equals("work-stop") || id.equals("anim-stop") || id.equals("top-1")) setTopMode(TOP_STOP);
  else if (id.equals("work-draw") || id.equals("anim-draw") || id.equals("top-2")) setTopMode(TOP_DRAW);
  else if (id.equals("top-3")) setTopMode(TOP_FX);
  else if (id.equals("top-4")) setTopMode(TOP_OUTPUT);
  else if (id.equals("top-5")) setTopMode(TOP_NOTES);
  else if (id.equals("notes-preview")) toggleNotesPreview();
  else if (id.equals("text-rec")) toggleTextRecord();
  else if (id.equals("feed-air")) toggleFeedOnAir();
  else if (id.equals("text-add")) addTextField();
  else if (id.equals("text-dup")) duplicateSelectedText();
  else if (id.equals("text-del")) removeSelectedText();
  else if (id.equals("text-clear")) removeAllText();
  else if (id.equals("text-place")) toggleTextPlace();
  else if (id.equals("text-font")) toggleTextFontMenu();
  else if (id.startsWith("text-font#")) pickTextFont(int(id.substring(10)));
  else if (id.startsWith("text-on#")) toggleTextEnabled(int(id.substring(8)));
  else if (id.startsWith("text-sel#")) selectTextIndex(int(id.substring(9)), true);
  else if (id.equals("notes-bold")) { notesFormatForPad(selectedPad()); notesToggleBold(); }
  else if (id.equals("notes-italic")) { notesFormatForPad(selectedPad()); notesToggleItalic(); }
  else if (id.equals("notes-align-l")) { notesFormatForPad(selectedPad()); notesSetAlign(javax.swing.text.StyleConstants.ALIGN_LEFT); }
  else if (id.equals("notes-align-c")) { notesFormatForPad(selectedPad()); notesSetAlign(javax.swing.text.StyleConstants.ALIGN_CENTER); }
  else if (id.equals("notes-align-r")) { notesFormatForPad(selectedPad()); notesSetAlign(javax.swing.text.StyleConstants.ALIGN_RIGHT); }
  else if (id.equals("notes-valign-t")) notesSetVAlign(0);
  else if (id.equals("notes-valign-c")) notesSetVAlign(1);
  else if (id.equals("notes-valign-b")) notesSetVAlign(2);
  else if (id.equals("notes-size-down")) { notesFormatForPad(selectedPad()); notesNudgeSize(-1); }
  else if (id.equals("notes-size-up")) { notesFormatForPad(selectedPad()); notesNudgeSize(1); }
  else if (id.equals("notes-size")) {
    NumBox typed = findNum(id);
    if (typed != null) beginEdit(typed);
  }
  else if (id.equals("stop-shoot")) animShoot();
  else if (id.equals("stop-play")) stopTogglePlay();
  else if (id.equals("stop-bake")) {
    stopClearThisBake = stopClearOnBake;
    bakeStoptrick();
  }
  else if (id.equals("stop-pop")) stopPopLast();
  else if (id.equals("stop-clear")) {
    if (hasStop()) stopClear();
    else note("No stoptrick frames");
  }
  else if (id.startsWith("stop#")) stopSelectFrame(int(id.substring(5)));
  else if (id.equals("draw-clear")) drawClearFrame();
  else if (id.equals("draw-raster")) {
    setDrawRaster(!drawRaster);
  } else if (id.equals("draw-trackpad")) {
    setDrawTrackpadMode(!drawTrackpadMode);
  } else if (id.equals("draw-shape-fill")) {
    drawShapeFill = !drawShapeFill;
    markDirty();
  } else if (id.startsWith("draw-tool-")) {
    setDrawTool(int(id.substring(10)));
  } else if (id.startsWith("draw-col-")) {
    applyDrawSwatch(int(id.substring(9)));
  } else if (id.startsWith("draw-sw#")) {
    int idx = int(id.substring(8));
    if (layerDoubleClick(id)) {
      applyDrawSwatch(idx);
      drawHslOpen = true;
      note("Edit swatch  ·  drag HSL");
    } else {
      applyDrawSwatch(idx);
      drawHslOpen = false;
    }
  } else if (id.equals("stop-clear-bake")) {
    stopClearOnBake = !stopClearOnBake;
    markDirty();
    note(stopClearOnBake ? "Clear frames after bake" : "Keep frames after bake");
  } else if (id.equals("stop-onion")) {
    stopToggleOnion();
  } else if (id.equals("stop-onion-ext")) {
    stopToggleOnionExternal();
  } else if (id.equals("draw-cursor-ext")) {
    setDrawCursorExternal(!drawCursorExternal);
  } else if (id.equals("draw-live-bg")) {
    setDrawLiveUnderlay(!drawLiveUnderlay);
  } else if (id.equals("mix-loop-tog")) {
    loopOpacity = loopOpacity > 0.5f ? 0 : 1;
    markDirty();
  } else if (id.equals("mix-live-tog")) {
    liveOpacity = liveOpacity > 0.5f ? 0 : 1;
    markDirty();
  } else if (id.equals("fx-affect-live")) {
    toggleFxAffectLive();
  } else if (id.equals("fx-affect-loop")) {
    toggleFxAffectLoop();
  } else if (id.equals("live-crop")) {
    toggleLiveCropEdit();
  } else if (id.equals("mix-blend") || id.equals("k-blend") || id.equals("blend-mul") || id.equals("blend-scr")) {
    if (id.equals("blend-mul")) setShownBlend(BLEND_MULTIPLY);
    else if (id.equals("blend-scr")) setShownBlend(BLEND_SCREEN);
    else setShownBlend(shownBlend() == BLEND_MULTIPLY ? BLEND_SCREEN : BLEND_MULTIPLY);
  } else if (id.equals("k-live")) {
    if (!freezeMouseLatch) {
      freezeMouseLatch = true;
      beginFreezeHold();
    }
  } else if (id.equals("live-out")) {
    toggleLiveInOutput();
  } else if (id.equals("k-black")) toggleBlackout();
  else if (id.equals("k-beamer") || id.equals("beamer")) toggleBeamer();
  else if (id.equals("k-settings")) cycleInspector();
  else if (id.equals("gear")) toggleGlobal();
  else if (id.startsWith("tab-")) {
    inspectorTab = constrain(int(id.substring(4)), 0, 2);
    lastWorkTab = inspectorTab;
  }
  else if (id.startsWith("midi-in#")) {
    int idx = int(id.substring(8));
    if (idx >= 0 && idx < midiNames.length) openMidi(midiNames[idx]);
  } else if (id.equals("midi-refresh")) {
    midiReady = false;
    midiStatus = "Searching for MIDI.";
    queueMidiScan();
  } else if (id.equals("midi-map")) {
    toggleMidiMap();
  } else if (id.startsWith("midi-bind#")) {
    selectMidiPick(id.substring(10));
  }
  else if (id.startsWith("rot-")) {
    camRotation = int(id.substring(4));
    liveFrameDirty = true;
    markDirty();
  } else if (id.equals("scale-fit")) {
    camScale = SCALE_FIT;
    liveFrameDirty = true;
    markDirty();
  } else if (id.equals("scale-fill")) {
    camScale = SCALE_FILL;
    liveFrameDirty = true;
    markDirty();
  } else if (id.equals("scale-1")) {
    camScale = SCALE_ONE;
    liveFrameDirty = true;
    markDirty();
  } else if (id.equals("cam-reset")) resetCameraGrade();
  else if (id.equals("live-frame-reset")) resetLiveFrame();
  else if (id.startsWith("rst-")) resetGroup(id.substring(4));
  else if (id.equals("fx-invert")) {
    fxSetInvert(!fxInvert);
    markDirty();
  } else if (id.equals("fx-filter")) {
    fxFilterFocus = true;
  } else if (id.equals("fx-filter-clear")) {
    fxFilter = "";
    fxFilterFocus = true;
  } else if (id.equals("fx-add")) {
    fxPickerOpen = !fxPickerOpen;
  } else if (id.equals("fx-pick-cancel")) {
    fxPickerOpen = false;
  } else if (id.startsWith("fx-pick#")) {
    fxAdd(constrain(int(id.substring(8)), 0, FX_NAMES.length - 1));
  } else if (id.startsWith("fx-tgt-")) {
    fxSetTarget(int(id.substring(7)));
  } else if (id.startsWith("fx-map#")) {
    fxArmKeyMap(int(id.substring(7)));
  } else if (id.startsWith("fx-row#")) {
    // Select only — show controls, do not toggle.
    fxSelectSlot(int(id.substring(7)));
  } else if (id.startsWith("fx-kb#")) {
    // Keyboard GUI: click selects, double toggles, triple resets params.
    int slot = fxSlotForKey(int(id.substring(6)));
    if (slot < 0) return;
    int n = fxKeyGesture(slot);
    if (n >= 3) fxResetUnit(slot);
    else if (n == 2) fxToggle(slot);
    else fxSelectSlot(slot);
  } else if (id.startsWith("fx-on#")) {
    // Stack checkbox still toggles immediately.
    fxToggle(int(id.substring(6)));
  } else if (id.startsWith("fx-rst#")) {
    fxResetUnit(int(id.substring(7)));
  } else if (id.startsWith("fx-del#")) {
    fxRemove(int(id.substring(7)));
  } else if (id.startsWith("fx-up#")) {
    fxMove(int(id.substring(6)), -1);
  } else if (id.startsWith("fx-dn#")) {
    fxMove(int(id.substring(6)), 1);
  }
  else if (id.equals("src-cam")) selectSource(SRC_CAM);
  else if (id.equals("src-syphon")) selectSource(SRC_SYPHON);
  else if (id.equals("src-tether")) selectSource(SRC_TETHER);
  else if (id.equals("src-test")) selectSource(SRC_TEST);
  else if (id.equals("tether-lock")) tetherToggleLock();
  else if (id.equals("tether-exp-off")) tetherSetAutoExposure(false);
  else if (id.equals("tether-exp-on")) tetherSetAutoExposure(true);
  else if (id.equals("tether-foc-off")) tetherSetAutoFocus(false);
  else if (id.equals("tether-foc-on")) tetherSetAutoFocus(true);
  else if (id.equals("tether-assist")) {
    tetherFocusAssist = !tetherFocusAssist;
    markDirty();
  } else if (id.startsWith("tether-cam#")) {
    int idx = int(id.substring(11));
    if (tetherLensEnabled(idx)) tetherSetCam(idx);
  }
  else if (id.startsWith("test#")) {
    testPattern = constrain(int(id.substring(5)), 0, 2);
    markDirty();
  }
  else if (id.startsWith("hw-")) onHardwareClick(id);
  else if (id.equals("refresh-cam") || id.equals("refresh-sy") || id.equals("refresh-inputs")) {
    refreshInputsAsync();
  } else if (id.startsWith("cam#")) selectCamera(int(id.substring(4)));
  else if (id.startsWith("sy#")) selectSyphon(int(id.substring(3)));
  else if (id.equals("mirror")) {
    mirror = !mirror;
    liveFrameDirty = true;
    markDirty();
  } else if (id.equals("syphon-out")) {
    syphonOut = !syphonOut;
    if (syphonOut) ensureSyphonServer();
    markDirty();
  } else if (id.equals("grid")) {
    showGrid = !showGrid;
    markDirty();
  } else if (id.equals("raw-pip")) {
    setRawPipDesktop(!rawPipDesktop);
  } else if (id.equals("raw-pip-ext")) {
    setRawPipExternal(!rawPipExternal);
  } else if (id.equals("blackout")) toggleBlackout();
  else if (id.startsWith("ext#")) {
    toggleBeamerExternal(int(id.substring(4)));
  } else if (id.equals("res-640")) setResolution(640, 360);
  else if (id.equals("res-854")) setResolution(854, 480);
  else if (id.equals("res-960")) setResolution(960, 540);
  else if (id.equals("res-1280")) setResolution(1280, 720);
  else if (id.equals("res-1920")) setResolution(1920, 1080);
  else if (id.equals("fps-24")) setFps(24);
  else if (id.equals("fps-25")) setFps(25);
  else if (id.equals("fps-30")) setFps(30);
  else if (id.startsWith("undo-steps#")) {
    int idx = int(id.substring(11));
    int[] choices = undoStepChoices();
    if (idx >= 0 && idx < choices.length) setUndoSteps(choices[idx]);
  }
  else if (id.equals("reset-key")) resetCorners();
  else if (id.equals("inset-key")) insetCorners(0.03);
  else if (id.equals("cam-up")) camScroll = max(0, camScroll - 1);
  else if (id.equals("cam-down")) camScroll++;
  else if (id.equals("corner-prev")) activeCorner = (activeCorner + 3) % 4;
  else if (id.equals("corner-next")) activeCorner = (activeCorner + 1) % 4;
}

void setFps(int fps) {
  if (capFps == fps) return;
  capFps = fps;
  markDirty();
  note(fps + " fps");
}

void setResolution(int w, int h) {
  if (w == capW && h == capH) return;
  clearLoop();
  clearHist(undoHist);
  clearHist(redoHist);
  capW = w;
  capH = h;
  allocateBuffers();
  if (sourceMode == SRC_CAM) startCamera();
  markDirty();
  note("Resolution " + w + "×" + h + ", loop cleared");
}

void selectSource(int src) {
  if (src != sourceMode) beginInputFade();
  rememberSourceSettings();
  sourceMode = src;
  if (src == SRC_SYPHON && syEntries.isEmpty()) refreshSyphon();
  recallSourceSettings(currentSourceKey());
  applySource();
  markDirty();
}

void applySource() {
  stopCamera();
  stopSyphonClient();
  if (sourceMode != SRC_TETHER) stopTether();
  liveValid = false;
  if (sourceMode == SRC_CAM) startCamera();
  else if (sourceMode == SRC_SYPHON) connectSyphon();
  else if (sourceMode == SRC_TETHER) startTether();
  else inputError = "";
}

void selectCamera(int index) {
  if (camEntries == null || index < 0 || index >= camEntries.size()) return;
  String next = camEntries.get(index).label;
  String nextKey = "cam:" + next;
  boolean changed = !(sourceMode == SRC_CAM && next.equals(cameraName));
  if (changed) beginInputFade();
  rememberSourceSettings();
  cameraName = next;
  sourceMode = SRC_CAM;
  recallSourceSettings(nextKey);
  camLiveOk = false;
  stopTether();
  stopSyphonClient();
  startCamera();
  markDirty();
}

void selectSyphon(int index) {
  if (index < 0 || index >= syEntries.size()) return;
  SyEntry e = syEntries.get(index);
  String nextKey = "syphon:"
    + (e.app == null ? "" : e.app) + "/"
    + (e.server == null ? "" : e.server);
  boolean changed = !(sourceMode == SRC_SYPHON && index == syIndex);
  if (changed) beginInputFade();
  rememberSourceSettings();
  syIndex = index;
  sourceMode = SRC_SYPHON;
  savedSyApp = e.app == null ? "" : e.app;
  savedSyServer = e.server == null ? "" : e.server;
  recallSourceSettings(nextKey);
  stopCamera();
  stopTether();
  connectSyphon();
  markDirty();
}

void toggleBeamer() {
  if (beamerOpen) closeBeamer();
  else openBeamer();
}

/** Toggle send-out for external list index (0-based among externals only). */
void toggleBeamerExternal(int extIndex) {
  ArrayList<ExtDisplay> ext = listExternalDisplays();
  if (extIndex < 0 || extIndex >= ext.size()) {
    note("No external display");
    return;
  }
  ExtDisplay d = ext.get(extIndex);
  if (beamerOpen && outputDisplayId.equals(d.id)) {
    closeBeamer();
    return;
  }
  outputDisplayId = d.id;
  markDirty();
  if (beamerOpen) reopenBeamerIfOpen();
  else openBeamer();
}

void openBeamer() {
  beamerReopenAt = 0;
  if (beamerOpening) return;
  if (gpuOut != null) {
    gpuOut.close();
    gpuOut = null;
  }
  final ExtDisplay d = selectedExternal();
  if (d == null) {
    beamerOpen = false;
    beamerPresent = null;
    println("openBeamer: no external display");
    note("No external display connected");
    markDirty();
    return;
  }
  outputDisplayId = d.id;
  outputFullscreen = true;
  beamerOpen = true;
  beamerOpening = true;
  markDirty();
  note("Out → " + d.label);
  final Rectangle bounds = new Rectangle(d.x, d.y, d.w, d.h);
  final LuckyLoop app = this;
  println("openBeamer GPU → " + d.id + " " + d.w + "x" + d.h + " @ " + d.x + "," + d.y);
  // Side thread + animator pause: shared NEWT window creation otherwise
  // deadlocks the JOGL FPSAnimator lock on macOS.
  Thread t = new Thread(new Runnable() {
    public void run() {
      GpuOutput g = null;
      try {
        Thread.sleep(80);
        g = new GpuOutput();
        g.open(app, d.id, bounds);
        if (!beamerOpen) {
          g.close();
          return;
        }
        gpuOut = g;
        // Cover menu bar on the external as soon as the out window exists.
        if (MacMenu.loaded) MacMenu.shieldProgramOut();
      } catch (Throwable e) {
        if (g != null) try { g.close(); } catch (Throwable ignored) {}
        gpuOut = null;
        beamerOpen = false;
        beamerPresent = null;
        println("openBeamer failed: " + e);
        e.printStackTrace();
        note("Send out failed — see console");
        markDirty();
      } finally {
        beamerOpening = false;
      }
    }
  }, "LuckyLoop-GpuOut");
  t.setDaemon(true);
  t.start();
}

void closeBeamer() {
  beamerReopenAt = 0;
  if (gpuOut != null) {
    gpuOut.close();
    gpuOut = null;
  }
  beamerOpen = false;
  beamerPresent = null;
  markDirty();
}

void reopenBeamerIfOpen() {
  if (!beamerOpen && beamerReopenAt == 0) return;
  if (gpuOut != null) {
    gpuOut.close();
    gpuOut = null;
  }
  beamerOpen = true;
  beamerReopenAt = frameCount + 5;
}

public void beamerClosedFromWindow() {
  beamerClosedPending = true;
}

/** Watchdog: drop out if the chosen external vanished; recover a lost window. */
void serviceBeamer() {
  if (!beamerOpen) return;
  if (selectedExternal() == null) {
    closeBeamer();
    note("External display disconnected");
    return;
  }
  if (gpuOut != null && gpuOut.dead) {
    closeBeamer();
    return;
  }
  // Window missing unexpectedly (not user-closed) → reopen.
  if (gpuOut == null && !beamerOpening && beamerReopenAt == 0 && !beamerClosedPending) {
    beamerReopenAt = frameCount + 30;
  }
}

class ExtDisplay {
  String id;
  String label;
  int x, y, w, h;
  ExtDisplay(String id, String label, int x, int y, int w, int h) {
    this.id = id;
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
}

ArrayList<ExtDisplay> listExternalDisplays() {
  ArrayList<ExtDisplay> out = new ArrayList<ExtDisplay>();
  GraphicsDevice[] ds = GpuOutput.allDevices();
  int n = 0;
  for (int i = 0; i < ds.length; i++) {
    if (GpuOutput.isPrimary(ds[i])) continue;
    Rectangle b = ds[i].getDefaultConfiguration().getBounds();
    n++;
    String lab = b.width + "×" + b.height;
    if (ds.length > 2) lab = "External " + n + " · " + lab;
    else lab = "External · " + lab;
    out.add(new ExtDisplay(ds[i].getIDstring(), lab, b.x, b.y, b.width, b.height));
  }
  return out;
}

ExtDisplay findExternal(String id) {
  if (id == null || id.length() == 0) return null;
  ArrayList<ExtDisplay> ext = listExternalDisplays();
  for (int i = 0; i < ext.size(); i++) {
    if (id.equals(ext.get(i).id)) return ext.get(i);
  }
  return null;
}

ExtDisplay selectedExternal() {
  ExtDisplay d = findExternal(outputDisplayId);
  if (d != null) return d;
  ArrayList<ExtDisplay> ext = listExternalDisplays();
  return ext.isEmpty() ? null : ext.get(0);
}

void clampDisplay() {
  ExtDisplay d = selectedExternal();
  outputDisplayId = d != null ? d.id : "";
}

boolean beamerOnExternal(String id) {
  return beamerOpen && id != null && id.equals(outputDisplayId);
}

String modeLabel() {
  if (mode == MODE_REC) return recFromStop ? "BAKE" : "RECORD";
  if (mode == MODE_DUB) return "OVERDUB";
  if (stopModeOn() && stopPlaying) return "STOP ▶";
  if (stopModeOn()) return "STOP";
  if (drawModeOn()) return "DRAW";
  if (mode == MODE_PLAY) return "LOOP";
  return "LIVE";
}

int modeColor() {
  if (mode == MODE_REC) return #e23d32;
  if (mode == MODE_DUB) return #e2b656;
  if (mode == MODE_PLAY) return #e2b656;
  return #2c3340;
}

boolean modeDarkText() {
  return mode == MODE_DUB || mode == MODE_PLAY;
}

String blendLabel() {
  return shownBlend() == BLEND_MULTIPLY ? "Multiply" : "Screen";
}

String fmtSec(float s) {
  return String.format(java.util.Locale.US, "%.1f s", s);
}

String savedSyApp = "";
String savedSyServer = "";

void loadProjectSettingsFile(java.io.File src) {
  if (src == null || !src.exists()) {
    clampDisplay();
    return;
  }
  int prevW = capW;
  int prevH = capH;
  try {
    JSONObject o = loadJSONObject(src.getAbsolutePath());
    int fileVersion = o.getInt("version", 1);
    capW = o.getInt("capW", capW);
    capH = o.getInt("capH", capH);
    capFps = o.getInt("capFps", capFps);
    undoSteps = sanitizeUndoSteps(o.getInt("undoSteps", DEFAULT_UNDO_STEPS));
    trimHist(undoHist);
    trimHist(redoHist);
    if (fileVersion < 3) {
      capW = 1920;
      capH = 1080;
      capFps = 25;
    }
    blendKind = o.getInt("blend", blendKind);
    liveOpacity = o.getFloat("liveOpacity", liveOpacity);
    loopOpacity = o.getFloat("loopOpacity", loopOpacity);
    liveInOutput = o.getBoolean("liveInOutput", liveInOutput);
    if (o.hasKey("inputFadeMs")) inputFadeMs = constrain(o.getFloat("inputFadeMs", inputFadeMs), 0, 1500);
    else if (o.hasKey("inputSeamless") && !o.getBoolean("inputSeamless", true)) inputFadeMs = 0;
    mirror = o.getBoolean("mirror", mirror);
    tetherFocusAssist = o.getBoolean("tetherFocusAssist", tetherFocusAssist);
    tetherAutoFocus = o.getBoolean("tetherAutoFocus", tetherAutoFocus);
    tetherAutoExposure = o.getBoolean("tetherAutoExposure", tetherAutoExposure);
    syphonOut = o.getBoolean("syphonOut", syphonOut);
    showGrid = o.getBoolean("showGrid", showGrid);
    // External out is always display-covering; keep flag true regardless of older saves.
    outputFullscreen = true;
    outputDisplayId = o.getString("displayId", outputDisplayId);
    // Migrate legacy 1-based AWT index → first matching external / index.
    if ((outputDisplayId == null || outputDisplayId.length() == 0) && o.hasKey("display")) {
      int legacy = o.getInt("display", 0);
      GraphicsDevice[] ds = GpuOutput.allDevices();
      if (legacy >= 1 && legacy <= ds.length && !GpuOutput.isPrimary(ds[legacy - 1])) {
        outputDisplayId = ds[legacy - 1].getIDstring();
      }
    }
    clampDisplay();
    beamerOpen = o.getBoolean("beamerOpen", beamerOpen);
    rawPipDesktop = o.getBoolean("rawPipDesktop", rawPipDesktop);
    rawPipExternal = o.getBoolean("rawPipExternal", rawPipExternal);
    rawPipExtAmt = rawPipExternal ? 1 : 0;
    rawPipExtFrom = rawPipExtAmt;
    sourceMode = o.getInt("source", sourceMode);
    testPattern = constrain(o.getInt("testPattern", testPattern), 0, 2);
    cameraName = o.getString("camera", cameraName);
    syIndex = o.getInt("syIndex", syIndex);
    savedSyApp = o.getString("syApp", "");
    savedSyServer = o.getString("syServer", "");
    camZoom = constrain(o.getFloat("camZoom", camZoom), LIVE_ZOOM_MIN, LIVE_ZOOM_MAX);
    camPanX = o.getFloat("camPanX", camPanX);
    camPanY = o.getFloat("camPanY", camPanY);
    camTwist = o.getFloat("camTwist", camTwist);
    liveCropL = constrain(o.getFloat("liveCropL", liveCropL), 0, 1);
    liveCropT = constrain(o.getFloat("liveCropT", liveCropT), 0, 1);
    liveCropR = constrain(o.getFloat("liveCropR", liveCropR), 0, 1);
    liveCropB = constrain(o.getFloat("liveCropB", liveCropB), 0, 1);
    normalizeLiveCrop();
    liveCropEdit = false;
    liveFeather = constrain(o.getFloat("liveFeather", liveFeather), 0, 100);
    camScale = o.getInt("camScale", camScale);
    camRotation = o.getInt("camRotation", camRotation);
    loadHardwareSettings(o);
    camExposure = o.getFloat("camExposure", camExposure);
    camBrilliance = o.getFloat("camBrilliance", camBrilliance);
    camHighlights = o.getFloat("camHighlights", camHighlights);
    camShadows = o.getFloat("camShadows", camShadows);
    camBrightness = o.getFloat("camBrightness", camBrightness);
    camBlack = o.getFloat("camBlack", camBlack);
    camVibrance = o.getFloat("camVibrance", camVibrance);
    camWarmth = o.getFloat("camWarmth", camWarmth);
    camTint = o.getFloat("camTint", camTint);
    camSharp = o.getFloat("camSharp", camSharp);
    camClarity = o.getFloat("camClarity", camClarity);
    camNoise = o.getFloat("camNoise", camNoise);
    float contrastIn = o.getFloat("camContrast", fileVersion < 2 ? 1 : 0);
    float satIn = o.getFloat("camSaturation", fileVersion < 2 ? 1 : 0);
    if (fileVersion < 2) {
      camContrast = contrastIn >= 1 ? constrain(contrastIn - 1, -1, 1) : constrain((contrastIn - 1) / 0.6f, -1, 1);
      camSaturation = constrain(satIn - 1, -1, 1);
      camVignette = o.getFloat("fxVignette", 0);
    } else {
      camContrast = constrain(contrastIn, -1, 1);
      camSaturation = constrain(satIn, -1, 1);
      camVignette = o.getFloat("camVignette", 0);
    }
    loadCurves(o);
    loadSourceMemories(o);
    fxFeedback = o.getFloat("fxFeedback", fxFeedback);
    fxHue = o.getFloat("fxHue", fxHue);
    fxPosterize = o.getInt("fxPosterize", fxPosterize);
    fxThreshold = o.getFloat("fxThreshold", fxThreshold);
    fxPixel = o.getInt("fxPixel", fxPixel);
    fxInvert = o.getBoolean("fxInvert", fxInvert);
    loadFxStacks(o);
    stopFps = constrain(o.getInt("stopFps", stopFps), 1, 25);
    stopOnion = o.getBoolean("stopOnion", stopOnion);
    stopOnionAmt = constrain(o.getFloat("stopOnionAmt", stopOnionAmt), 0, 1);
    stopOnionExternal = o.getBoolean("stopOnionExternal", stopOnionExternal);
    stopClearOnBake = o.getBoolean("stopClearOnBake", stopClearOnBake);
    stopZoom = constrain(o.getFloat("stopZoom", stopZoom), LIVE_ZOOM_MIN, LIVE_ZOOM_MAX);
    stopPanX = o.getFloat("stopPanX", stopPanX);
    stopPanY = o.getFloat("stopPanY", stopPanY);
    stopTwist = o.getFloat("stopTwist", stopTwist);
    dirtyStopView();
    animMode = constrain(o.getInt("workMode", animMode), ANIM_LIVE, ANIM_DRAW);
    topMode = constrain(o.getInt("topMode", animMode), TOP_LIVE, TOP_NOTES);
    drawBrush = constrain(o.getFloat("drawBrush", drawBrush), DRAW_BRUSH_MIN, DRAW_BRUSH_MAX);
    drawColorIdx = constrain(o.getInt("drawColor", drawColorIdx), 0, drawSwatches.length - 1);
    if (o.hasKey("drawSwatches")) {
      JSONArray sw = o.getJSONArray("drawSwatches");
      if (sw != null) {
        for (int i = 0; i < min(drawSwatches.length, sw.size()); i++) {
          drawSwatches[i] = sw.getInt(i) | 0xFF000000;
        }
      }
    }
    drawTool = constrain(o.getInt("drawTool", drawTool), DRAW_PENCIL, DRAW_ROUNDRECT);
    drawRaster = o.getBoolean("drawRaster", drawRaster);
    drawTrackpadMode = o.getBoolean("drawTrackpadMode", drawTrackpadMode);
    drawCursorExternal = o.getBoolean("drawCursorExternal", drawCursorExternal);
    drawLiveUnderlay = o.getBoolean("drawLiveUnderlay", drawLiveUnderlay);
    drawShapeFill = o.getBoolean("drawShapeFill", drawShapeFill);
    // Swatches are source of truth; legacy hue/sat/light only if no palette saved.
    if (!o.hasKey("drawSwatches")) {
      drawHue = constrain(o.getFloat("drawHue", drawHue), 0, 360);
      drawSat = constrain(o.getFloat("drawSat", drawSat), 0, 1);
      drawLight = constrain(o.getFloat("drawLight", drawLight), 0, 1);
      drawSwatches[constrain(drawColorIdx, 0, drawSwatches.length - 1)] = drawInk() | 0xFF000000;
    } else {
      setDrawColorFromRgb(drawSwatches[drawColorIdx]);
    }
    inspectorTab = constrain(o.getInt("inspector", inspectorTab), 0, 3);
    takeCount = o.getInt("takeCount", takeCount);
    loadMidi(o);
    loadMidiMapFile();
    if (o.hasKey("corners")) {
      JSONArray arr = o.getJSONArray("corners");
      if (arr != null && arr.size() == 4) {
        corners = new float[4][2];
        for (int i = 0; i < 4; i++) {
          JSONObject p = arr.getJSONObject(i);
          corners[i][0] = p.getFloat("x", cornersDefault[i][0]);
          corners[i][1] = p.getFloat("y", cornersDefault[i][1]);
        }
        cornersReady = true;
      }
    }
    clampDisplay();
    if (capW != prevW || capH != prevH) allocateBuffers();
    applySource();
  } catch (Exception e) {
    println("Settings unreadable, using defaults.");
  }
}

void saveSettings() {
  if (!projectOpen) {
    saveAppPrefs();
    return;
  }
  try {
    ensureProjectDirs();
    JSONObject o = new JSONObject();
    o.setInt("version", 3);
    o.setInt("capW", capW);
    o.setInt("capH", capH);
    o.setInt("capFps", capFps);
    o.setInt("undoSteps", undoSteps);
    o.setInt("blend", blendKind);
    o.setFloat("liveOpacity", liveOpacity);
    o.setFloat("loopOpacity", loopOpacity);
    o.setBoolean("liveInOutput", liveInOutput);
    o.setFloat("inputFadeMs", inputFadeMs);
    o.setBoolean("mirror", mirror);
    o.setBoolean("tetherFocusAssist", tetherFocusAssist);
    o.setBoolean("tetherAutoFocus", tetherAutoFocus);
    o.setBoolean("tetherAutoExposure", tetherAutoExposure);
    o.setBoolean("syphonOut", syphonOut);
    o.setBoolean("showGrid", showGrid);
    o.setInt("fullscreen", outputFullscreen ? 1 : 0);
    o.setInt("outputFullscreen", outputFullscreen ? 1 : 0);
    o.setString("displayId", outputDisplayId == null ? "" : outputDisplayId);
    o.setBoolean("beamerOpen", beamerOpen);
    o.setBoolean("rawPipDesktop", rawPipDesktop);
    o.setBoolean("rawPipExternal", rawPipExternal);
    o.setInt("source", sourceMode);
    o.setInt("testPattern", testPattern);
    o.setString("camera", cameraName == null ? "" : cameraName);
    o.setInt("syIndex", syIndex);
    if (syIndex >= 0 && syIndex < syEntries.size()) {
      o.setString("syApp", syEntries.get(syIndex).app);
      o.setString("syServer", syEntries.get(syIndex).server);
    } else {
      o.setString("syApp", savedSyApp);
      o.setString("syServer", savedSyServer);
    }
    o.setFloat("camZoom", camZoom);
    o.setFloat("camPanX", camPanX);
    o.setFloat("camPanY", camPanY);
    o.setFloat("camTwist", camTwist);
    o.setFloat("liveCropL", liveCropL);
    o.setFloat("liveCropT", liveCropT);
    o.setFloat("liveCropR", liveCropR);
    o.setFloat("liveCropB", liveCropB);
    o.setFloat("liveFeather", liveFeather);
    o.setInt("camScale", camScale);
    o.setInt("camRotation", camRotation);
    saveHardwareSettings(o);
    o.setFloat("camExposure", camExposure);
    o.setFloat("camBrilliance", camBrilliance);
    o.setFloat("camHighlights", camHighlights);
    o.setFloat("camShadows", camShadows);
    o.setFloat("camBrightness", camBrightness);
    o.setFloat("camBlack", camBlack);
    o.setFloat("camContrast", camContrast);
    o.setFloat("camSaturation", camSaturation);
    o.setFloat("camVibrance", camVibrance);
    o.setFloat("camWarmth", camWarmth);
    o.setFloat("camTint", camTint);
    o.setFloat("camSharp", camSharp);
    o.setFloat("camClarity", camClarity);
    o.setFloat("camNoise", camNoise);
    o.setFloat("camVignette", camVignette);
    saveCurves(o);
    saveSourceMemories(o);
    syncFlatFxFromLive();
    o.setFloat("fxFeedback", fxFeedback);
    o.setFloat("fxHue", fxHue);
    o.setInt("fxPosterize", fxPosterize);
    o.setFloat("fxThreshold", fxThreshold);
    o.setInt("fxPixel", fxPixel);
    o.setBoolean("fxInvert", fxInvert);
    saveFxStacks(o);
    o.setInt("stopFps", stopFps);
    o.setBoolean("stopOnion", stopOnion);
    o.setFloat("stopOnionAmt", stopOnionAmt);
    o.setBoolean("stopOnionExternal", stopOnionExternal);
    o.setBoolean("stopClearOnBake", stopClearOnBake);
    o.setFloat("stopZoom", stopZoom);
    o.setFloat("stopPanX", stopPanX);
    o.setFloat("stopPanY", stopPanY);
    o.setFloat("stopTwist", stopTwist);
    o.setInt("workMode", animMode);
    o.setInt("topMode", topMode);
    o.setFloat("drawBrush", drawBrush);
    o.setInt("drawColor", drawColorIdx);
    JSONArray swOut = new JSONArray();
    for (int i = 0; i < drawSwatches.length; i++) swOut.append(drawSwatches[i]);
    o.setJSONArray("drawSwatches", swOut);
    o.setInt("drawTool", drawTool);
    o.setBoolean("drawRaster", drawRaster);
    o.setBoolean("drawTrackpadMode", drawTrackpadMode);
    o.setBoolean("drawCursorExternal", drawCursorExternal);
    o.setBoolean("drawLiveUnderlay", drawLiveUnderlay);
    o.setBoolean("drawShapeFill", drawShapeFill);
    o.setFloat("drawHue", drawHue);
    o.setFloat("drawSat", drawSat);
    o.setFloat("drawLight", drawLight);
    o.setInt("inspector", inspectorTab);
    o.setInt("takeCount", takeCount);
    saveMidi(o);
    JSONArray arr = new JSONArray();
    for (int i = 0; i < 4; i++) {
      JSONObject p = new JSONObject();
      p.setFloat("x", corners[i][0]);
      p.setFloat("y", corners[i][1]);
      arr.setJSONObject(i, p);
    }
    o.setJSONArray("corners", arr);
    saveJSONObject(o, projectSettingsPath());
    saveMidiMapFile();
    writeProjectMeta();
    saveAppPrefs();
  } catch (Exception e) {
    println("Save failed: " + e.getMessage());
  }
}
