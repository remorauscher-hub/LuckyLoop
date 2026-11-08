// LuckyPad — iPad ink surface over Bonjour/USB. Separate from LuckyTether (camera).

PadClient luckyPad;
boolean luckyPadSynced = false;
float[] luckyPadSample = new float[3];
boolean luckyPadEncodeWanted = false;
boolean luckyPadEncodeBusy = false;
int luckyPadPreviewAt = 0;
PImage luckyPadPreviewBuf;
int[] luckyPadSnapPx;
int luckyPadSnapW, luckyPadSnapH;
final Object luckyPadSnapLock = new Object();

void ensureLuckyPad() {
  if (luckyPad == null) luckyPad = new PadClient();
}

void startLuckyPad() {
  ensureLuckyPad();
  if (!luckyPad.running) luckyPad.start();
}

void stopLuckyPad() {
  if (luckyPad != null) luckyPad.stop();
  luckyPadSynced = false;
  luckyPadEncodeWanted = false;
}

boolean luckyPadLive() {
  return luckyPad != null && luckyPad.running && luckyPad.connected;
}

/** Enter / leave Draw — keep browsing; sync brush when Draw is active. */
void luckyPadOnDraw(boolean on) {
  startLuckyPad();
  luckyPadSynced = false;
  if (!on) {
    luckyPadEncodeWanted = false;
    if (luckyPadLive()) luckyPad.sendControl("{\"c\":\"armed\",\"v\":0}");
    return;
  }
  if (luckyPadLive()) luckyPadSyncAll();
}

String luckyPadNum(float v, int decimals) {
  return String.format(java.util.Locale.US, "%." + decimals + "f", v);
}

void luckyPadSyncBrush() {
  if (!drawModeOn() || !luckyPadLive()) return;
  luckyPad.sendControl("{\"c\":\"brush\",\"v\":" + luckyPadNum(drawBrush, 1) + "}");
}

void luckyPadSyncColor() {
  if (!drawModeOn() || !luckyPadLive()) return;
  int c = drawInk() & 0xFFFFFF;
  int r = (c >> 16) & 255;
  int g = (c >> 8) & 255;
  int b = c & 255;
  luckyPad.sendControl("{\"c\":\"inkrgb\",\"r\":" + r + ",\"g\":" + g + ",\"b\":" + b
    + ",\"i\":" + constrain(drawColorIdx, 0, drawSwatches.length - 1) + "}");
}

void luckyPadSyncColorIdx() {
  if (!luckyPadLive()) return;
  luckyPad.sendControl("{\"c\":\"coloridx\",\"v\":" + constrain(drawColorIdx, 0, drawSwatches.length - 1) + "}");
}

void luckyPadSyncSwatch(int idx) {
  if (!luckyPadLive()) return;
  idx = constrain(idx, 0, drawSwatches.length - 1);
  int c = drawSwatches[idx] & 0xFFFFFF;
  int r = (c >> 16) & 255;
  int g = (c >> 8) & 255;
  int b = c & 255;
  luckyPad.sendControl("{\"c\":\"swatch\",\"i\":" + idx + ",\"r\":" + r + ",\"g\":" + g + ",\"b\":" + b + "}");
}

void luckyPadSyncSwatches() {
  if (!luckyPadLive()) return;
  for (int i = 0; i < drawSwatches.length; i++) luckyPadSyncSwatch(i);
  luckyPadSyncColorIdx();
}

void luckyPadSyncStyle() {
  if (!drawModeOn() || !luckyPadLive()) return;
  // Floats so Swift JSONSerialization always yields Double (Int casts used to drop tool/raster).
  luckyPad.sendControl("{\"c\":\"style\",\"raster\":" + (drawRaster ? "1.0" : "0.0")
    + ",\"tool\":" + luckyPadNum(drawTool, 1)
    + ",\"brush\":" + luckyPadNum(drawBrush, 1) + "}");
}

void luckyPadSyncOnion() {
  if (!luckyPadLive()) return;
  luckyPad.sendControl("{\"c\":\"onion\",\"v\":" + (stopOnion ? 1 : 0) + "}");
}

void luckyPadSyncPlay() {
  if (!luckyPadLive()) return;
  boolean baking = (mode == MODE_REC && recFromStop) || (recWait && stopIsRecordSource());
  luckyPad.sendControl("{\"c\":\"play\",\"v\":" + (stopPlaying ? 1 : 0)
    + ",\"bake\":" + (baking ? 1 : 0)
    + ",\"frames\":" + stopCount() + "}");
}

void luckyPadSyncCanvas() {
  if (!luckyPadLive()) return;
  luckyPad.sendControl("{\"c\":\"canvas\",\"w\":" + capW + ",\"h\":" + capH + "}");
}

void luckyPadSyncAll() {
  if (!luckyPadLive()) return;
  luckyPad.clearInk();
  luckyPadSyncCanvas();
  luckyPadSyncBrush();
  luckyPadSyncSwatches();
  luckyPadSyncColor();
  luckyPadSyncStyle();
  luckyPadSyncOnion();
  luckyPadSyncPlay();
  luckyPad.sendControl("{\"c\":\"armed\",\"v\":1}");
  luckyPadSynced = true;
  luckyPadRequestPreview(true);
  note("LuckyPad linked");
}

/**
 * Snapshot the draw preview on the animation thread, encode JPEG off-thread.
 * Low-res / low-quality plate only — keeps Mac live view smooth.
 * force=true bypasses the rate limit (stroke end / undo / link).
 */
void luckyPadRequestPreview(boolean force) {
  if (!luckyPadLive() || !drawModeOn()) return;
  int now = millis();
  // ~8–12 fps max — pad underlay, not a second live cam.
  int gap = drawTouching ? 120 : (stopPlaying ? 90 : 180);
  if (!force && now - luckyPadPreviewAt < gap) return;
  luckyPadPreviewAt = now;

  boolean loopOn = loopAudible() && syncLoopImage();
  // Match Mac Draw: keep Hap loop and/or live under frame-stack play.
  boolean liveOn = liveOpacity > 0.001 && liveShowing() && outputIncludesLive();
  if (!loopOn && liveShowing() && liveOpacity > 0.001) {
    // Naked live when no loop — also under Draw Play (ink plates are sparse).
    if (!(stopPlaying && hasStop()) || (drawModeOn() && drawLiveUnderlay && !liveFrozen())) {
      liveOn = true;
    }
  }
  // Always refresh stop head — needed for Play stepping on the iPad.
  if (hasStop()) syncStopImage();
  // Pad onion / play: keep ghost readable even if the live fader is low.
  int onionA = stopOverlayAlpha(false);
  if (stopOnion && hasStop() && !stopPlaying && stopHold < 0) {
    int base = constrain(round(stopOnionAmt * 255), 0, 255);
    if (base > onionA) onionA = base;
  }
  luckyPadPreviewBuf = composeDrawProgramCPU(luckyPadPreviewBuf,
    loopOn ? loopImg : null, liveOn, onionA);
  if (luckyPadPreviewBuf == null) return;
  luckyPadPreviewBuf.loadPixels();
  int srcW = luckyPadPreviewBuf.width;
  int srcH = luckyPadPreviewBuf.height;
  if (srcW < 4 || srcH < 4 || luckyPadPreviewBuf.pixels == null) return;
  // Half-res underlay (~960×540) — plenty for ink registration, cheap to encode.
  int dw = max(2, srcW / 2);
  int dh = max(2, srcH / 2);
  int[] small = luckyPadDownsample(luckyPadPreviewBuf.pixels, srcW, srcH, dw, dh);
  synchronized (luckyPadSnapLock) {
    luckyPadSnapPx = small;
    luckyPadSnapW = dw;
    luckyPadSnapH = dh;
    luckyPadEncodeWanted = true;
  }
  if (!luckyPadEncodeBusy) thread("luckyPadEncodeWorker");
}

/** Nearest-neighbor downsample for pad JPEG (draw-thread only). */
int[] luckyPadDownsample(int[] src, int sw, int sh, int dw, int dh) {
  int[] out = new int[dw * dh];
  for (int y = 0; y < dh; y++) {
    int sy = (y * sh) / dh;
    int srcRow = sy * sw;
    int dstRow = y * dw;
    for (int x = 0; x < dw; x++) {
      out[dstRow + x] = src[srcRow + (x * sw) / dw];
    }
  }
  return out;
}

/** JPEG encode + send — never touch PImage / GL here. */
void luckyPadEncodeWorker() {
  if (luckyPadEncodeBusy) return;
  luckyPadEncodeBusy = true;
  try {
    while (true) {
      int[] px;
      int w, h;
      synchronized (luckyPadSnapLock) {
        if (!luckyPadEncodeWanted || luckyPadSnapPx == null) break;
        luckyPadEncodeWanted = false;
        w = luckyPadSnapW;
        h = luckyPadSnapH;
        px = luckyPadSnapPx;
        luckyPadSnapPx = null; // ownership to worker — no second full copy
      }
      if (w < 2 || h < 2 || px == null) break;
      try {
        byte[] jpeg = PadClient.encodeJpeg(px, w, h, drawTouching ? 0.35f : 0.4f);
        if (jpeg != null && luckyPadLive()) luckyPad.sendPreviewJpeg(jpeg);
      } catch (Throwable t) {
        println("LuckyPad jpeg: " + t.getMessage());
      }
      synchronized (luckyPadSnapLock) {
        if (!luckyPadEncodeWanted) break;
      }
    }
  } finally {
    luckyPadEncodeBusy = false;
    synchronized (luckyPadSnapLock) {
      if (luckyPadEncodeWanted && luckyPadLive() && drawModeOn()) {
        thread("luckyPadEncodeWorker");
      }
    }
  }
}

void serviceLuckyPadActions() {
  if (luckyPad == null || !luckyPad.connected) return;
  int a;
  while ((a = luckyPad.pollAction()) != 0) {
    if (a == PadClient.ACT_SHOOT) {
      if (drawModeOn()) animShoot();
      else if (stopModeOn()) stopCapture();
    } else if (a == PadClient.ACT_UNDO) {
      if (drawModeOn()) drawOrStopUndo();
      else if (stopModeOn()) stopPopLast();
      luckyPadRequestPreview(true);
    } else if (a == PadClient.ACT_PLAY) {
      stopTogglePlay();
      luckyPadSyncPlay();
      luckyPadRequestPreview(true);
    } else if (a == PadClient.ACT_BAKE) {
      if (drawModeOn() || stopModeOn()) {
        stopClearThisBake = stopClearOnBake;
        bakeStoptrick();
      }
      luckyPadSyncPlay();
      luckyPadRequestPreview(true);
    } else if (a == PadClient.ACT_COLOR) {
      int rgb = luckyPad.padColorRgb;
      if (rgb >= 0) {
        int idx = luckyPad.padColorIdx;
        if (idx >= 0 && idx < drawSwatches.length) {
          drawColorIdx = idx;
          drawSwatches[idx] = 0xFF000000 | (rgb & 0xFFFFFF);
          setDrawColorFromRgb(drawSwatches[idx]);
          drawHslOpen = false;
          // Echo chip + persist so desktop Draw / settings stay in sync.
          luckyPadSyncSwatch(idx);
          luckyPadSyncColorIdx();
          markDirty();
          flushSettings(false); // throttled ≤2/s while ColorPicker drags
        } else {
          selectDrawSwatchClosest(rgb);
          setDrawColorFromRgb(0xFF000000 | rgb);
          markDirty();
        }
      }
    } else if (a == PadClient.ACT_CLEAR) {
      // Pad has one Clear: wipe live ink, or committed stop frames if the plate is empty
      // (after Shoot the plate is already clear and onion still shows — that looked broken).
      if (drawModeOn()) {
        if (drawHasInk()) {
          drawClearFrame();
        } else if (hasStop()) {
          stopClear();
        } else {
          drawClearFrame();
        }
      } else if (stopModeOn() && hasStop()) {
        stopClear();
      }
      luckyPadRequestPreview(true);
    } else if (a == PadClient.ACT_ONION) {
      int want = luckyPad.padOnionWant;
      if (want < 0) setStopOnion(!stopOnion);
      else setStopOnion(want != 0);
    } else if (a == PadClient.ACT_TOOL) {
      int t = luckyPad.padToolWant;
      if (t >= DRAW_PENCIL && t <= DRAW_ROUNDRECT) setDrawTool(t);
    } else if (a == PadClient.ACT_BRUSH) {
      float b = luckyPad.padBrushWant;
      if (b >= 1) {
        drawBrush = constrain(b, DRAW_BRUSH_MIN, DRAW_BRUSH_MAX);
        luckyPadSyncBrush();
        markDirty();
      }
    }
  }
}

/** True while an iPad stroke/shape is in progress (not Mac mouse/trackpad). */
boolean luckyPadStrokeLive = false;

/** Pull iPad ink into the draw canvas; keep preview streaming to the pad. */
boolean serviceLuckyPadInk() {
  serviceLuckyPadActions();
  if (!drawModeOn() || luckyPad == null) return false;

  if (luckyPad.connected && !luckyPadSynced) {
    luckyPadSyncAll();
  }
  if (!luckyPad.connected) {
    luckyPadSynced = false;
    luckyPadStrokeLive = false;
    return false;
  }

  boolean any = false;
  while (luckyPad.pollInk(luckyPadSample)) {
    float x = luckyPadSample[0] * (capW - 1);
    float y = luckyPadSample[1] * (capH - 1);
    int ph = round(luckyPadSample[2]);
    drawNX = luckyPadSample[0];
    drawNY = 1f - luckyPadSample[1];
    drawInkSeenAt = millis();
    luckyPadApplyInk(x, y, ph);
    any = true;
  }

  // Dropped END over the wire — finish pad-owned shape / stroke only.
  // Never touch Mac mouse/trackpad gestures (was killing rect/ellipse mid-drag).
  if (luckyPadStrokeLive && (drawTouching || drawShapeOn)
      && !mousePressed && !drawPadFingerDown
      && millis() - drawInkSeenAt > 450) {
    if (drawShapeOn) {
      drawShapeFinish();
      luckyPadRequestPreview(true);
    }
    drawTouching = false;
    drawLastX = -1;
    drawStrokeUndoArmed = false;
    luckyPadStrokeLive = false;
  }

  luckyPadRequestPreview(false);
  if (stopPlaying || (mode == MODE_REC && recFromStop) || recWait) {
    if (frameCount % 15 == 0) luckyPadSyncPlay();
  }
  return any;
}

/**
 * Apply one iPad sample with the active Mac draw tool (pencil/brush/shapes/fill/…).
 * Previously everything went through drawStrokeTo → rect always looked like a pencil.
 */
void luckyPadApplyInk(float x, float y, int ph) {
  boolean begin = ph == PadClient.INK_BEGIN;
  boolean end = ph == PadClient.INK_END;
  boolean move = !begin && !end;

  if (drawTool == DRAW_PICK) {
    if (begin || (move && !luckyPadStrokeLive)) drawPickAt(x, y);
    if (begin || move) luckyPadStrokeLive = true;
    if (end) luckyPadStrokeLive = false;
    return;
  }
  if (drawTool == DRAW_FILL) {
    if (begin || (move && !luckyPadStrokeLive)) drawFloodFill(x, y);
    if (begin || move) luckyPadStrokeLive = true;
    if (end) luckyPadStrokeLive = false;
    return;
  }
  if (drawToolIsShape()) {
    // BEGIN can arrive late (or be dropped) — first MOVE must still start the shape.
    if (begin || (!drawShapeOn && (move || end))) {
      drawShapeBegin(x, y);
      luckyPadStrokeLive = true;
    }
    if (drawShapeOn && (move || end)) {
      drawShapeUpdate(x, y);
    }
    if (end && drawShapeOn) {
      drawShapeFinish();
      drawTouching = false;
      drawLastX = -1;
      drawStrokeUndoArmed = false;
      luckyPadStrokeLive = false;
      luckyPadRequestPreview(true);
    }
    return;
  }

  // Freehand: pencil / brush / eraser / spray
  ensureDrawImg();
  drawImg.loadPixels();
  if (begin) {
    if (!drawStrokeUndoArmed) {
      drawPushUndo();
      drawStrokeUndoArmed = true;
    }
    drawTouching = true;
    luckyPadStrokeLive = true;
    drawStrokeTo(x, y, true, false);
  } else if (end) {
    if (drawTouching || drawLastX >= 0) drawStrokeTo(x, y, false, false);
    drawTouching = false;
    drawLastX = -1;
    drawStrokeUndoArmed = false;
    luckyPadStrokeLive = false;
  } else {
    boolean start = drawLastX < 0;
    if (start && !drawStrokeUndoArmed) {
      drawPushUndo();
      drawStrokeUndoArmed = true;
    }
    drawTouching = true;
    luckyPadStrokeLive = true;
    drawStrokeTo(x, y, start, false);
  }
  drawImg.updatePixels();
}
