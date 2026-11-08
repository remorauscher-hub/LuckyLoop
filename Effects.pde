int[] rawPixels;
int[] feedbackBuf;
int[] gradeTmp;

float camZoom = 1;
float camPanX = 0; // view-space pan; ±1 ≈ frame edge, beyond pushes past the preview box
float camPanY = 0;
int camScale = SCALE_FILL;
int camRotation = 0; // discrete 0/90/180/270 from UI
float camTwist = 0;  // continuous two-finger rotate (degrees), Live framing only
float camExposure = 0;
float camBrilliance = 0;
float camHighlights = 0;
float camShadows = 0;
float camContrast = 0;
float camBrightness = 0;
float camBlack = 0;
float camSaturation = 0;
float camVibrance = 0;
float camWarmth = 0;
float camTint = 0;
float camSharp = 0;
float camClarity = 0;
float camNoise = 0;
float camVignette = 0;

float fxFeedback = 0;
float fxHue = 0;
int fxPosterize = 0;
float fxThreshold = 0;
int fxPixel = 1;
boolean fxInvert = false;

int[] blurH;
int[] blurFine;
int[] blurWide;

void copyRaw(int[] src, int n) {
  if (rawPixels == null || rawPixels.length != n) rawPixels = new int[n];
  for (int i = 0; i < n; i++) rawPixels[i] = src[i] | 0xFF000000;
  if (livePixels != null && livePixels.length == n) arrayCopy(rawPixels, livePixels);
  liveValid = true;
}

void applyGrade() {
  if (!liveValid || sourceGfx == null) {
    gpuGradeActive = false;
    return;
  }
  if (applyGradeGpu()) return;
  pullSourceCpu();
  applyGradeCpu();
}

void pullSourceCpu() {
  if (sourceGfx == null || livePixels == null) return;
  sourceGfx.loadPixels();
  int n = min(livePixels.length, sourceGfx.pixels.length);
  if (n > 0) copyRaw(sourceGfx.pixels, n);
}

void applyGradeCpu() {
  if (!liveValid || rawPixels == null || livePixels == null) return;
  if (rawPixels.length != livePixels.length) return;
  arrayCopy(rawPixels, livePixels);
  if (toneOn()) gradeTone();
  ensureCurveLuts();
  sampleCurveHist();
  if (curvesOn()) applyCurves();
  if (spatialOn()) gradeSpatial();
  if (finishOn()) gradeFinish();
  // Stylistic FX live in FxStack (Live / Loop / Output), not in camera grade.
}

boolean toneOn() {
  return abs(camExposure) > 0.004 || abs(camBrilliance) > 0.004
    || abs(camHighlights) > 0.004 || abs(camShadows) > 0.004
    || abs(camContrast) > 0.004 || abs(camBrightness) > 0.004 || abs(camBlack) > 0.004
    || abs(camSaturation) > 0.004 || abs(camVibrance) > 0.004
    || abs(camWarmth) > 0.004 || abs(camTint) > 0.004;
}

boolean spatialOn() {
  return camSharp > 0.004 || abs(camClarity) > 0.004 || camNoise > 0.004;
}

boolean finishOn() {
  return abs(camVignette) > 0.004;
}

void gradeTone() {
  int n = livePixels.length;
  float exposure = pow(2, camExposure * 1.5f);
  float ct = 1 + (camContrast >= 0 ? camContrast : camContrast * 0.6f);
  float bright = camBrightness * 90;
  float satM = 1 + camSaturation;
  for (int i = 0; i < n; i++) {
    int c = livePixels[i];
    float r = ((c >> 16) & 255) * exposure;
    float g = ((c >> 8) & 255) * exposure;
    float b = (c & 255) * exposure;
    float lum = r * 0.299f + g * 0.587f + b * 0.114f;
    if (abs(camBrilliance) > 0.004) {
      float nrm = constrain(lum / 255f, 0, 1);
      float lift = camBrilliance * (1 - nrm) * 0.2f;
      float shaped = nrm + lift + camBrilliance * nrm * (1 - nrm) * 0.5f;
      shaped = constrain(shaped, 0, 1.4f);
      if (nrm > 0.004f) {
        float scale = constrain(shaped / nrm, 0, 4);
        r *= scale;
        g *= scale;
        b *= scale;
      } else if (shaped > 0) {
        r = g = b = shaped * 255f;
      }
      lum = r * 0.299f + g * 0.587f + b * 0.114f;
      float mx = max(r, max(g, b));
      float mn = min(r, min(g, b));
      float s = mx > 1 ? constrain((mx - mn) / mx, 0, 1) : 0;
      float vib = camBrilliance * 0.35f * (1 - s);
      r = lum + (r - lum) * (1 + vib);
      g = lum + (g - lum) * (1 + vib);
      b = lum + (b - lum) * (1 + vib);
      lum = r * 0.299f + g * 0.587f + b * 0.114f;
    }
    if (abs(camHighlights) > 0.004) {
      float w = constrain((lum - 148f) / 107f, 0, 1);
      float m = 1 + camHighlights * w * w * 0.95f;
      r *= m;
      g *= m;
      b *= m;
      lum *= m;
    }
    if (abs(camShadows) > 0.004) {
      float w = constrain((128f - lum) / 128f, 0, 1);
      float add = camShadows * w * w * 110f;
      r += add;
      g += add;
      b += add;
      lum += add;
    }
    r = (r - 128) * ct + 128 + bright;
    g = (g - 128) * ct + 128 + bright;
    b = (b - 128) * ct + 128 + bright;
    if (abs(camBlack) > 0.004) {
      if (camBlack > 0) {
        float floor = camBlack * 48;
        float gain = 255f / (255f - floor);
        r = (r - floor) * gain;
        g = (g - floor) * gain;
        b = (b - floor) * gain;
      } else {
        float lift = -camBlack * 56;
        float keep = (255f - lift) / 255f;
        r = r * keep + lift;
        g = g * keep + lift;
        b = b * keep + lift;
      }
    }
    lum = r * 0.299f + g * 0.587f + b * 0.114f;
    r = lum + (r - lum) * satM;
    g = lum + (g - lum) * satM;
    b = lum + (b - lum) * satM;
    if (abs(camVibrance) > 0.004) {
      float mx = max(r, max(g, b));
      float mn = min(r, min(g, b));
      float s = mx > 1 ? constrain((mx - mn) / mx, 0, 1) : 0;
      float vib = camVibrance * (1 - s);
      lum = r * 0.299f + g * 0.587f + b * 0.114f;
      r = lum + (r - lum) * (1 + vib);
      g = lum + (g - lum) * (1 + vib);
      b = lum + (b - lum) * (1 + vib);
    }
    if (abs(camWarmth) > 0.004) {
      r += camWarmth * 32;
      g += camWarmth * 8;
      b -= camWarmth * 36;
    }
    if (abs(camTint) > 0.004) {
      r += camTint * 16;
      g -= camTint * 28;
      b += camTint * 16;
    }
    livePixels[i] = packRgb(r, g, b);
  }
}

void gradeSpatial() {
  int n = livePixels.length;
  int w = capW;
  int h = capH;
  boolean fine = camSharp > 0.004 || camNoise > 0.004;
  boolean wide = abs(camClarity) > 0.004;
  if (fine) {
    if (blurFine == null || blurFine.length != n) blurFine = new int[n];
    blurBox(livePixels, blurFine, w, h, 1);
  }
  if (wide) {
    if (blurWide == null || blurWide.length != n) blurWide = new int[n];
    blurBox(livePixels, blurWide, w, h, 8);
  }
  float sharp = camSharp * 1.55f;
  float nr = constrain(camNoise, 0, 1);
  float clar = camClarity * 1.1f;
  for (int i = 0; i < n; i++) {
    int c = livePixels[i];
    float r = (c >> 16) & 255;
    float g = (c >> 8) & 255;
    float b = c & 255;
    if (fine) {
      int f = blurFine[i];
      float fr = (f >> 16) & 255;
      float fg = (f >> 8) & 255;
      float fb = f & 255;
      r += (fr - r) * nr + (r - fr) * sharp;
      g += (fg - g) * nr + (g - fg) * sharp;
      b += (fb - b) * nr + (b - fb) * sharp;
    }
    if (wide) {
      int f = blurWide[i];
      float fr = (f >> 16) & 255;
      float fg = (f >> 8) & 255;
      float fb = f & 255;
      float lum = r * 0.299f + g * 0.587f + b * 0.114f;
      float mid = 1 - constrain(abs(lum / 255f - 0.5f) * 2f, 0, 1);
      float k = clar * (0.4f + 0.6f * mid);
      r += (r - fr) * k;
      g += (g - fg) * k;
      b += (b - fb) * k;
    }
    livePixels[i] = packRgb(r, g, b);
  }
}

void gradeFinish() {
  // Camera vignette only — Hue / Post / Thr / Pix / Invert / Feedback live in FxStack.
  if (abs(camVignette) <= 0.004) return;
  int n = livePixels.length;
  int w = capW;
  int h = capH;
  float cx = (w - 1) * 0.5f;
  float cy = (h - 1) * 0.5f;
  float invCx = cx > 1 ? 1f / cx : 1;
  float invCy = cy > 1 ? 1f / cy : 1;
  for (int i = 0; i < n; i++) {
    int c = livePixels[i];
    float r = (c >> 16) & 255;
    float g = (c >> 8) & 255;
    float b = c & 255;
    int x = i % w;
    int y = i / w;
    float dx = (x - cx) * invCx;
    float dy = (y - cy) * invCy;
    float d = sqrt(dx * dx + dy * dy);
    float edge = constrain((d - 0.42f) / 0.7f, 0, 1);
    edge = edge * edge;
    if (camVignette >= 0) {
      float m = 1 - edge * camVignette;
      r *= m;
      g *= m;
      b *= m;
    } else {
      float a = edge * -camVignette;
      r = r * (1 - a) + 255 * a;
      g = g * (1 - a) + 255 * a;
      b = b * (1 - a) + 255 * a;
    }
    livePixels[i] = packRgb(r, g, b);
  }
}

int packRgb(float r, float g, float b) {
  int ir = r <= 0 ? 0 : r >= 255 ? 255 : (int) (r + 0.5f);
  int ig = g <= 0 ? 0 : g >= 255 ? 255 : (int) (g + 0.5f);
  int ib = b <= 0 ? 0 : b >= 255 ? 255 : (int) (b + 0.5f);
  return 0xFF000000 | (ir << 16) | (ig << 8) | ib;
}

void blurBox(int[] src, int[] dst, int w, int h, int rad) {
  blurBoxAxes(src, dst, w, h, rad, rad);
}

void blurBoxAxes(int[] src, int[] dst, int w, int h, int radH, int radV) {
  int n = w * h;
  if (blurH == null || blurH.length != n) blurH = new int[n];
  if (radH <= 0) {
    arrayCopy(src, blurH);
  } else {
    int span = radH * 2 + 1;
    float inv = 1f / span;
    for (int y = 0; y < h; y++) {
      int row = y * w;
      int sr = 0, sg = 0, sb = 0;
      for (int k = -radH; k <= radH; k++) {
        int c = src[row + constrain(k, 0, w - 1)];
        sr += (c >> 16) & 255;
        sg += (c >> 8) & 255;
        sb += c & 255;
      }
      for (int x = 0; x < w; x++) {
        blurH[row + x] = 0xFF000000 | ((int) (sr * inv) << 16) | ((int) (sg * inv) << 8) | (int) (sb * inv);
        int c0 = src[row + constrain(x - radH, 0, w - 1)];
        int c1 = src[row + constrain(x + radH + 1, 0, w - 1)];
        sr += ((c1 >> 16) & 255) - ((c0 >> 16) & 255);
        sg += ((c1 >> 8) & 255) - ((c0 >> 8) & 255);
        sb += (c1 & 255) - (c0 & 255);
      }
    }
  }
  if (radV <= 0) {
    arrayCopy(blurH, dst);
    return;
  }
  int span = radV * 2 + 1;
  float inv = 1f / span;
  int rad = radV;
  for (int x = 0; x < w; x++) {
    int sr = 0;
    int sg = 0;
    int sb = 0;
    for (int k = -rad; k <= rad; k++) {
      int c = blurH[constrain(k, 0, h - 1) * w + x];
      sr += (c >> 16) & 255;
      sg += (c >> 8) & 255;
      sb += c & 255;
    }
    for (int y = 0; y < h; y++) {
      dst[y * w + x] = 0xFF000000 | ((int) (sr * inv) << 16) | ((int) (sg * inv) << 8) | (int) (sb * inv);
      int c0 = blurH[constrain(y - rad, 0, h - 1) * w + x];
      int c1 = blurH[constrain(y + rad + 1, 0, h - 1) * w + x];
      sr += ((c1 >> 16) & 255) - ((c0 >> 16) & 255);
      sg += ((c1 >> 8) & 255) - ((c0 >> 8) & 255);
      sb += (c1 & 255) - (c0 & 255);
    }
  }
}

void pixelateLive(int block) {
  int n = livePixels.length;
  if (gradeTmp == null || gradeTmp.length != n) gradeTmp = new int[n];
  arrayCopy(livePixels, gradeTmp);
  int w = capW;
  int h = capH;
  for (int y = 0; y < h; y += block) {
    int by = min(h - 1, y + block / 2);
    int y2 = min(h, y + block);
    for (int x = 0; x < w; x += block) {
      int bx = min(w - 1, x + block / 2);
      int c = gradeTmp[by * w + bx];
      int x2 = min(w, x + block);
      for (int yy = y; yy < y2; yy++) {
        int row = yy * w;
        for (int xx = x; xx < x2; xx++) livePixels[row + xx] = c;
      }
    }
  }
}

void storeFeedback() {
  // Feedback buffers are updated inside applyFxStack when a Feedback unit is active.
}

void resetCameraGrade() {
  applySourceMemoryDefaults();
  rememberSourceSettings();
  markDirty();
}

void resetGroup(String name) {
  if (name.equals("LIGHT")) {
    camExposure = 0;
    camBrilliance = 0;
    camHighlights = 0;
    camShadows = 0;
    camContrast = 0;
    camBrightness = 0;
    camBlack = 0;
  } else if (name.equals("COLOR")) {
    camSaturation = 0;
    camVibrance = 0;
    camWarmth = 0;
    camTint = 0;
  } else if (name.equals("DETAILS")) {
    camSharp = 0;
    camClarity = 0;
    camNoise = 0;
    camVignette = 0;
  } else if (name.equals("CURVES")) {
    for (int i = 0; i < 4; i++) resetCurveBank(0, i);
    curveDrag = -1;
    curveSel = -1;
  } else if (name.equals("OUTCURVES")) {
    resetOutCurves();
    return;
  } else if (name.equals("LIVECURVES")) {
    resetCurveBankAll(2);
    return;
  } else if (name.equals("LOOPCURVES")) {
    resetCurveBankAll(3);
    return;
  } else if (name.equals("EFFECTS") || name.equals("FX")) {
    // FX panel Reset → active target; EFFECTS still wipes all stacks.
    if (name.equals("FX")) fxResetActiveStack();
    else resetEffects();
    return;
  } else return;
  markDirty();
}
