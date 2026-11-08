// Live feed framing: pinch zoom, two-finger pan, soft edge feather, reset.

float liveFeather = 0; // 0..100 — soft edge width
boolean framePadOn = false;
boolean framePadFallback = false;
float[] framePadSample = new float[10]; // up to 5 touches × xy
float[] frameScrollSample = new float[2];
int framePadFailLog = 0;

static final float LIVE_ZOOM_MIN = 0.25f;
static final float LIVE_ZOOM_MAX = 3f;

boolean framePinchOn = false;
float framePinchLastDist = 1;
float framePinchLastMidX = 0.5f;
float framePinchLastMidY = 0.5f;
float framePinchLastAng = 0; // radians, two-finger axis

boolean frameDragOn = false;
boolean frameDragMoved = false;
float frameDragX0 = 0;
float frameDragY0 = 0;
float frameDragPanX0 = 0;
float frameDragPanY0 = 0;

/** Re-blit live cover even if the camera hasn't delivered a new frame. */
boolean liveFrameDirty = false;

PImage liveFeatherImg;
int[] liveFeatherPixels;
int liveFeatherFrame = -1;
float liveFeatherCached = -1;

/** Live crop rect in normalized stage space (0..1). Full frame = no crop. */
float liveCropL = 0;
float liveCropT = 0;
float liveCropR = 1;
float liveCropB = 1;
boolean liveCropEdit = false;
int liveCropDrag = -1; // -1 none, 0–3 corners, 4 body, 5–8 edges LTRB
float liveCropGrabX, liveCropGrabY;
float liveCropL0, liveCropT0, liveCropR0, liveCropB0;
PGraphics liveCropGfx;
static final float LIVE_CROP_MIN = 0.08f;

boolean liveCropActive() {
  return liveCropL > 0.001f || liveCropT > 0.001f
    || liveCropR < 0.999f || liveCropB < 0.999f;
}

void normalizeLiveCrop() {
  float l = constrain(min(liveCropL, liveCropR), 0, 1);
  float r = constrain(max(liveCropL, liveCropR), 0, 1);
  float t = constrain(min(liveCropT, liveCropB), 0, 1);
  float b = constrain(max(liveCropT, liveCropB), 0, 1);
  if (r - l < LIVE_CROP_MIN) {
    float m = (l + r) * 0.5f;
    l = constrain(m - LIVE_CROP_MIN * 0.5f, 0, 1 - LIVE_CROP_MIN);
    r = l + LIVE_CROP_MIN;
  }
  if (b - t < LIVE_CROP_MIN) {
    float m = (t + b) * 0.5f;
    t = constrain(m - LIVE_CROP_MIN * 0.5f, 0, 1 - LIVE_CROP_MIN);
    b = t + LIVE_CROP_MIN;
  }
  liveCropL = l;
  liveCropT = t;
  liveCropR = r;
  liveCropB = b;
}

void resetLiveCrop() {
  liveCropL = 0;
  liveCropT = 0;
  liveCropR = 1;
  liveCropB = 1;
  liveCropDrag = -1;
  liveCropEdit = false;
  dirtyLiveFrame();
}

void toggleLiveCropEdit() {
  liveCropEdit = !liveCropEdit;
  liveCropDrag = -1;
  normalizeLiveCrop();
  dirtyLiveFrame(); // re-blit so mask / fill crop shows immediately
  if (liveCropEdit) {
    note("CROP box  ·  drag edges / move  ·  0 resets");
  } else {
    flushSettings(true);
    note(liveCropActive() ? "CROP on" : "CROP off");
  }
}

/** Key 0 / Reset frame — pan center, zoom 100%, twist 0, fill cover, crop off.
 *  Double-tap 0 also kills all FX (see onKey). */
void resetLiveFrame() {
  camZoom = 1;
  camPanX = 0;
  camPanY = 0;
  camTwist = 0;
  liveFeather = 0;
  camScale = SCALE_FILL;
  framePinchOn = false;
  frameDragOn = false;
  liveFeatherFrame = -1;
  resetLiveCrop();
  if (topMode == TOP_STOP) resetStopFrameView();
  dirtyLiveFrame();
  flushSettings(true);
  note(topMode == TOP_STOP ? "STOP FRAME  100%" : "LIVE FRAME  100%");
}

/**
 * Crop region always scales to fill the stage — it becomes the live-feed box.
 * Call after framing blit.
 */
void applyLiveCropBlit() {
  if (!liveCropActive()) return;
  if (scaleGfx == null) return;
  normalizeLiveCrop();
  int sx1 = constrain(round(liveCropL * capW), 0, capW - 1);
  int sy1 = constrain(round(liveCropT * capH), 0, capH - 1);
  int sx2 = constrain(round(liveCropR * capW), sx1 + 1, capW);
  int sy2 = constrain(round(liveCropB * capH), sy1 + 1, capH);
  liveCropGfx = ensureFrame(liveCropGfx);
  liveCropGfx.beginDraw();
  liveCropGfx.background(0);
  liveCropGfx.blendMode(BLEND);
  liveCropGfx.noTint();
  liveCropGfx.imageMode(CORNER);
  liveCropGfx.image(scaleGfx, 0, 0, capW, capH);
  liveCropGfx.endDraw();
  float cw = max(1, sx2 - sx1);
  float ch = max(1, sy2 - sy1);
  // Uniform cover into the live-feed box — crop becomes the new stage frame.
  float s = max(capW / cw, capH / ch);
  float dw = cw * s;
  float dh = ch * s;
  float ox = (capW - dw) * 0.5f;
  float oy = (capH - dh) * 0.5f;
  scaleGfx.beginDraw();
  scaleGfx.background(0);
  scaleGfx.blendMode(BLEND);
  scaleGfx.noTint();
  scaleGfx.imageMode(CORNER);
  scaleGfx.image(liveCropGfx, ox, oy, dw, dh, sx1, sy1, sx2, sy2);
  scaleGfx.endDraw();
}

/**
 * Handles sit on the live preview box (the scaled crop). Dragging an edge
 * insets/outsets the source crop; content reflows to keep filling the box.
 */
int liveCropHit(float mx, float my) {
  if (!liveCropEdit || previewIw < 2 || previewIh < 2) return -1;
  if (!overLivePreview(mx, my)) {
    // Allow grabbing handles slightly outside the box.
    float pad = 12;
    if (mx < previewIx - pad || mx > previewIx + previewIw + pad
      || my < previewIy - pad || my > previewIy + previewIh + pad) return -1;
  }
  float rx = previewIx;
  float ry = previewIy;
  float rw = previewIw;
  float rh = previewIh;
  float hs = 12;
  float[][] c = {
    { rx, ry }, { rx + rw, ry }, { rx + rw, ry + rh }, { rx, ry + rh }
  };
  for (int i = 0; i < 4; i++) {
    if (abs(mx - c[i][0]) <= hs && abs(my - c[i][1]) <= hs) return i;
  }
  if (abs(mx - rx) <= hs && my >= ry - hs && my <= ry + rh + hs) return 5;
  if (abs(my - ry) <= hs && mx >= rx - hs && mx <= rx + rw + hs) return 6;
  if (abs(mx - (rx + rw)) <= hs && my >= ry - hs && my <= ry + rh + hs) return 7;
  if (abs(my - (ry + rh)) <= hs && mx >= rx - hs && mx <= rx + rw + hs) return 8;
  if (mx >= rx && mx <= rx + rw && my >= ry && my <= ry + rh) return 4;
  return -1;
}

boolean beginLiveCropDrag(float mx, float my) {
  if (!liveCropEdit) return false;
  int h = liveCropHit(mx, my);
  if (h < 0) return false;
  liveCropDrag = h;
  liveCropGrabX = mx;
  liveCropGrabY = my;
  liveCropL0 = liveCropL;
  liveCropT0 = liveCropT;
  liveCropR0 = liveCropR;
  liveCropB0 = liveCropB;
  return true;
}

void moveLiveCropDrag(float mx, float my) {
  if (liveCropDrag < 0 || previewIw < 2 || previewIh < 2) return;
  // Drag in preview pixels → delta in source-crop space.
  // Inward drag (toward center) tightens crop; content stays filling the box.
  float dx = (mx - liveCropGrabX) / previewIw;
  float dy = (my - liveCropGrabY) / previewIh;
  float l = liveCropL0, t = liveCropT0, r = liveCropR0, b = liveCropB0;
  float cw = max(LIVE_CROP_MIN, r - l);
  float ch = max(LIVE_CROP_MIN, b - t);
  // Scale drag so edge motion maps to source crop at current zoom of the window.
  float sx = cw; // one preview-width of drag ≈ full current crop width in source
  float sy = ch;
  int h = liveCropDrag;
  if (h == 4) {
    // Pan crop window inside source.
    l = constrain(l - dx * sx, 0, 1 - cw);
    t = constrain(t - dy * sy, 0, 1 - ch);
    r = l + cw;
    b = t + ch;
  } else if (h == 0) { // TL — drag toward center (down-right) tightens
    l = l + dx * sx;
    t = t + dy * sy;
  } else if (h == 1) { // TR
    r = r + dx * sx;
    t = t + dy * sy;
  } else if (h == 2) { // BR
    r = r + dx * sx;
    b = b + dy * sy;
  } else if (h == 3) { // BL
    l = l + dx * sx;
    b = b + dy * sy;
  } else if (h == 5) l = l + dx * sx;
  else if (h == 6) t = t + dy * sy;
  else if (h == 7) r = r + dx * sx;
  else if (h == 8) b = b + dy * sy;
  liveCropL = l;
  liveCropT = t;
  liveCropR = r;
  liveCropB = b;
  normalizeLiveCrop();
  dirtyLiveFrame();
}

void endLiveCropDrag() {
  if (liveCropDrag < 0) return;
  liveCropDrag = -1;
  normalizeLiveCrop();
  dirtyLiveFrame();
  flushSettings(true);
}

/** Crop edit chrome on the live-feed box (preview = scaled crop). */
void drawLiveCropOverlay() {
  if (previewIw < 2 || previewIh < 2) return;
  float rx = previewIx;
  float ry = previewIy;
  float rw = previewIw;
  float rh = previewIh;
  if (!liveCropEdit) {
    if (!liveCropActive()) return;
    // Quiet mark that the feed box is cropped.
    noFill();
    stroke(ACCENT, 120);
    strokeWeight(1);
    rect(rx + 0.5f, ry + 0.5f, rw - 1, rh - 1);
    noStroke();
    return;
  }
  // Active edit: the preview frame IS the crop box.
  noFill();
  stroke(ACCENT);
  strokeWeight(2);
  rect(rx, ry, rw, rh);
  stroke(ACCENT, 80);
  strokeWeight(1);
  line(rx + rw / 3f, ry, rx + rw / 3f, ry + rh);
  line(rx + 2f * rw / 3f, ry, rx + 2f * rw / 3f, ry + rh);
  line(rx, ry + rh / 3f, rx + rw, ry + rh / 3f);
  line(rx, ry + 2f * rh / 3f, rx + rw, ry + 2f * rh / 3f);
  noStroke();
  fill(PAPER);
  stroke(ACCENT);
  strokeWeight(1);
  float hs = 6;
  rect(rx - hs, ry - hs, hs * 2, hs * 2);
  rect(rx + rw - hs, ry - hs, hs * 2, hs * 2);
  rect(rx + rw - hs, ry + rh - hs, hs * 2, hs * 2);
  rect(rx - hs, ry + rh - hs, hs * 2, hs * 2);
  // Edge mid handles.
  rect(rx + rw * 0.5f - hs, ry - hs, hs * 2, hs * 2);
  rect(rx + rw * 0.5f - hs, ry + rh - hs, hs * 2, hs * 2);
  rect(rx - hs, ry + rh * 0.5f - hs, hs * 2, hs * 2);
  rect(rx + rw - hs, ry + rh * 0.5f - hs, hs * 2, hs * 2);
  noStroke();
}

boolean liveFeatherOn() {
  return liveFeather >= 0.5f;
}

float liveFeatherWidth(int w, int h) {
  float amt = constrain(liveFeather, 0, 100) / 100f;
  return amt * 0.42f * min(w, h);
}

void dirtyLiveFrame() {
  liveFrameDirty = true;
  markDirty();
}

void applyLiveZoom(float next) {
  next = constrain(next, LIVE_ZOOM_MIN, LIVE_ZOOM_MAX);
  if (abs(next - camZoom) < 0.0001f) return;
  camZoom = next;
  dirtyLiveFrame();
}

void applyLivePan(float x, float y) {
  // No ±1 box clamp — pinch/drag may push the image past the preview frame.
  if (abs(x - camPanX) < 0.0001f && abs(y - camPanY) < 0.0001f) return;
  camPanX = x;
  camPanY = y;
  dirtyLiveFrame();
}

void applyLiveTwist(float deg) {
  // Keep a tidy range for display / save — continuous rotate wraps.
  float next = deg;
  while (next > 180) next -= 360;
  while (next < -180) next += 360;
  if (abs(next - camTwist) < 0.01f) return;
  camTwist = next;
  dirtyLiveFrame();
}

/** Pinch target: stop stack playback in Stoptrick, otherwise live feed. */
boolean framingTargetsStopStack() {
  return hasStop() && (topMode == TOP_STOP || stopModeOn());
}

void applyPreviewZoom(float next) {
  if (framingTargetsStopStack()) applyStopZoom(next);
  else applyLiveZoom(next);
}

void applyPreviewPan(float x, float y) {
  if (framingTargetsStopStack()) applyStopPan(x, y);
  else applyLivePan(x, y);
}

void applyPreviewTwist(float deg) {
  if (framingTargetsStopStack()) applyStopTwist(deg);
  else applyLiveTwist(deg);
}

float previewZoom() {
  return framingTargetsStopStack() ? stopZoom : camZoom;
}

float previewPanX() {
  return framingTargetsStopStack() ? stopPanX : camPanX;
}

float previewPanY() {
  return framingTargetsStopStack() ? stopPanY : camPanY;
}

float previewTwist() {
  return framingTargetsStopStack() ? stopTwist : camTwist;
}

float liveCoverAngle() {
  return camRotation + camTwist;
}

/** Soft-edge alpha mask into dest (ARGB). Source RGB kept; alpha feathered. */
void bakeLiveFeather(int[] src, int[] dest, int w, int h, float fw) {
  if (src == null || dest == null || src.length != dest.length) return;
  if (fw < 0.5f) {
    int n = src.length;
    for (int i = 0; i < n; i++) dest[i] = src[i] | 0xFF000000;
    return;
  }
  float inv = 1f / fw;
  for (int y = 0; y < h; y++) {
    float dy = min(y + 0.5f, h - 0.5f - y);
    int row = y * w;
    for (int x = 0; x < w; x++) {
      float dx = min(x + 0.5f, w - 0.5f - x);
      float d = min(dx, dy);
      float a = constrain(d * inv, 0, 1);
      a = a * a * (3f - 2f * a);
      int sa = constrain(round(a * 255), 0, 255);
      int c = src[row + x];
      dest[row + x] = (sa << 24) | (c & 0x00FFFFFF);
    }
  }
}

void prepareLiveFeather() {
  if (!liveFeatherOn()) {
    liveFeatherFrame = frameCount;
    liveFeatherCached = liveFeather;
    return;
  }
  if (liveFeatherFrame == frameCount && abs(liveFeatherCached - liveFeather) < 0.01f) return;
  liveFeatherFrame = frameCount;
  liveFeatherCached = liveFeather;

  PImage src = liveCompositeSourceBase();
  if (src == null) return;
  src.loadPixels();
  int n = capW * capH;
  if (src.pixels == null || src.pixels.length < n) return;
  if (liveFeatherPixels == null || liveFeatherPixels.length != n) liveFeatherPixels = new int[n];
  if (liveFeatherImg == null || liveFeatherImg.width != capW || liveFeatherImg.height != capH) {
    liveFeatherImg = createImage(capW, capH, ARGB);
  }
  bakeLiveFeather(src.pixels, liveFeatherPixels, capW, capH, liveFeatherWidth(capW, capH));
  liveFeatherImg.loadPixels();
  arrayCopy(liveFeatherPixels, liveFeatherImg.pixels);
  liveFeatherImg.updatePixels();
}

boolean overLivePreview(float mx, float my) {
  return previewIw > 1 && mx >= previewIx && mx < previewIx + previewIw
    && my >= previewIy && my < previewIy + previewIh;
}

boolean liveFramingAllowed() {
  // Pinch / pan / twist on the live preview in LIVE, STOPTRICK, and FX.
  return (topMode == TOP_LIVE || topMode == TOP_STOP || topMode == TOP_FX)
    && !liveCropEdit && !outputEditOn() && !midiMapMode
    && dragSlider == null && fineId == null && editId == null && curveDrag < 0;
}

void ensureFramePad() {
  PadCtl.load(sketchPath("data/libpadctl.dylib"));
  if (!PadCtl.loaded) {
    if (framePadFailLog < 1) {
      println("Live frame pad: " + (PadCtl.fail.length() > 0 ? PadCtl.fail : "not loaded"));
      framePadFailLog++;
    }
    framePadFallback = true;
    framePadOn = true;
    return;
  }
  int ok = 0;
  try {
    ok = PadCtl.start();
  } catch (Throwable t) {
    ok = 0;
    if (framePadFailLog < 3) {
      println("Live frame pad start: " + t);
      framePadFailLog++;
    }
  }
  if (ok != 1) {
    framePadFallback = true;
    framePadOn = true;
    return;
  }
  framePadFallback = false;
  framePadOn = true;
}

void stopFramePad() {
  if (!framePadOn) return;
  framePadOn = false;
  framePinchOn = false;
  if (!drawPadOn && PadCtl.loaded) {
    try { PadCtl.stop(); } catch (Throwable t) {}
  }
}

void serviceLiveFraming() {
  if (!liveFramingAllowed()) {
    framePinchOn = false;
    return;
  }

  ensureFramePad();
  if (!PadCtl.loaded) return;

  // 1) Native macOS pinch + rotate (NSEvent) — works with P3D/NEWT.
  boolean nativeMag = false;
  boolean nativeRot = false;
  try {
    float mag = PadCtl.pollMagnify();
    if (abs(mag) > 0.00001f) {
      applyPreviewZoom(previewZoom() * (1f + mag * 2.8f));
      framePinchOn = true;
      nativeMag = true;
    }
  } catch (UnsatisfiedLinkError e) {
    if (framePadFailLog < 2) {
      println("PadCtl.pollMagnify missing — rebuild libpadctl / restart sketch");
      framePadFailLog++;
    }
  } catch (Throwable t) {}
  try {
    float rot = PadCtl.pollRotate();
    if (abs(rot) > 0.0001f) {
      // NSEvent: clockwise positive. With view-space mirror, CW already matches screen.
      applyPreviewTwist(previewTwist() + (mirror ? rot : -rot));
      framePinchOn = true;
      nativeRot = true;
    }
  } catch (UnsatisfiedLinkError e) {
    if (framePadFailLog < 2) {
      println("PadCtl.pollRotate missing — rebuild libpadctl / restart sketch");
      framePadFailLog++;
    }
  } catch (Throwable t) {}

  // 1b) Native two-finger pan via precise trackpad scroll (same path as pinch/rotate).
  boolean overPreview = overLivePreview(mouseX, mouseY);
  try {
    int got = PadCtl.pollScroll(frameScrollSample);
    if (got == 1) {
      float sdx = frameScrollSample[0];
      float sdy = frameScrollSample[1];
      // Only pan over the live preview (or mid-gesture) — don't steal inspector scroll.
      if (overPreview || framePinchOn) {
        float s = 2.4f / max(160f, min(previewIw, previewIh));
        // Natural scroll: fingers right → negative dx; image follows fingers.
        applyPreviewPan(previewPanX() - sdx * s, previewPanY() + sdy * s);
        framePinchOn = true;
      }
    }
  } catch (UnsatisfiedLinkError e) {
    if (framePadFailLog < 2) {
      println("PadCtl.pollScroll missing — rebuild libpadctl / restart sketch");
      framePadFailLog++;
    }
  } catch (Throwable t) {}

  if (framePadFallback) return;
  // Absolute two-finger contacts: backup pinch/rotate + mid-point pan.
  if (!overPreview && !framePinchOn) return;

  // 2) Two-finger absolute contacts → pan (+ pinch/rotate backup if NSEvent silent).
  int n = 0;
  try {
    n = PadCtl.pollAll(framePadSample);
  } catch (UnsatisfiedLinkError e) {
    if (framePadFailLog < 3) {
      println("PadCtl.pollAll missing — rebuild libpadctl / restart sketch");
      framePadFailLog++;
    }
    framePadFallback = true;
    return;
  } catch (Throwable t) {
    return;
  }

  if (n < 2) {
    if (framePinchOn && !mousePressed) framePinchOn = false;
    return;
  }

  float x0 = framePadSample[0];
  float y0 = framePadSample[1];
  float x1 = framePadSample[2];
  float y1 = framePadSample[3];
  float mx = (x0 + x1) * 0.5f;
  float my = (y0 + y1) * 0.5f;
  float dist = max(0.012f, sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)));
  float ang = atan2(y1 - y0, x1 - x0);

  if (!framePinchOn) {
    framePinchOn = true;
    framePinchLastDist = dist;
    framePinchLastMidX = mx;
    framePinchLastMidY = my;
    framePinchLastAng = ang;
    return;
  }

  float dmx = mx - framePinchLastMidX;
  float dmy = my - framePinchLastMidY;
  float midMove = sqrt(dmx * dmx + dmy * dmy);
  float distDelta = abs(dist - framePinchLastDist);

  // Pinch zoom only when distance change dominates mid-point travel (not scroll/pan).
  if (!nativeMag) {
    float ratio = dist / max(0.012f, framePinchLastDist);
    if (abs(ratio - 1f) > 0.012f && distDelta > midMove * 0.85f) {
      applyPreviewZoom(previewZoom() * pow(ratio, 1.25f));
    }
  }
  if (!nativeRot) {
    float dAng = ang - framePinchLastAng;
    if (dAng > PI) dAng -= TWO_PI;
    if (dAng < -PI) dAng += TWO_PI;
    // Ignore tiny angle jitter while mostly panning/scrolling.
    if (abs(dAng) > 0.003f && abs(dAng) * dist > midMove * 0.55f) {
      float deg = degrees(dAng);
      applyPreviewTwist(previewTwist() + (mirror ? deg : -deg));
    }
  }
  // Pad Y is bottom-left; flip so finger-up moves the image up (matches scroll pan).
  applyPreviewPan(previewPanX() + dmx * 2.8f, previewPanY() - dmy * 2.8f);

  framePinchLastDist = dist;
  framePinchLastMidX = mx;
  framePinchLastMidY = my;
  framePinchLastAng = ang;
}

boolean beginFrameDrag(float mx, float my) {
  if (!liveFramingAllowed() || !overLivePreview(mx, my)) return false;
  if (framePinchOn) return false;
  frameDragOn = true;
  frameDragMoved = false;
  frameDragX0 = mx;
  frameDragY0 = my;
  frameDragPanX0 = previewPanX();
  frameDragPanY0 = previewPanY();
  return true;
}

void moveFrameDrag(float mx, float my) {
  if (!frameDragOn || previewIw < 2 || previewIh < 2) return;
  float dx = (mx - frameDragX0) / previewIw;
  float dy = (my - frameDragY0) / previewIh;
  if (abs(dx) + abs(dy) > 0.012f) frameDragMoved = true;
  if (!frameDragMoved) return; // still a tap — don't nudge pan yet
  // Mouse Y is top-down: same sign as pan so the image follows the pointer.
  applyPreviewPan(frameDragPanX0 + dx * 2f, frameDragPanY0 + dy * 2f);
}

void endFrameDrag() {
  if (!frameDragOn) return;
  boolean wasTap = !frameDragMoved;
  float tapX = frameDragX0;
  float tapY = frameDragY0;
  frameDragOn = false;
  frameDragMoved = false;
  if (wasTap) {
    // Click without drag → focus assist (tether) when enabled.
    tetherTapAtStage(tapX, tapY);
  } else {
    flushSettings(true);
  }
}

void zoomLiveFrame(float wheelCount) {
  // Kept for MIDI / explicit callers — trackpad scroll does not zoom (pinch only).
  if (!liveFramingAllowed()) return;
  applyPreviewZoom(previewZoom() - wheelCount * 0.08f);
}

void panLiveFrameWheel(float dx, float dy) {
  if (!liveFramingAllowed()) return;
  applyPreviewPan(previewPanX() + dx, previewPanY() + dy);
}
