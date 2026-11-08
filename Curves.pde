static final int CURVE_MAX = 8;

class ToneCurve {
  float[] x = new float[CURVE_MAX];
  float[] y = new float[CURVE_MAX];
  int n = 2;
  int[] lut = new int[256];
  boolean identity = true;
  boolean dirty = true;
  ToneCurve() {
    x[0] = 0;
    y[0] = 0;
    x[1] = 1;
    y[1] = 1;
  }
}

ToneCurve[] curves;        // 0 Input / camera grade
ToneCurve[] outCurves;     // 1 Program output (after Out FX)
ToneCurve[] liveFxCurves;  // 2 After Live FX
ToneCurve[] loopFxCurves;  // 3 After Loop FX
int curveBank = 0;         // active editor bank
int curveChannel = 0;
int outCurveChannel = 0;
int liveFxCurveChannel = 0;
int loopFxCurveChannel = 0;
int curveDrag = -1;
int curveSel = -1;
float curveGX, curveGY, curveGW, curveGH;
int[][] curveHist = new int[4][64];
int[] curveHistPeak = new int[4];

void initCurves() {
  curves = new ToneCurve[4];
  outCurves = new ToneCurve[4];
  liveFxCurves = new ToneCurve[4];
  loopFxCurves = new ToneCurve[4];
  for (int i = 0; i < 4; i++) {
    curves[i] = new ToneCurve();
    outCurves[i] = new ToneCurve();
    liveFxCurves[i] = new ToneCurve();
    loopFxCurves[i] = new ToneCurve();
  }
  curveChannel = 0;
  outCurveChannel = 0;
  liveFxCurveChannel = 0;
  loopFxCurveChannel = 0;
  curveBank = 0;
  curveDrag = -1;
  curveSel = -1;
}

/** Curve bank for current FX target (Live / Loop / Out). */
int fxCurveBank() {
  if (fxTarget == FX_TGT_LOOP) return 3;
  if (fxTarget == FX_TGT_OUT) return 1;
  return 2;
}

ToneCurve[] curveSet(int bank) {
  if (curves == null) initCurves();
  if (bank == 1) return outCurves;
  if (bank == 2) return liveFxCurves;
  if (bank == 3) return loopFxCurves;
  return curves;
}

ToneCurve[] activeCurveSet() {
  return curveSet(curveBank);
}

int activeCurveChannel() {
  if (curveBank == 1) return outCurveChannel;
  if (curveBank == 2) return liveFxCurveChannel;
  if (curveBank == 3) return loopFxCurveChannel;
  return curveChannel;
}

void setActiveCurveChannel(int ch) {
  ch = constrain(ch, 0, 3);
  if (curveBank == 1) outCurveChannel = ch;
  else if (curveBank == 2) liveFxCurveChannel = ch;
  else if (curveBank == 3) loopFxCurveChannel = ch;
  else curveChannel = ch;
}

void resetCurve(int ch) {
  resetCurveBank(0, ch);
}

void resetCurveBank(int bank, int ch) {
  ToneCurve[] set = curveSet(bank);
  if (set == null || ch < 0 || ch >= set.length) return;
  ToneCurve c = set[ch];
  c.n = 2;
  c.x[0] = 0;
  c.y[0] = 0;
  c.x[1] = 1;
  c.y[1] = 1;
  c.dirty = true;
  if (curveBank == bank && activeCurveChannel() == ch) curveSel = -1;
}

void resetAllCurves() {
  // Input curves only (camera grade). Output has resetOutCurves / rst-OUTCURVES.
  if (curves == null) initCurves();
  for (int i = 0; i < 4; i++) resetCurveBank(0, i);
  curveDrag = -1;
  curveSel = -1;
}

void resetOutCurves() {
  resetCurveBankAll(1);
}

void resetCurveBankAll(int bank) {
  if (curves == null) initCurves();
  for (int i = 0; i < 4; i++) resetCurveBank(bank, i);
  curveDrag = -1;
  curveSel = -1;
  bumpFxCurveBank(bank);
  markDirty();
}

/** Live/Loop curves sit after FX — invalidate cached frames. */
void bumpFxCurveBank(int bank) {
  if (bank == 2) liveFxReady = false;
  else if (bank == 3) loopImgHead = -1;
  else if (bank == 1) { /* out curves reapplied each frame */ }
}

boolean curveBankOn(int bank) {
  ToneCurve[] set = curveSet(bank);
  if (set == null) return false;
  for (int i = 0; i < 4; i++) {
    if (set[i].dirty) rebuildLut(set[i]);
    if (!set[i].identity) return true;
  }
  return false;
}

boolean outCurvesOn() {
  return curveBankOn(1);
}

boolean liveFxCurvesOn() {
  return curveBankOn(2);
}

boolean loopFxCurvesOn() {
  return curveBankOn(3);
}

boolean curvesOn() {
  if (curves == null) return false;
  for (int i = 0; i < 4; i++) if (!curves[i].identity) return true;
  return false;
}

void ensureCurveLuts() {
  if (curves == null) initCurves();
  for (int i = 0; i < 4; i++) {
    if (curves[i].dirty) rebuildLut(curves[i]);
    if (outCurves[i].dirty) rebuildLut(outCurves[i]);
    if (liveFxCurves[i].dirty) rebuildLut(liveFxCurves[i]);
    if (loopFxCurves[i].dirty) rebuildLut(loopFxCurves[i]);
  }
}

void rebuildLut(ToneCurve c) {
  // Identity only for plain 0→0 / 1→1 (endpoints may sit inward when adjusted).
  c.identity = c.n == 2
    && abs(c.x[0]) < 0.004f && abs(c.y[0]) < 0.004f
    && abs(c.x[1] - 1) < 0.004f && abs(c.y[1] - 1) < 0.004f;
  int n = c.n;
  if (n < 2) {
    for (int i = 0; i < 256; i++) c.lut[i] = i;
    c.identity = true;
    c.dirty = false;
    return;
  }
  float[] d = new float[n - 1];
  float[] m = new float[n];
  for (int i = 0; i < n - 1; i++) {
    float dx = c.x[i + 1] - c.x[i];
    d[i] = dx > 1e-5f ? (c.y[i + 1] - c.y[i]) / dx : 0;
  }
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (int i = 1; i < n - 1; i++) {
    if (d[i - 1] * d[i] <= 0) m[i] = 0;
    else m[i] = (d[i - 1] + d[i]) * 0.5f;
  }
  for (int i = 0; i < n - 1; i++) {
    if (abs(d[i]) < 1e-6f) {
      m[i] = 0;
      m[i + 1] = 0;
    } else {
      float a = m[i] / d[i];
      float b = m[i + 1] / d[i];
      float s = a * a + b * b;
      if (s > 9f) {
        float t = 3f / sqrt(s);
        m[i] = t * a * d[i];
        m[i + 1] = t * b * d[i];
      }
    }
  }
  int seg = 0;
  for (int i = 0; i < 256; i++) {
    float t = i / 255f;
    while (seg < n - 2 && t > c.x[seg + 1]) seg++;
    float x0 = c.x[seg];
    float x1 = c.x[seg + 1];
    float h = x1 - x0;
    float u = h > 1e-5f ? constrain((t - x0) / h, 0, 1) : 0;
    float u2 = u * u;
    float u3 = u2 * u;
    float y = (2 * u3 - 3 * u2 + 1) * c.y[seg]
      + (u3 - 2 * u2 + u) * h * m[seg]
      + (-2 * u3 + 3 * u2) * c.y[seg + 1]
      + (u3 - u2) * h * m[seg + 1];
    c.lut[i] = y <= 0 ? 0 : y >= 1 ? 255 : (int) (y * 255f + 0.5f);
  }
  c.dirty = false;
}

void sampleCurveHist() {
  for (int ch = 0; ch < 4; ch++) {
    java.util.Arrays.fill(curveHist[ch], 0);
    curveHistPeak[ch] = 1;
  }
  if (livePixels == null) return;
  int n = livePixels.length;
  int step = max(1, n / 6000);
  for (int i = 0; i < n; i += step) {
    int p = livePixels[i];
    int r = (p >> 16) & 255;
    int g = (p >> 8) & 255;
    int b = p & 255;
    int luma = (r * 299 + g * 587 + b * 114) / 1000;
    int[] v = { luma, r, g, b };
    for (int ch = 0; ch < 4; ch++) {
      int bin = v[ch] * 63 / 255;
      int h = ++curveHist[ch][bin];
      if (h > curveHistPeak[ch]) curveHistPeak[ch] = h;
    }
  }
}

void applyCurves() {
  if (!curvesOn() || livePixels == null) return;
  int[] mr = curves[0].lut;
  int[] rr = curves[1].lut;
  int[] gg = curves[2].lut;
  int[] bb = curves[3].lut;
  boolean m = !curves[0].identity;
  boolean rOn = !curves[1].identity;
  boolean gOn = !curves[2].identity;
  boolean bOn = !curves[3].identity;
  int n = livePixels.length;
  for (int i = 0; i < n; i++) {
    int p = livePixels[i];
    int r = (p >> 16) & 255;
    int g = (p >> 8) & 255;
    int b = p & 255;
    if (m) {
      r = mr[r];
      g = mr[g];
      b = mr[b];
    }
    if (rOn) r = rr[r];
    if (gOn) g = gg[g];
    if (bOn) b = bb[b];
    livePixels[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
  }
}

color curveInk(int ch) {
  if (ch == 1) return SIGNAL;
  if (ch == 2) return #7d9a78;
  if (ch == 3) return ACCENT;
  return INK; // RGB master — white, readable on dark well
}

float drawCurveEditor(float x, float y, float w) {
  return drawCurveEditor(x, y, w, 0, "CURVES");
}

float drawCurveEditor(float x, float y, float w, int bank, String title) {
  curveBank = bank;
  ToneCurve[] set = curveSet(bank);
  int ch = activeCurveChannel();
  ensureCurveLuts();
  fill(DIM);
  textAlign(LEFT, BASELINE);
  ui(10);
  text(title, x, y + 10);
  String rst = bank == 1 ? "rst-OUTCURVES"
    : bank == 2 ? "rst-LIVECURVES"
    : bank == 3 ? "rst-LOOPCURVES"
    : "rst-CURVES";
  resetLink(rst, x + textWidth(title) + 12, y + 10);
  if (curveSel >= 0 && set != null) {
    ToneCurve c = set[ch];
    if (curveSel < c.n) {
      fill(INK);
      textAlign(RIGHT, BASELINE);
      text(round(c.x[curveSel] * 100) + "  →  " + round(c.y[curveSel] * 100), x + w, y + 10);
    }
  }
  y += 18;
  String[] ids = { "curve-ch#0", "curve-ch#1", "curve-ch#2", "curve-ch#3" };
  String[] labels = { "RGB", "R", "G", "B" };
  noStroke();
  fill(WELL);
  rect(x, y, w, 24, 12);
  float cw = w / 4f;
  for (int i = 0; i < 4; i++) {
    float tx = x + i * cw;
    if (inClip(y, 24)) hit(ids[i], tx, y, cw, 24);
    if (i == ch) {
      fill(curveInk(i));
      if (i == 0) rect(tx, y, cw, 24, 12, 0, 0, 12);
      else if (i == 3) rect(tx, y, cw, 24, 0, 12, 12, 0);
      else rect(tx + 2, y + 2, cw - 4, 20, 10);
    }
    // Dark text on light RGB/G pills; light text on R/B
    fill(i == ch ? (i == 0 || i == 2 ? #1a1a1e : PAPER) : MUTED);
    textAlign(CENTER, CENTER);
    ui(11);
    text(labels[i], tx + cw / 2f, y + 11);
  }
  y += 32;
  // Flatter editor — still wide enough to drag handles.
  float boxH = min(118, w * 0.62f);
  if (inClip(y, boxH)) hit("curve", x, y, w, boxH);
  noStroke();
  fill(WELL);
  rect(x, y, w, boxH, 8);
  float pad = 12;
  curveGX = x + pad;
  curveGY = y + pad;
  curveGW = w - pad * 2;
  curveGH = boxH - pad * 2;
  // Histogram only for input curves (sampled from grade)
  if (bank == 0) {
    int peak = curveHistPeak[ch];
    if (peak > 1) {
      fill(curveInk(ch), 36);
      float bw = curveGW / 64f;
      for (int i = 0; i < 64; i++) {
        float bh = curveHist[ch][i] / (float) peak * curveGH * 0.92f;
        rect(curveGX + i * bw, curveGY + curveGH - bh, max(1, bw - 0.6f), bh);
      }
    }
  }
  stroke(LINE);
  strokeWeight(1);
  for (int i = 1; i < 4; i++) {
    float g = i / 4f;
    line(curveGX + g * curveGW, curveGY, curveGX + g * curveGW, curveGY + curveGH);
    line(curveGX, curveGY + g * curveGH, curveGX + curveGW, curveGY + g * curveGH);
  }
  stroke(DIM);
  line(curveGX, curveGY + curveGH, curveGX + curveGW, curveGY);
  if (ch != 0 && set != null && !set[0].identity) {
    stroke(DIM);
    strokeWeight(1);
    drawLutLine(set[0], curveGX, curveGY, curveGW, curveGH);
  }
  stroke(curveInk(ch));
  strokeWeight(1.5);
  if (set != null) drawLutLine(set[ch], curveGX, curveGY, curveGW, curveGH);
  noStroke();
  ToneCurve c = set[ch];
  for (int i = 0; i < c.n; i++) {
    float px = curveGX + c.x[i] * curveGW;
    float py = curveGY + (1 - c.y[i]) * curveGH;
    boolean on = i == curveSel || i == curveDrag;
    if (on) {
      fill(curveInk(ch), 50);
      ellipse(px, py, 16, 16);
    }
    stroke(#1a1a1e);
    strokeWeight(1);
    fill(on ? PAPER : curveInk(ch));
    ellipse(px, py, on ? 8 : 6, on ? 8 : 6);
    noStroke();
    // Cam curve endpoints → MIDI map targets (horizontal black / white).
    if (bank == 0 && i == 0) mapTarget("sl-curve-black", px - 14, py - 14, 28, 28);
    if (bank == 0 && i == c.n - 1) mapTarget("sl-curve-white", px - 14, py - 14, 28, 28);
  }
  y += boxH + 14;
  fill(DIM);
  textAlign(LEFT, CENTER);
  ui(10);
  text("Click adds a point    ⌘-click removes", x, y);
  return y + 16;
}

void applyToneCurves(int[] px, ToneCurve[] set) {
  if (px == null || set == null) return;
  ensureCurveLuts();
  boolean m = !set[0].identity;
  boolean rOn = !set[1].identity;
  boolean gOn = !set[2].identity;
  boolean bOn = !set[3].identity;
  if (!m && !rOn && !gOn && !bOn) return;
  int[] mr = set[0].lut;
  int[] rr = set[1].lut;
  int[] gg = set[2].lut;
  int[] bb = set[3].lut;
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    int r = (c >> 16) & 255;
    int g = (c >> 8) & 255;
    int b = c & 255;
    if (m) {
      r = mr[r];
      g = mr[g];
      b = mr[b];
    }
    if (rOn) r = rr[r];
    if (gOn) g = gg[g];
    if (bOn) b = bb[b];
    px[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
  }
}

void applyOutCurves(int[] px) {
  if (px == null || !outCurvesOn()) return;
  applyToneCurves(px, outCurves);
}

void applyLiveFxCurves(int[] px) {
  if (px == null || !liveFxCurvesOn()) return;
  applyToneCurves(px, liveFxCurves);
}

void applyLoopFxCurves(int[] px) {
  if (px == null || !loopFxCurvesOn()) return;
  applyToneCurves(px, loopFxCurves);
}

void drawLutLine(ToneCurve c, float x, float y, float w, float h) {
  noFill();
  beginShape();
  int steps = max(24, (int) w);
  for (int i = 0; i <= steps; i++) {
    int lut = c.lut[constrain(i * 255 / steps, 0, 255)];
    vertex(x + i * w / steps, y + (1 - lut / 255f) * h);
  }
  endShape();
}

int nearestCurvePoint(ToneCurve c, float radius) {
  int best = -1;
  float bestD = radius * radius;
  for (int i = 0; i < c.n; i++) {
    float px = curveGX + c.x[i] * curveGW;
    float py = curveGY + (1 - c.y[i]) * curveGH;
    float dx = mouseX - px;
    float dy = mouseY - py;
    float d = dx * dx + dy * dy;
    if (d <= bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

int insertCurvePoint(ToneCurve c, float nx, float ny) {
  if (c.n >= CURVE_MAX) return -1;
  nx = constrain(nx, 0.02f, 0.98f);
  int at = 1;
  while (at < c.n && c.x[at] < nx) at++;
  if (at > 0 && nx < c.x[at - 1] + 0.02f) nx = c.x[at - 1] + 0.02f;
  if (at < c.n && nx > c.x[at] - 0.02f) nx = c.x[at] - 0.02f;
  if (nx <= c.x[0] + 0.015f || nx >= c.x[c.n - 1] - 0.015f) return -1;
  for (int i = c.n; i > at; i--) {
    c.x[i] = c.x[i - 1];
    c.y[i] = c.y[i - 1];
  }
  c.x[at] = nx;
  c.y[at] = ny;
  c.n++;
  return at;
}

void removeCurvePoint(ToneCurve c, int i) {
  if (i <= 0 || i >= c.n - 1) return;
  for (int k = i; k < c.n - 1; k++) {
    c.x[k] = c.x[k + 1];
    c.y[k] = c.y[k + 1];
  }
  c.n--;
  if (curveSel == i) curveSel = -1;
  else if (curveSel > i) curveSel--;
}

void curvePointerDown() {
  if (curves == null) initCurves();
  ToneCurve[] set = activeCurveSet();
  ToneCurve c = set[activeCurveChannel()];
  int near = nearestCurvePoint(c, 12);
  if (cmdDown()) {
    if (near >= 0) {
      if (near == 0 || near == c.n - 1) c.y[near] = near == 0 ? 0 : 1;
      else removeCurvePoint(c, near);
    } else resetCurveBank(curveBank, activeCurveChannel());
    c.dirty = true;
    curveDrag = -1;
    bumpFxCurveBank(curveBank);
    markDirty();
    flushSettings(true);
    return;
  }
  if (near >= 0) {
    curveDrag = near;
    curveSel = near;
    return;
  }
  float nx = constrain((mouseX - curveGX) / max(1, curveGW), 0, 1);
  float ny = constrain(1 - (mouseY - curveGY) / max(1, curveGH), 0, 1);
  int at = insertCurvePoint(c, nx, ny);
  if (at < 0) {
    note("Curve is full");
    return;
  }
  c.dirty = true;
  curveDrag = at;
  curveSel = at;
  bumpFxCurveBank(curveBank);
  markDirty();
}

void curveDragMove() {
  if (curveDrag < 0) return;
  ToneCurve[] set = activeCurveSet();
  if (set == null) return;
  ToneCurve c = set[activeCurveChannel()];
  int i = curveDrag;
  if (i < 0 || i >= c.n) return;
  float nx = constrain((mouseX - curveGX) / max(1, curveGW), 0, 1);
  float ny = constrain(1 - (mouseY - curveGY) / max(1, curveGH), 0, 1);
  if (i == 0) {
    // Black / bottom handler — free Y, X up to next point (levels-style).
    setCurveBlackX(c, nx);
    c.y[0] = ny;
  } else if (i == c.n - 1) {
    // White / top handler — free Y, X down from previous point.
    setCurveWhiteX(c, nx);
    c.y[c.n - 1] = ny;
  } else {
    float lo = c.x[i - 1] + 0.02f;
    float hi = c.x[i + 1] - 0.02f;
    c.x[i] = constrain(nx, lo, hi);
    c.y[i] = ny;
  }
  c.dirty = true;
  bumpFxCurveBank(curveBank);
  markDirty();
}

/** Input (cam) curve black handler X — MIDI / levels. Active RGB/R/G/B channel. */
void setInputCurveBlackX(float nx) {
  if (curves == null) initCurves();
  ToneCurve c = curves[constrain(curveChannel, 0, 3)];
  setCurveBlackX(c, nx);
  c.dirty = true;
  markDirty();
}

/** Input (cam) curve white handler X — MIDI / levels. Active RGB/R/G/B channel. */
void setInputCurveWhiteX(float nx) {
  if (curves == null) initCurves();
  ToneCurve c = curves[constrain(curveChannel, 0, 3)];
  setCurveWhiteX(c, nx);
  c.dirty = true;
  markDirty();
}

float inputCurveBlackX() {
  if (curves == null) initCurves();
  ToneCurve c = curves[constrain(curveChannel, 0, 3)];
  return c != null && c.n > 0 ? c.x[0] : 0;
}

float inputCurveWhiteX() {
  if (curves == null) initCurves();
  ToneCurve c = curves[constrain(curveChannel, 0, 3)];
  return c != null && c.n > 1 ? c.x[c.n - 1] : 1;
}

void setCurveBlackX(ToneCurve c, float nx) {
  if (c == null || c.n < 1) return;
  float hi = c.n > 1 ? c.x[1] - 0.02f : 0.45f;
  c.x[0] = constrain(nx, 0, max(0, hi));
}

void setCurveWhiteX(ToneCurve c, float nx) {
  if (c == null || c.n < 2) return;
  int i = c.n - 1;
  float lo = c.x[i - 1] + 0.02f;
  c.x[i] = constrain(nx, min(1, lo), 1);
}

void loadCurveBank(JSONArray all, ToneCurve[] set) {
  if (all == null || set == null) return;
  for (int ch = 0; ch < min(4, all.size()); ch++) {
    JSONArray pts = all.getJSONArray(ch);
    if (pts == null) continue;
    ToneCurve c = set[ch];
    int n = min(CURVE_MAX, pts.size());
    if (n < 2) continue;
    int w = 0;
    for (int i = 0; i < n; i++) {
      JSONObject p = pts.getJSONObject(i);
      float px = constrain(p.getFloat("x", 0), 0, 1);
      float py = constrain(p.getFloat("y", px), 0, 1);
      if (w > 0 && px <= c.x[w - 1] + 0.01f) continue;
      c.x[w] = px;
      c.y[w] = py;
      w++;
    }
    if (w < 2) continue;
    // Keep saved endpoint X (black/white handlers may sit inward).
    c.n = w;
    c.dirty = true;
  }
}

JSONArray saveCurveBank(ToneCurve[] set) {
  JSONArray all = new JSONArray();
  if (set == null) return all;
  for (int ch = 0; ch < 4; ch++) {
    ToneCurve c = set[ch];
    JSONArray pts = new JSONArray();
    for (int i = 0; i < c.n; i++) {
      JSONObject p = new JSONObject();
      p.setFloat("x", c.x[i]);
      p.setFloat("y", c.y[i]);
      pts.setJSONObject(i, p);
    }
    all.setJSONArray(ch, pts);
  }
  return all;
}

void loadCurves(JSONObject o) {
  if (curves == null) initCurves();
  curveChannel = constrain(o.getInt("curveChannel", 0), 0, 3);
  outCurveChannel = constrain(o.getInt("outCurveChannel", 0), 0, 3);
  liveFxCurveChannel = constrain(o.getInt("liveFxCurveChannel", 0), 0, 3);
  loopFxCurveChannel = constrain(o.getInt("loopFxCurveChannel", 0), 0, 3);
  if (o.hasKey("curves")) loadCurveBank(o.getJSONArray("curves"), curves);
  if (o.hasKey("outCurves")) loadCurveBank(o.getJSONArray("outCurves"), outCurves);
  if (o.hasKey("liveFxCurves")) loadCurveBank(o.getJSONArray("liveFxCurves"), liveFxCurves);
  if (o.hasKey("loopFxCurves")) loadCurveBank(o.getJSONArray("loopFxCurves"), loopFxCurves);
}

void saveCurves(JSONObject o) {
  if (curves == null) return;
  o.setInt("curveChannel", curveChannel);
  o.setInt("outCurveChannel", outCurveChannel);
  o.setInt("liveFxCurveChannel", liveFxCurveChannel);
  o.setInt("loopFxCurveChannel", loopFxCurveChannel);
  o.setJSONArray("curves", saveCurveBank(curves));
  o.setJSONArray("outCurves", saveCurveBank(outCurves));
  o.setJSONArray("liveFxCurves", saveCurveBank(liveFxCurves));
  o.setJSONArray("loopFxCurves", saveCurveBank(loopFxCurves));
}
