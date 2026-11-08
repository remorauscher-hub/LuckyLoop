// Work modes: Live (dub) · Stoptrick · Draw.
// Pixel buffer only — no JAVA2D offscreen inside P3D (that crashes JOGL).

static final int ANIM_LIVE = 0;
static final int ANIM_STOP = 1;
static final int ANIM_DRAW = 2;
/** @deprecated use ANIM_LIVE */
static final int ANIM_OFF = ANIM_LIVE;

/** Top strip: LIVE · STOPTRICK · DRAW · TEXT · FX · OUTPUT */
static final int TOP_LIVE = 0;
static final int TOP_STOP = 1;
static final int TOP_DRAW = 2;
static final int TOP_FX = 3;
static final int TOP_OUTPUT = 4;
static final int TOP_NOTES = 5;

/** MS Paint–style tools */
static final int DRAW_PENCIL = 0;
static final int DRAW_BRUSH = 1;
static final int DRAW_ERASER = 2;
static final int DRAW_FILL = 3;
static final int DRAW_PICK = 4;
static final int DRAW_SPRAY = 5;
static final int DRAW_LINE = 6;
static final int DRAW_RECT = 7;
static final int DRAW_ELLIPSE = 8;
static final int DRAW_ROUNDRECT = 9;

int animMode = ANIM_LIVE;
int topMode = TOP_LIVE;

PImage drawImg; // ARGB ink plate
boolean drawDirty = false;
boolean drawPadOn = false;
boolean drawTouching = false;
boolean drawAltDown = false; // leftover key flag; brush is mouse click-drag
float drawNX = 0.5f;
float drawNY = 0.5f;
float drawLastX = -1;
float drawLastY = -1;
int drawInkSeenAt = 0;
float drawBrush = 8;
final float DRAW_BRUSH_MIN = 1;
final float DRAW_BRUSH_MAX = 200; // was 48 — allow fat paint strokes
int drawColorIdx = 0; // active swatch 0..5
boolean padMouseFallback = false;
float[] padSample = new float[2];
boolean drawTrackpadMode = false; // absolute pad = touchscreen draw (no mouse press)
boolean drawPadFingerDown = false;
int drawPadUpFrames = 0; // empty Multitouch polls before ending a stroke
boolean metaHeld = false; // ⌘ held — Cmd+pinch adjusts brush size
boolean drawCursorExternal = true; // brush ghost on Syphon / beamer
boolean drawLiveUnderlay = true; // keep live as background when no loop exists
PGraphics drawCursorGfx;
PImage drawCursorPlate; // CPU copy for safe image() into drawCursorGfx

int drawTool = DRAW_BRUSH;
boolean drawRaster = false; // hard pixels like classic Paint
boolean drawShapeFill = true; // filled rect / ellipse / roundrect (Paint default)
float drawHue = 0;
float drawSat = 1;
float drawLight = 0.92f; // default white swatch lightness
boolean hslDragPad = false;
boolean drawHslOpen = false; // HSL pad only after double-click on a swatch
float hslPadX, hslPadY, hslPadW, hslPadH;
PImage hslPadImg;
int hslPadCachedW = 0, hslPadCachedH = 0;

/** Six editable presets — same defaults as LuckyPad. ARGB. */
int[] drawSwatches = {
  0xFFECECEF, // White
  0xFFC4A573, // Warm
  0xFFD17068, // Signal
  0xFF141417, // Dark
  0xFFF2B838, // Amber
  0xFF59C7DB  // Cyan
};

boolean drawShapeOn = false;
float drawShapeX0, drawShapeY0, drawShapeX1, drawShapeY1;
int[] drawShapeBackup;

static final int DRAW_UNDO_MAX = 24;
ArrayList<int[]> drawUndoStack = new ArrayList<int[]>();
ArrayList<int[]> drawRedoStack = new ArrayList<int[]>();
boolean drawStrokeUndoArmed = false; // one snapshot per freehand gesture

float previewIx, previewIy, previewIw, previewIh;

color drawInk() {
  return hslToColor(drawHue, drawSat, drawLight);
}

int hslToColor(float h, float s, float l) {
  h = ((h % 360f) + 360f) % 360f;
  s = constrain(s, 0, 1);
  l = constrain(l, 0, 1);
  float c = (1f - abs(2f * l - 1f)) * s;
  float hp = h / 60f;
  float x = c * (1f - abs(hp % 2f - 1f));
  float r = 0, g = 0, b = 0;
  if (hp < 1) { r = c; g = x; }
  else if (hp < 2) { r = x; g = c; }
  else if (hp < 3) { g = c; b = x; }
  else if (hp < 4) { g = x; b = c; }
  else if (hp < 5) { r = x; b = c; }
  else { r = c; b = x; }
  float m = l - c * 0.5f;
  return color(
    constrain(round((r + m) * 255), 0, 255),
    constrain(round((g + m) * 255), 0, 255),
    constrain(round((b + m) * 255), 0, 255),
    255);
}

void colorToHsl(int argb, float[] out) {
  float r = ((argb >> 16) & 255) / 255f;
  float g = ((argb >> 8) & 255) / 255f;
  float b = (argb & 255) / 255f;
  float maxc = max(r, max(g, b));
  float minc = min(r, min(g, b));
  float l = (maxc + minc) * 0.5f;
  float s = 0, h = 0;
  float d = maxc - minc;
  if (d > 1e-5f) {
    s = d / (1f - abs(2f * l - 1f));
    if (maxc == r) h = 60f * (((g - b) / d) % 6f);
    else if (maxc == g) h = 60f * ((b - r) / d + 2f);
    else h = 60f * ((r - g) / d + 4f);
  }
  if (h < 0) h += 360f;
  out[0] = h;
  out[1] = constrain(s, 0, 1);
  out[2] = constrain(l, 0, 1);
}

void setDrawColorFromRgb(int argb) {
  float[] hsl = new float[3];
  colorToHsl(argb, hsl);
  drawHue = hsl[0];
  drawSat = hsl[1];
  drawLight = hsl[2];
  markDirty();
}

void applyDrawSwatch(int idx) {
  drawColorIdx = constrain(idx, 0, drawSwatches.length - 1);
  setDrawColorFromRgb(drawSwatches[drawColorIdx]);
  luckyPadSyncColor();
  luckyPadSyncColorIdx();
  markDirty();
}

/** Write current HSL into the active swatch and push to iPad. */
void commitDrawSwatchFromHsl() {
  int rgb = drawInk() | 0xFF000000;
  drawSwatches[constrain(drawColorIdx, 0, drawSwatches.length - 1)] = rgb;
  luckyPadSyncSwatch(drawColorIdx);
  luckyPadSyncColor();
  markDirty();
}

void selectDrawSwatchClosest(int rgb) {
  int best = 0;
  long bestD = Long.MAX_VALUE;
  int rr = (rgb >> 16) & 255, gg = (rgb >> 8) & 255, bb = rgb & 255;
  for (int i = 0; i < drawSwatches.length; i++) {
    int c = drawSwatches[i];
    long dr = rr - ((c >> 16) & 255);
    long dg = gg - ((c >> 8) & 255);
    long db = bb - (c & 255);
    long d = dr * dr + dg * dg + db * db;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  drawColorIdx = best;
  // Exact pad preset tap — keep swatch as-is; free RGB still selects nearest.
  if (bestD > 3) {
    drawSwatches[best] = 0xFF000000 | (rgb & 0xFFFFFF);
  }
}

boolean liveModeOn() {
  return animMode == ANIM_LIVE;
}

boolean drawModeOn() {
  return animMode == ANIM_DRAW;
}

boolean stopModeOn() {
  return animMode == ANIM_STOP;
}

boolean fxViewOn() {
  return topMode == TOP_FX;
}

boolean outputEditOn() {
  return topMode == TOP_OUTPUT;
}

boolean notesViewOn() {
  return topMode == TOP_NOTES;
}

String workModeLabel() {
  if (animMode == ANIM_STOP) return "Stoptrick";
  if (animMode == ANIM_DRAW) return "Draw";
  return "Live";
}

void setTopMode(int next) {
  next = constrain(next, TOP_LIVE, TOP_NOTES);
  boolean leaveSet = inspectorTab == 3;
  if (next == topMode && !leaveSet) return;
  // Mode strip owns the right dock — exit SET when a mode is chosen.
  if (leaveSet) inspectorTab = lastWorkTab;
  if (next == topMode) {
    markDirty();
    return;
  }
  if (topMode == TOP_NOTES) flushNotesIfDirty();
  topMode = next;
  if (next <= TOP_DRAW) {
    setWorkMode(next);
  } else {
    if (next == TOP_NOTES) {
      leaveDrawWork();
      textFontOpen = false;
      notesFocus = false; // click a field to type (mutes shortcuts)
      note("Text  ·  on the live image");
    } else if (next == TOP_FX) note("FX");
    else if (next == TOP_OUTPUT) note("Output  ·  drag corners on preview");
  }
  markDirty();
}

/** True while Draw work mode is active (mouse click-drag draws on preview). */
boolean drawArmed() {
  return drawModeOn();
}

void setDrawAlt(boolean on) {
  drawAltDown = on;
}

void setDrawTool(int tool) {
  drawTool = constrain(tool, DRAW_PENCIL, DRAW_ROUNDRECT);
  drawShapeCancel();
  luckyPadSyncStyle();
  markDirty();
  note("Draw  ·  " + drawToolLabel(drawTool) + (drawRaster ? "  ·  raster" : ""));
}

String drawToolLabel(int tool) {
  switch (tool) {
    case DRAW_PENCIL: return "Pencil";
    case DRAW_BRUSH: return "Brush";
    case DRAW_ERASER: return "Eraser";
    case DRAW_FILL: return "Fill";
    case DRAW_PICK: return "Pick";
    case DRAW_SPRAY: return "Spray";
    case DRAW_LINE: return "Line";
    case DRAW_RECT: return "Rect";
    case DRAW_ELLIPSE: return "Ellipse";
    case DRAW_ROUNDRECT: return "Round rect";
  }
  return "Brush";
}

boolean drawToolIsShape() {
  return drawTool == DRAW_LINE || drawTool == DRAW_RECT
    || drawTool == DRAW_ELLIPSE || drawTool == DRAW_ROUNDRECT;
}

void setDrawRaster(boolean on) {
  if (drawRaster == on) return;
  drawRaster = on;
  luckyPadSyncStyle();
  luckyPadRequestPreview(true);
  markDirty();
  note(drawRaster ? "Raster on  ·  hard pixels" : "Raster off  ·  soft brush");
}

void setDrawTrackpadMode(boolean on) {
  if (drawTrackpadMode == on) return;
  drawTrackpadMode = on;
  drawPadFingerDown = false;
  if (drawModeOn()) startDrawPad(); // pad also feeds Cmd+pinch
  if (drawTrackpadMode) {
    note(padMouseFallback
      ? "Trackpad mode  ·  lib missing — use mouse"
      : "Trackpad mode  ·  finger draws (absolute)");
  } else if (drawModeOn()) {
    note("Draw  ·  click & drag  ·  ⌘ pinch = size");
  }
  markDirty();
}

/** Draw owns the canvas until another work mode or Text takes over. */
void leaveDrawWork() {
  if (animMode != ANIM_DRAW) return;
  animMode = ANIM_LIVE;
  luckyPadOnDraw(false);
  tetherPaintArm(false); // keep phone camera-only
  stopDrawPad();
  drawTouching = false;
  drawLastX = -1;
  drawPadFingerDown = false;
  drawShapeCancel();
  hslDragPad = false;
  drawHslOpen = false;
  selectedLayer = -1;
}

/** Exclusive work mode — Live / Stoptrick / Draw. No toggle-off. */
void setWorkMode(int next) {
  next = constrain(next, ANIM_LIVE, ANIM_DRAW);
  topMode = next;
  if (next == animMode) return;
  boolean wasDraw = animMode == ANIM_DRAW;
  animMode = next;
  if (animMode == ANIM_DRAW) {
    ensureDrawImg();
    selectedLayer = SEL_STOP;
    luckyPadOnDraw(true);
    tetherPaintArm(false); // phone stays cam — ink is LuckyPad
    drawShapeCancel();
    drawPadFingerDown = false;
    startDrawPad(); // absolute draw + Cmd+pinch magnify
    note(drawTrackpadMode ? "Draw  ·  trackpad absolute" : "Draw  ·  click & drag  ·  ⌘ pinch = size");
  } else {
    if (wasDraw) {
      luckyPadOnDraw(false);
      tetherPaintArm(false);
    }
    stopDrawPad();
    drawTouching = false;
    drawLastX = -1;
    drawPadFingerDown = false;
    drawShapeCancel();
    hslDragPad = false;
    if (animMode == ANIM_STOP) {
      selectedLayer = SEL_STOP;
      if (stopPlaying) stopTogglePlay();
      note("Stoptrick  ·  Enter shoots  ·  Space plays");
    } else {
      selectedLayer = -1;
      note("Live  ·  Space records / overdubs");
    }
  }
  markDirty();
}

void setAnimMode(int mode) {
  setWorkMode(mode);
}

void ensureDrawImg() {
  if (drawImg == null || drawImg.width != capW || drawImg.height != capH) {
    drawImg = createImage(capW, capH, ARGB);
    drawImg.loadPixels();
    java.util.Arrays.fill(drawImg.pixels, 0);
    drawImg.updatePixels();
    drawDirty = false;
    drawLastX = -1;
    drawShapeBackup = null;
  }
}

void drawClearUndo() {
  drawUndoStack.clear();
  drawRedoStack.clear();
  drawStrokeUndoArmed = false;
}

void drawPushUndoSnap(int[] src) {
  if (src == null) return;
  int[] snap = new int[src.length];
  arrayCopy(src, snap);
  drawUndoStack.add(snap);
  while (drawUndoStack.size() > DRAW_UNDO_MAX) drawUndoStack.remove(0);
  drawRedoStack.clear();
}

/** Snapshot current ink plate before a destructive edit. */
void drawPushUndo() {
  ensureDrawImg();
  drawImg.loadPixels();
  drawPushUndoSnap(drawImg.pixels);
}

boolean drawUndo() {
  if (drawUndoStack.isEmpty()) return false;
  ensureDrawImg();
  drawImg.loadPixels();
  int[] cur = new int[drawImg.pixels.length];
  arrayCopy(drawImg.pixels, cur);
  drawRedoStack.add(cur);
  int[] prev = drawUndoStack.remove(drawUndoStack.size() - 1);
  arrayCopy(prev, drawImg.pixels);
  drawImg.updatePixels();
  drawDirty = false;
  for (int i = 0; i < drawImg.pixels.length; i++) {
    if (((drawImg.pixels[i] >>> 24) & 255) > 0) { drawDirty = true; break; }
  }
  drawLastX = -1;
  drawTouching = false;
  luckyPadRequestPreview(true);
  note(drawDirty ? "Undo" : "Undo  ·  empty frame");
  return true;
}

boolean drawRedo() {
  if (drawRedoStack.isEmpty()) return false;
  ensureDrawImg();
  drawImg.loadPixels();
  int[] cur = new int[drawImg.pixels.length];
  arrayCopy(drawImg.pixels, cur);
  drawUndoStack.add(cur);
  while (drawUndoStack.size() > DRAW_UNDO_MAX) drawUndoStack.remove(0);
  int[] next = drawRedoStack.remove(drawRedoStack.size() - 1);
  arrayCopy(next, drawImg.pixels);
  drawImg.updatePixels();
  drawDirty = false;
  for (int i = 0; i < drawImg.pixels.length; i++) {
    if (((drawImg.pixels[i] >>> 24) & 255) > 0) { drawDirty = true; break; }
  }
  drawLastX = -1;
  luckyPadRequestPreview(true);
  note("Redo");
  return true;
}

/** Cmd+Z in Draw: stroke undo, else pop last stop frame. */
void drawOrStopUndo() {
  if (drawShapeOn) drawShapeCancel();
  if (drawUndo()) return;
  if (hasStop()) stopPopLast();
  else note("Nothing to undo");
}

void drawOrStopRedo() {
  if (drawRedo()) return;
  redo();
}

void drawClearCanvas() {
  ensureDrawImg();
  drawImg.loadPixels();
  java.util.Arrays.fill(drawImg.pixels, 0);
  drawImg.updatePixels();
  drawDirty = false;
  drawLastX = -1;
  drawClearUndo();
  drawShapeCancel();
}

void drawClearFrame() {
  drawClearCanvas();
  luckyPadRequestPreview(true);
  note("Frame cleared");
}

void drawResetBuffers() {
  stopDrawPad();
  drawImg = null;
  drawDirty = false;
  drawTouching = false;
  drawLastX = -1;
  drawShapeBackup = null;
  drawClearUndo();
  hslPadImg = null;
  if (animMode == ANIM_DRAW) animMode = ANIM_OFF;
}

boolean drawHasInk() {
  return drawDirty && drawImg != null;
}

void startDrawPad() {
  if (drawPadOn) return;
  PadCtl.load(sketchPath("data/libpadctl.dylib"));
  if (!PadCtl.loaded) {
    padMouseFallback = true;
    drawPadOn = true;
    note("Trackpad lib missing");
    return;
  }
  // Live framing may already own the multitouch session.
  if (framePadOn) {
    padMouseFallback = false;
    drawPadOn = true;
    return;
  }
  int ok = 0;
  try {
    ok = PadCtl.start();
  } catch (Throwable t) {
    ok = 0;
  }
  if (ok != 1) {
    padMouseFallback = true;
    drawPadOn = true;
    note("Trackpad start failed");
    return;
  }
  padMouseFallback = false;
  drawPadOn = true;
}

void stopDrawPad() {
  if (!drawPadOn) return;
  drawPadOn = false;
  drawPadFingerDown = false;
  drawPadUpFrames = 0;
  // Keep multitouch alive when live framing still needs the trackpad.
  if (PadCtl.loaded && !framePadOn) {
    try { PadCtl.stop(); } catch (Throwable t) {}
  }
  if (drawShapeOn) drawShapeFinish();
  else if (drawTouching) {
    drawTouching = false;
    drawLastX = -1;
  }
}

void serviceDrawPad() {
  try {
    if (!drawModeOn()) {
      if (drawPadOn) stopDrawPad();
      return;
    }
    serviceLuckyPadInk();

    // Mac trackpad stays up in Draw for absolute ink and/or Cmd+pinch brush size.
    // iPad ink arrives via LuckyPad (separate from LuckyTether camera).
    if (!drawPadOn) startDrawPad();

    if (drawTrackpadMode && !padMouseFallback && PadCtl.loaded && !metaHeld) {
      int down = 0;
      try {
        down = PadCtl.poll(padSample);
      } catch (Throwable t) {
        down = 0;
      }

      float nx = constrain(padSample[0], 0, 1);
      float ny = constrain(padSample[1], 0, 1);
      drawNX = nx;
      drawNY = ny;

      if (previewIw >= 2 && previewIh >= 2) {
        // Absolute pad → preview (touchscreen): finger contact draws, no mouse press.
        // Clamp so edge swipes stay one stroke (bounds reject was breaking lines into dots).
        float mx = constrain(previewIx + nx * previewIw, previewIx, previewIx + previewIw);
        float my = constrain(previewIy + (1f - ny) * previewIh, previewIy, previewIy + previewIh);
        if (down > 0) {
          drawPadUpFrames = 0;
          boolean start = !drawPadFingerDown;
          drawPadFingerDown = true;
          drawMouseStroke(mx, my, start);
        } else if (drawPadFingerDown) {
          // MultitouchSupport often inserts empty frames mid-swipe — keep the stroke alive.
          drawPadUpFrames++;
          if (drawPadUpFrames >= 3) {
            drawPadFingerDown = false;
            drawPadUpFrames = 0;
            drawMouseReleased();
          }
        }
      }
    } else {
      if (drawPadFingerDown) {
        drawPadFingerDown = false;
        drawPadUpFrames = 0;
        drawMouseReleased();
      }
      if (!drawTrackpadMode || metaHeld) drawUpdateHover(mouseX, mouseY);
    }

    serviceDrawBrushPinch();
  } catch (Throwable t) {
    println("draw service: " + t.getMessage());
  }
}

/** ⌘ + trackpad pinch → brush size. */
void serviceDrawBrushPinch() {
  if (!metaHeld || padMouseFallback || !PadCtl.loaded) return;
  float mag = 0;
  try {
    mag = PadCtl.pollMagnify();
  } catch (Throwable t) {
    return;
  }
  if (abs(mag) < 0.00001f) return;
  float next = constrain(drawBrush * (1f + mag * 4.2f), DRAW_BRUSH_MIN, DRAW_BRUSH_MAX);
  if (abs(next - drawBrush) < 0.04f) return;
  drawBrush = next;
  luckyPadSyncBrush();
  markDirty();
}

float drawBrushPx() {
  if (drawRaster) return drawRasterCell();
  if (drawTool == DRAW_PENCIL) return max(1f, drawBrush * 0.25f * (capH / 1080f));
  return max(1f, drawBrush * (capH / 1080f));
}

/** Coarse paint-pixel size so stair-steps read on HD canvases. */
int drawRasterCell() {
  float u = drawBrush * (capH / 1080f);
  if (drawTool == DRAW_PENCIL) return max(3, round(max(2f, u * 0.55f)));
  if (drawTool == DRAW_LINE) return max(3, round(max(2f, u * 0.85f)));
  // Shapes: same chunky grid so rect / oval / round read as pixels
  if (drawToolIsShape()) return max(3, round(max(2f, u * 0.85f)));
  return max(2, round(max(1f, u)));
}

float drawSnap(float v) {
  if (!drawRaster) return v;
  int c = drawRasterCell();
  return floor(v / c) * c + c * 0.5f;
}

/** Fill one raster cell (opaque block). gx/gy are cell indices. */
void drawRasterCellFill(int[] pix, int w, int h, int gx, int gy, int ink) {
  int c = drawRasterCell();
  int x0 = gx * c;
  int y0 = gy * c;
  int x1 = min(w, x0 + c);
  int y1 = min(h, y0 + c);
  if (x0 >= w || y0 >= h || x1 <= 0 || y1 <= 0) return;
  x0 = max(0, x0);
  y0 = max(0, y0);
  int solid = ink | 0xFF000000;
  for (int y = y0; y < y1; y++) {
    int row = y * w;
    for (int x = x0; x < x1; x++) pix[row + x] = solid;
  }
}

void drawRasterCellErase(int[] pix, int w, int h, int gx, int gy) {
  int c = drawRasterCell();
  int x0 = max(0, gx * c);
  int y0 = max(0, gy * c);
  int x1 = min(w, x0 + c);
  int y1 = min(h, y0 + c);
  for (int y = y0; y < y1; y++) {
    int row = y * w;
    for (int x = x0; x < x1; x++) pix[row + x] = 0;
  }
}

/** Bresenham across the coarse grid — stair-steps stay visible. */
void drawRasterGridLine(int[] pix, int w, int h, float x0, float y0, float x1, float y1, int ink, boolean erase) {
  int c = max(1, drawRasterCell());
  int gx0 = floor(x0 / c);
  int gy0 = floor(y0 / c);
  int gx1 = floor(x1 / c);
  int gy1 = floor(y1 / c);
  int dx = abs(gx1 - gx0), sx = gx0 < gx1 ? 1 : -1;
  int dy = -abs(gy1 - gy0), sy = gy0 < gy1 ? 1 : -1;
  int err = dx + dy;
  while (true) {
    if (erase) drawRasterCellErase(pix, w, h, gx0, gy0);
    else drawRasterCellFill(pix, w, h, gx0, gy0, ink);
    if (gx0 == gx1 && gy0 == gy1) break;
    int e2 = 2 * err;
    if (e2 >= dy) { err += dy; gx0 += sx; }
    if (e2 <= dx) { err += dx; gy0 += sy; }
  }
}

/** Soft or hard circle / square stamp into ARGB plate. erase=true clears alpha. */
void drawStamp(int[] pix, int w, int h, float cx, float cy, float diam, int ink, boolean erase) {
  boolean hard = drawRaster || drawTool == DRAW_PENCIL || erase;
  boolean square = drawRaster && (drawTool == DRAW_PENCIL || drawTool == DRAW_ERASER);
  float r = diam * 0.5f;
  if (r < 0.5f) r = 0.5f;
  if (drawRaster) {
    cx = floor(cx);
    cy = floor(cy);
  }
  int x0 = max(0, floor(cx - r - 1));
  int y0 = max(0, floor(cy - r - 1));
  int x1 = min(w - 1, ceil(cx + r + 1));
  int y1 = min(h - 1, ceil(cy + r + 1));
  int ir = (ink >> 16) & 255;
  int ig = (ink >> 8) & 255;
  int ib = ink & 255;
  float r2 = r * r;
  for (int y = y0; y <= y1; y++) {
    float dy = y + 0.5f - cy;
    int row = y * w;
    for (int x = x0; x <= x1; x++) {
      float dx = x + 0.5f - cx;
      float d2;
      if (square) {
        if (abs(dx) > r || abs(dy) > r) continue;
        d2 = 0;
      } else {
        d2 = dx * dx + dy * dy;
        if (d2 > r2) continue;
      }
      int i = row + x;
      if (erase) {
        if (hard) {
          pix[i] = 0;
        } else {
          float a = 1f - sqrt(d2) / r;
          if (a <= 0) continue;
          int da = (pix[i] >>> 24) & 255;
          int na = constrain(da - round(a * 255), 0, 255);
          if (na <= 0) pix[i] = 0;
          else pix[i] = (na << 24) | (pix[i] & 0x00FFFFFF);
        }
        continue;
      }
      int na;
      if (hard) {
        na = 255;
      } else {
        float a = 1f - sqrt(d2) / r;
        if (a <= 0) continue;
        na = constrain(round(a * 255), 1, 255);
      }
      int dst = pix[i];
      int da = (dst >>> 24) & 255;
      if (da == 0 || hard) {
        pix[i] = (na << 24) | (ir << 16) | (ig << 8) | ib;
        continue;
      }
      int outA = na + da * (255 - na) / 255;
      if (outA <= 0) continue;
      int dr = (dst >> 16) & 255;
      int dg = (dst >> 8) & 255;
      int db = dst & 255;
      int or_ = (ir * na + dr * da * (255 - na) / 255) / outA;
      int og = (ig * na + dg * da * (255 - na) / 255) / outA;
      int ob = (ib * na + db * da * (255 - na) / 255) / outA;
      pix[i] = (outA << 24) | (or_ << 16) | (og << 8) | ob;
    }
  }
}

void drawStamp(int[] pix, int w, int h, float cx, float cy, float diam, int ink) {
  drawStamp(pix, w, h, cx, cy, diam, ink, false);
}

void drawSprayAt(int[] pix, int w, int h, float cx, float cy, float diam, int ink) {
  float r = max(1f, diam * 0.5f);
  int n = max(4, round(r * (drawRaster ? 1.2f : 2.2f)));
  for (int i = 0; i < n; i++) {
    float ang = random(TWO_PI);
    float rad = sqrt(random(1)) * r;
    float px = cx + cos(ang) * rad;
    float py = cy + sin(ang) * rad;
    float dot = drawRaster ? 1f : max(1f, diam * 0.12f);
    drawStamp(pix, w, h, px, py, dot, ink, false);
  }
}

void drawStrokeTo(float x, float y, boolean start) {
  drawStrokeTo(x, y, start, true);
}

/** Stamp into the ink plate. Pass flush=false when batching many tether samples. */
void drawStrokeTo(float x, float y, boolean start, boolean flush) {
  ensureDrawImg();
  x = drawSnap(x);
  y = drawSnap(y);
  float brush = drawBrushPx();
  int ink = drawInk();
  boolean erase = drawTool == DRAW_ERASER;
  if (flush) drawImg.loadPixels();
  float prevX = drawLastX;
  float prevY = drawLastY;
  boolean segStart = start || prevX < 0;
  drawStrokeSegment(prevX, prevY, x, y, segStart, brush, ink, erase);
  drawStrokeSymmetry(prevX, prevY, x, y, segStart, brush, ink, erase);
  drawLastX = x;
  drawLastY = y;
  drawDirty = true;
  if (flush) drawImg.updatePixels();
}

/** Live Mirror / Quad / Flip — stamp replicas so strokes stay mirrored while painting. */
int drawLiveSymmetry() {
  if (fxLive == null) return -1;
  int mode = -1;
  for (int i = 0; i < fxLive.size(); i++) {
    FxUnit u = fxLive.get(i);
    if (u == null || u.fade < 0.45f) continue;
    if (u.type == FX_QUAD) mode = 2;
    else if (u.type == FX_MIRROR) mode = constrain(round(u.amount2), 0, 1);
    else if (u.type == FX_MIRROR_H) mode = 0;
    else if (u.type == FX_MIRROR_V) mode = 1;
    else if (u.type == FX_FLIP || u.type == FX_FLIP_V) {
      int m = u.type == FX_FLIP_V ? 1 : constrain(round(u.amount2), 0, 2);
      mode = m == 2 ? 5 : m; // Both → 180° paint symmetry
    } else if (u.type == FX_ROT180) mode = 5;
  }
  return mode;
}

void drawStrokeSymmetry(float x0, float y0, float x1, float y1, boolean start,
    float brush, int ink, boolean erase) {
  int sym = drawLiveSymmetry();
  if (sym < 0) return;
  float W = capW - 1;
  float H = capH - 1;
  if (sym == 0 || sym == 2) {
    drawStrokeSegment(x0 < 0 ? -1 : W - x0, y0, W - x1, y1, start, brush, ink, erase);
  }
  if (sym == 1 || sym == 2) {
    drawStrokeSegment(x0, y0 < 0 ? -1 : H - y0, x1, H - y1, start, brush, ink, erase);
  }
  if (sym == 2 || sym == 5) {
    drawStrokeSegment(x0 < 0 ? -1 : W - x0, y0 < 0 ? -1 : H - y0, W - x1, H - y1, start, brush, ink, erase);
  }
}

void drawStrokeSegment(float x0, float y0, float x1, float y1, boolean start,
    float brush, int ink, boolean erase) {
  // Raster pencil / eraser: blocky grid stroke (Paint-like stair steps).
  if (drawRaster && (drawTool == DRAW_PENCIL || drawTool == DRAW_ERASER)) {
    if (start || x0 < 0) drawRasterGridLine(drawImg.pixels, capW, capH, x1, y1, x1, y1, ink, erase);
    else drawRasterGridLine(drawImg.pixels, capW, capH, x0, y0, x1, y1, ink, erase);
    return;
  }
  if (start || x0 < 0) {
    if (drawTool == DRAW_SPRAY) drawSprayAt(drawImg.pixels, capW, capH, x1, y1, brush, ink);
    else drawStamp(drawImg.pixels, capW, capH, x1, y1, brush, ink, erase);
    return;
  }
  float d = dist(x0, y0, x1, y1);
  float step = drawRaster ? max(1f, brush * 0.55f) : max(0.55f, brush * 0.28f);
  int n = max(1, ceil(d / step));
  for (int i = 1; i <= n; i++) {
    float t = i / (float) n;
    float sx = lerp(x0, x1, t);
    float sy = lerp(y0, y1, t);
    if (drawTool == DRAW_SPRAY) drawSprayAt(drawImg.pixels, capW, capH, sx, sy, brush, ink);
    else drawStamp(drawImg.pixels, capW, capH, sx, sy, brush, ink, erase);
  }
}

void drawPutPixel(int[] pix, int w, int h, int x, int y, int ink) {
  if (x < 0 || y < 0 || x >= w || y >= h) return;
  pix[y * w + x] = ink | 0xFF000000;
}

void drawBresenhamLine(int[] pix, int w, int h, int x0, int y0, int x1, int y1, int ink, float thick) {
  int t = max(1, round(thick));
  int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
  int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
  int err = dx + dy;
  while (true) {
    if (t <= 1) drawPutPixel(pix, w, h, x0, y0, ink);
    else drawStamp(pix, w, h, x0 + 0.5f, y0 + 0.5f, t, ink, false);
    if (x0 == x1 && y0 == y1) break;
    int e2 = 2 * err;
    if (e2 >= dy) { err += dy; x0 += sx; }
    if (e2 <= dx) { err += dx; y0 += sy; }
  }
}

/** Signed distance of point to rounded box centered at origin. */
float drawSdfRoundBox(float px, float py, float hx, float hy, float rad) {
  float r = min(rad, min(hx, hy));
  float qx = abs(px) - (hx - r);
  float qy = abs(py) - (hy - r);
  float mx = max(qx, 0);
  float my = max(qy, 0);
  return sqrt(mx * mx + my * my) + min(max(qx, qy), 0) - r;
}

/** Soft (per-pixel) rect / ellipse / roundrect. */
void drawShapePixels(int[] pix, int w, int h, int kind, float x0, float y0, float x1, float y1,
                     int ink, boolean fill, float thick) {
  if (x0 > x1) { float t = x0; x0 = x1; x1 = t; }
  if (y0 > y1) { float t = y0; y0 = y1; y1 = t; }
  float cx = (x0 + x1) * 0.5f;
  float cy = (y0 + y1) * 0.5f;
  float hx = max(0.5f, (x1 - x0) * 0.5f);
  float hy = max(0.5f, (y1 - y0) * 0.5f);
  float rad = (kind == DRAW_ROUNDRECT) ? max(1f, min(hx, hy) * 0.45f) : 0;
  float tHalf = max(0.5f, thick * 0.5f);
  int minX = max(0, floor(x0 - thick - 1));
  int maxX = min(w - 1, ceil(x1 + thick + 1));
  int minY = max(0, floor(y0 - thick - 1));
  int maxY = min(h - 1, ceil(y1 + thick + 1));
  int solid = ink | 0xFF000000;
  for (int y = minY; y <= maxY; y++) {
    float py = y + 0.5f - cy;
    int row = y * w;
    for (int x = minX; x <= maxX; x++) {
      float px = x + 0.5f - cx;
      float d;
      if (kind == DRAW_ELLIPSE) {
        float nx = px / hx;
        float ny = py / hy;
        d = (sqrt(nx * nx + ny * ny) - 1f) * max(hx, hy);
      } else if (kind == DRAW_ROUNDRECT) {
        d = drawSdfRoundBox(px, py, hx, hy, rad);
      } else {
        d = max(abs(px) - hx, abs(py) - hy);
      }
      boolean hit = fill ? (d <= 0) : (abs(d) <= tHalf);
      if (hit) pix[row + x] = solid;
    }
  }
}

/**
 * Chunky grid shapes — each paint-cell is either in or out.
 * Corners of roundrect use the same SDF (no full circles).
 */
void drawShapeCells(int[] pix, int w, int h, int kind, float x0, float y0, float x1, float y1,
                    int ink, boolean fill) {
  int c = max(1, drawRasterCell());
  if (x0 > x1) { float t = x0; x0 = x1; x1 = t; }
  if (y0 > y1) { float t = y0; y0 = y1; y1 = t; }
  // Snap bounds to cell edges so the silhouette stays blocky
  int gx0 = floor(x0 / c);
  int gy0 = floor(y0 / c);
  int gx1 = floor(x1 / c);
  int gy1 = floor(y1 / c);
  if (gx1 < gx0) { int t = gx0; gx0 = gx1; gx1 = t; }
  if (gy1 < gy0) { int t = gy0; gy0 = gy1; gy1 = t; }

  float ax0 = gx0 * c;
  float ay0 = gy0 * c;
  float ax1 = (gx1 + 1) * c;
  float ay1 = (gy1 + 1) * c;
  float cx = (ax0 + ax1) * 0.5f;
  float cy = (ay0 + ay1) * 0.5f;
  float hx = max(c * 0.5f, (ax1 - ax0) * 0.5f);
  float hy = max(c * 0.5f, (ay1 - ay0) * 0.5f);
  float rad = (kind == DRAW_ROUNDRECT) ? max(c, min(hx, hy) * 0.45f) : 0;
  // Outline thickness ≈ one cell in continuous space
  float tHalf = c * 0.55f;

  for (int gy = gy0; gy <= gy1; gy++) {
    for (int gx = gx0; gx <= gx1; gx++) {
      float px = (gx + 0.5f) * c - cx;
      float py = (gy + 0.5f) * c - cy;
      float d;
      if (kind == DRAW_ELLIPSE) {
        float nx = px / hx;
        float ny = py / hy;
        d = (sqrt(nx * nx + ny * ny) - 1f) * max(hx, hy);
      } else if (kind == DRAW_ROUNDRECT) {
        d = drawSdfRoundBox(px, py, hx, hy, rad);
      } else {
        d = max(abs(px) - hx, abs(py) - hy);
      }
      boolean hit = fill ? (d <= 0) : (abs(d) <= tHalf);
      if (hit) drawRasterCellFill(pix, w, h, gx, gy, ink);
    }
  }
}

void drawShapeCommit(float x0, float y0, float x1, float y1) {
  ensureDrawImg();
  drawImg.loadPixels();
  if (drawShapeBackup != null && drawShapeBackup.length == drawImg.pixels.length) {
    arrayCopy(drawShapeBackup, drawImg.pixels);
  }
  int ink = drawInk();
  float thick = drawBrushPx();
  drawShapePaint(x0, y0, x1, y1, ink, thick);
  int sym = drawLiveSymmetry();
  if (sym >= 0) {
    float W = capW - 1;
    float H = capH - 1;
    if (sym == 0 || sym == 2) drawShapePaint(W - x0, y0, W - x1, y1, ink, thick);
    if (sym == 1 || sym == 2) drawShapePaint(x0, H - y0, x1, H - y1, ink, thick);
    if (sym == 2 || sym == 5) drawShapePaint(W - x0, H - y0, W - x1, H - y1, ink, thick);
  }
  drawImg.updatePixels();
  drawDirty = true;
}

void drawShapePaint(float x0, float y0, float x1, float y1, int ink, float thick) {
  if (drawTool == DRAW_LINE) {
    if (drawRaster) {
      drawRasterGridLine(drawImg.pixels, capW, capH, x0, y0, x1, y1, ink, false);
    } else {
      float d = dist(x0, y0, x1, y1);
      float step = max(0.55f, thick * 0.28f);
      int n = max(1, ceil(d / step));
      for (int i = 0; i <= n; i++) {
        float t = i / (float) n;
        drawStamp(drawImg.pixels, capW, capH, lerp(x0, x1, t), lerp(y0, y1, t), thick, ink, false);
      }
    }
  } else if (drawTool == DRAW_RECT || drawTool == DRAW_ELLIPSE || drawTool == DRAW_ROUNDRECT) {
    if (drawRaster) {
      drawShapeCells(drawImg.pixels, capW, capH, drawTool, x0, y0, x1, y1, ink, drawShapeFill);
    } else {
      drawShapePixels(drawImg.pixels, capW, capH, drawTool, x0, y0, x1, y1, ink, drawShapeFill, thick);
    }
  }
}

void drawShapeBegin(float x, float y) {
  ensureDrawImg();
  drawImg.loadPixels();
  if (drawShapeBackup == null || drawShapeBackup.length != drawImg.pixels.length) {
    drawShapeBackup = new int[drawImg.pixels.length];
  }
  arrayCopy(drawImg.pixels, drawShapeBackup);
  drawShapeOn = true;
  drawShapeX0 = drawShapeX1 = drawSnap(x);
  drawShapeY0 = drawShapeY1 = drawSnap(y);
  drawTouching = true;
}

void drawShapeUpdate(float x, float y) {
  if (!drawShapeOn) return;
  drawShapeX1 = drawSnap(x);
  drawShapeY1 = drawSnap(y);
  drawShapeCommit(drawShapeX0, drawShapeY0, drawShapeX1, drawShapeY1);
}

void drawShapeFinish() {
  if (!drawShapeOn) return;
  // Backup is pre-shape plate — keep it as undo snapshot.
  if (drawShapeBackup != null) {
    drawPushUndoSnap(drawShapeBackup);
    drawShapeBackup = null;
  }
  drawShapeOn = false;
  drawTouching = false;
  drawLastX = -1;
}

void drawShapeCancel() {
  if (drawShapeOn && drawShapeBackup != null && drawImg != null
      && drawShapeBackup.length == drawImg.pixels.length) {
    drawImg.loadPixels();
    arrayCopy(drawShapeBackup, drawImg.pixels);
    drawImg.updatePixels();
  }
  drawShapeOn = false;
  drawShapeBackup = null;
}

void drawFloodFill(float fx, float fy) {
  ensureDrawImg();
  int x = constrain(round(fx), 0, capW - 1);
  int y = constrain(round(fy), 0, capH - 1);
  drawImg.loadPixels();
  int[] pix = drawImg.pixels;
  int repl = drawInk() | 0xFF000000;
  int target = pix[y * capW + x];
  int ta = (target >>> 24) & 255;
  if (ta < 8) target = 0;
  if ((target & 0x00FFFFFF) == (repl & 0x00FFFFFF) && ((target >>> 24) & 255) > 200) {
    note("Fill  ·  nothing");
    return;
  }
  drawPushUndoSnap(pix);
  int filled = drawFloodFillAt(pix, capW, capH, x, y, target, repl);
  int sym = drawLiveSymmetry();
  if (sym >= 0) {
    int W = capW - 1, H = capH - 1;
    if (sym == 0 || sym == 2) filled += drawFloodFillAt(pix, capW, capH, W - x, y, target, repl);
    if (sym == 1 || sym == 2) filled += drawFloodFillAt(pix, capW, capH, x, H - y, target, repl);
    if (sym == 2 || sym == 5) filled += drawFloodFillAt(pix, capW, capH, W - x, H - y, target, repl);
  }
  drawImg.updatePixels();
  if (filled > 0) drawDirty = true;
  note(filled > 0 ? "Fill  ·  " + filled + " px" : "Fill  ·  nothing");
}

int drawFloodFillAt(int[] pix, int w, int h, int x, int y, int target, int repl) {
  x = constrain(x, 0, w - 1);
  y = constrain(y, 0, h - 1);
  java.util.ArrayDeque<Integer> q = new java.util.ArrayDeque<Integer>();
  boolean[] seen = new boolean[w * h];
  int start = y * w + x;
  q.add(start);
  seen[start] = true;
  int filled = 0;
  int maxFill = w * h;
  while (!q.isEmpty() && filled < maxFill) {
    int i = q.removeFirst();
    int cur = pix[i];
    int ca = (cur >>> 24) & 255;
    if (ca < 8) cur = 0;
    if (cur != target) continue;
    pix[i] = repl;
    filled++;
    int cx = i % w;
    int cy = i / w;
    if (cx > 0 && !seen[i - 1]) { seen[i - 1] = true; q.add(i - 1); }
    if (cx + 1 < w && !seen[i + 1]) { seen[i + 1] = true; q.add(i + 1); }
    if (cy > 0 && !seen[i - w]) { seen[i - w] = true; q.add(i - w); }
    if (cy + 1 < h && !seen[i + w]) { seen[i + w] = true; q.add(i + w); }
  }
  return filled;
}

void drawPickAt(float fx, float fy) {
  ensureDrawImg();
  int x = constrain(round(fx), 0, capW - 1);
  int y = constrain(round(fy), 0, capH - 1);
  drawImg.loadPixels();
  int c = drawImg.pixels[y * capW + x];
  if (((c >>> 24) & 255) < 8) {
    // Fall back to stop onion / last frame if ink is empty
    int[] sp = stopCurrentPixels();
    if (sp != null && sp.length == drawImg.pixels.length) c = sp[y * capW + x];
  }
  if (((c >>> 24) & 255) < 8) {
    note("Pick  ·  empty");
    return;
  }
  setDrawColorFromRgb(c);
  commitDrawSwatchFromHsl();
  note("Pick  ·  swatch updated");
}

/** Preview-space hover — updates brush ghost, no ink. */
void drawUpdateHover(float mx, float my) {
  if (!drawModeOn() || previewIw < 2 || previewIh < 2) return;
  if (mx < previewIx || my < previewIy || mx > previewIx + previewIw || my > previewIy + previewIh) return;
  drawNX = constrain((mx - previewIx) / previewIw, 0, 1);
  drawNY = 1f - constrain((my - previewIy) / previewIh, 0, 1);
}

void drawMouseStroke(float mx, float my, boolean start) {
  if (!drawModeOn()) return;
  if (previewIw < 2 || previewIh < 2) return;
  // Clamp — rejecting out-of-bounds mid-stroke reset lastX and turned swipes into dots.
  mx = constrain(mx, previewIx, previewIx + previewIw);
  my = constrain(my, previewIy, previewIy + previewIh);
  float x = (mx - previewIx) / previewIw * (capW - 1);
  float y = (my - previewIy) / previewIh * (capH - 1);
  drawNX = constrain((mx - previewIx) / previewIw, 0, 1);
  drawNY = 1f - constrain((my - previewIy) / previewIh, 0, 1);
  // Local gesture owns the stroke — pad END-timeout must not cancel mid-drag.
  luckyPadStrokeLive = false;

  if (drawTool == DRAW_PICK) {
    if (start) drawPickAt(x, y);
    return;
  }
  if (drawTool == DRAW_FILL) {
    if (start) drawFloodFill(x, y);
    return;
  }
  if (drawToolIsShape()) {
    // Recover if a pad timeout cleared drawShapeOn while the mouse is still down.
    if (start || !drawShapeOn) drawShapeBegin(x, y);
    else drawShapeUpdate(x, y);
    return;
  }

  boolean strokeStart = start || !drawTouching || drawLastX < 0;
  if (strokeStart && !drawStrokeUndoArmed) {
    drawPushUndo();
    drawStrokeUndoArmed = true;
  }
  drawTouching = true;
  drawStrokeTo(x, y, strokeStart);
  luckyPadRequestPreview(false);
}

void drawMouseReleased() {
  drawStrokeUndoArmed = false;
  luckyPadStrokeLive = false;
  if (drawShapeOn) {
    drawShapeFinish();
    luckyPadRequestPreview(true);
    return;
  }
  if (!drawTouching) return;
  drawTouching = false;
  drawLastX = -1;
  luckyPadRequestPreview(true);
}

boolean drawHslHit(String id) {
  return id != null && id.equals("hsl-pad");
}

void drawHslBegin(String id, float mx, float my) {
  if (!id.equals("hsl-pad")) return;
  hslDragPad = true;
  drawHslDragPad(mx, my);
}

void drawHslDrag(float mx, float my) {
  if (hslDragPad) drawHslDragPad(mx, my);
}

void drawHslEnd() {
  if (hslDragPad) commitDrawSwatchFromHsl();
  hslDragPad = false;
}

/** Single square: X = hue, Y = lightness (sat full). */
void drawHslDragPad(float mx, float my) {
  if (hslPadW < 2 || hslPadH < 2) return;
  drawHue = constrain((mx - hslPadX) / hslPadW, 0, 1) * 360f;
  drawLight = constrain(1f - (my - hslPadY) / hslPadH, 0, 1);
  drawSat = 1;
  // Live-update active swatch while dragging so the chip matches the pad.
  drawSwatches[constrain(drawColorIdx, 0, drawSwatches.length - 1)] = drawInk() | 0xFF000000;
  markDirty();
}

void ensureHslPadImage(int pw, int ph) {
  if (pw < 2 || ph < 2) return;
  if (hslPadImg != null && hslPadCachedW == pw && hslPadCachedH == ph) return;
  hslPadImg = createImage(pw, ph, RGB);
  hslPadImg.loadPixels();
  for (int y = 0; y < ph; y++) {
    float l = 1f - y / (float) (ph - 1);
    int row = y * pw;
    for (int x = 0; x < pw; x++) {
      float h = x / (float) (pw - 1) * 360f;
      hslPadImg.pixels[row + x] = hslToColor(h, 1, l);
    }
  }
  hslPadImg.updatePixels();
  hslPadCachedW = pw;
  hslPadCachedH = ph;
}

void drawCommit() {
  ensureDrawImg();
  if (!drawDirty) {
    note("Nothing drawn");
    return;
  }
  if (stopCount() >= MAX_STOP_FRAMES) {
    note("Stoptrick full  ·  " + MAX_STOP_FRAMES + " frames");
    return;
  }
  drawImg.loadPixels();
  int[] frame = new int[drawImg.pixels.length];
  arrayCopy(drawImg.pixels, frame);
  stopPushFrame(frame, true); // ink plate — onion must use Normal, not Multiply
  drawClearCanvas(); // also clears stroke undo
  try { tetherPushOnion(); } catch (Throwable t) { println("onion: " + t.getMessage()); }
  luckyPadRequestPreview(true);
  note("Drawn  " + stopCount());
}

void animShoot() {
  requestShoot();
}

float drawBrushNorm() {
  return constrain((drawBrush - DRAW_BRUSH_MIN) / (DRAW_BRUSH_MAX - DRAW_BRUSH_MIN), 0, 1);
}

void setDrawBrushNorm(float u) {
  drawBrush = lerp(DRAW_BRUSH_MIN, DRAW_BRUSH_MAX, constrain(u, 0, 1));
  markDirty();
}

boolean drawCursorWanted() {
  return drawModeOn() && drawCursorExternal
    && drawTool != DRAW_FILL && drawTool != DRAW_PICK;
}

void paintDrawCursor(PGraphics g) {
  if (g == null) return;
  float cx = drawNX * (capW - 1);
  float cy = (1f - drawNY) * (capH - 1);
  float r = max(2f, drawBrushPx() * 0.5f);
  g.blendMode(BLEND);
  g.noFill();
  int ink = drawTool == DRAW_ERASER ? color(160, 160, 168, 255) : drawInk();
  g.stroke(ink);
  g.strokeWeight(drawTouching || drawPadFingerDown ? 2f : 1.5f);
  if (drawRaster) g.rectMode(CORNER);
  if (drawRaster) g.rect(cx - r, cy - r, r * 2, r * 2);
  else g.ellipse(cx, cy, r * 2, r * 2);
  g.noStroke();
}

/**
 * Overlay brush ghost for Syphon / beamer only (preview draws its own).
 *
 * Draw's program out is often stackGfx (pixels uploaded, never GL-drawn).
 * beginDraw() clears that FBO; image(stackGfx) samples empty → black + cursor only.
 * Always blit from a plain CPU PImage (stackImg / copy), then stroke the cursor.
 */
PImage withDrawCursorExternal(PImage src) {
  if (!drawCursorWanted() || src == null) return src;

  // Prefer the CPU compose plate — never trust loadPixels on an upload-only PGraphics.
  PImage cpu = src;
  if (src == stackGfx && stackImg != null) cpu = stackImg;
  cpu.loadPixels();
  int[] sp = cpu.pixels;
  if (sp == null || sp.length < capW * capH) return src;

  if (drawCursorPlate == null || drawCursorPlate.width != capW || drawCursorPlate.height != capH) {
    drawCursorPlate = createImage(capW, capH, ARGB);
  }
  drawCursorPlate.loadPixels();
  arrayCopy(sp, 0, drawCursorPlate.pixels, 0, capW * capH);
  drawCursorPlate.updatePixels();

  drawCursorGfx = ensureFrame(drawCursorGfx);
  drawCursorGfx.beginDraw();
  drawCursorGfx.blendMode(BLEND);
  drawCursorGfx.noTint();
  drawCursorGfx.background(0);
  drawCursorGfx.image(drawCursorPlate, 0, 0, capW, capH);
  paintDrawCursor(drawCursorGfx);
  drawCursorGfx.endDraw();
  return drawCursorGfx;
}

void setDrawCursorExternal(boolean on) {
  if (drawCursorExternal == on) return;
  drawCursorExternal = on;
  markDirty();
  note(on ? "Cursor on external" : "Cursor preview only");
}

void setDrawLiveUnderlay(boolean on) {
  if (drawLiveUnderlay == on) return;
  drawLiveUnderlay = on;
  markDirty();
  note(on ? "Live underlay on" : "Live underlay off");
}

/**
 * Live under ink while drawing.
 * No Hap loop yet → always show naked live (Draw must not open onto black).
 * Over a loop → optional checkbox; FRZ never becomes a fake onion.
 * Frame-stack play is gated in outputIncludesLive (Draw + Live underlay keeps cam).
 */
boolean drawWantsLiveUnderlay() {
  if (!drawModeOn()) return true;
  if (!loopAudible()) return true;
  if (liveFrozen()) return false;
  return drawLiveUnderlay;
}
