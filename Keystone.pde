float[][] corners = new float[4][2];
float[][] cornersDefault = {
  {0, 0}, {1, 0}, {1, 1}, {0, 1}
};
boolean cornersReady = false;

void resetCornersIfNeeded() {
  if (!cornersReady) resetCorners();
}

void resetCorners() {
  corners = new float[4][2];
  for (int i = 0; i < 4; i++) {
    corners[i][0] = cornersDefault[i][0];
    corners[i][1] = cornersDefault[i][1];
  }
  cornersReady = true;
  markDirty();
}

void insetCorners(float m) {
  corners[0][0] = m;
  corners[0][1] = m;
  corners[1][0] = 1 - m;
  corners[1][1] = m;
  corners[2][0] = 1 - m;
  corners[2][1] = 1 - m;
  corners[3][0] = m;
  corners[3][1] = 1 - m;
  markDirty();
}

float[][] homography(float ox, float oy, float dw, float dh) {
  double[] sx = {0, 1, 1, 0};
  double[] sy = {0, 0, 1, 1};
  double[][] A = new double[8][9];
  for (int i = 0; i < 4; i++) {
    double x = sx[i];
    double y = sy[i];
    double u = ox + corners[i][0] * dw;
    double v = oy + corners[i][1] * dh;
    int r = i * 2;
    A[r][0] = x;
    A[r][1] = y;
    A[r][2] = 1;
    A[r][6] = -u * x;
    A[r][7] = -u * y;
    A[r][8] = u;
    A[r + 1][3] = x;
    A[r + 1][4] = y;
    A[r + 1][5] = 1;
    A[r + 1][6] = -v * x;
    A[r + 1][7] = -v * y;
    A[r + 1][8] = v;
  }
  if (!solveGauss(A)) return identityMap(ox, oy, dw, dh);
  float[][] H = new float[3][3];
  H[0][0] = (float) A[0][8];
  H[0][1] = (float) A[1][8];
  H[0][2] = (float) A[2][8];
  H[1][0] = (float) A[3][8];
  H[1][1] = (float) A[4][8];
  H[1][2] = (float) A[5][8];
  H[2][0] = (float) A[6][8];
  H[2][1] = (float) A[7][8];
  H[2][2] = 1;
  return H;
}

float[][] identityMap(float ox, float oy, float dw, float dh) {
  float[][] H = new float[3][3];
  H[0][0] = dw;
  H[0][2] = ox;
  H[1][1] = dh;
  H[1][2] = oy;
  H[2][2] = 1;
  return H;
}

boolean solveGauss(double[][] M) {
  int n = 8;
  for (int col = 0; col < n; col++) {
    int piv = col;
    for (int r = col + 1; r < n; r++) {
      if (Math.abs(M[r][col]) > Math.abs(M[piv][col])) piv = r;
    }
    if (Math.abs(M[piv][col]) < 1e-10) return false;
    if (piv != col) {
      double[] tmp = M[col];
      M[col] = M[piv];
      M[piv] = tmp;
    }
    double div = M[col][col];
    for (int j = col; j <= n; j++) M[col][j] /= div;
    for (int r = 0; r < n; r++) {
      if (r == col) continue;
      double f = M[r][col];
      if (f == 0) continue;
      for (int j = col; j <= n; j++) M[r][j] -= f * M[col][j];
    }
  }
  return true;
}

void applyH(float[][] H, float u, float v, float[] out) {
  float x = H[0][0] * u + H[0][1] * v + H[0][2];
  float y = H[1][0] * u + H[1][1] * v + H[1][2];
  float w = H[2][0] * u + H[2][1] * v + H[2][2];
  if (abs(w) < 1e-5f) w = (w < 0) ? -1e-5f : 1e-5f;
  out[0] = x / w;
  out[1] = y / w;
}

void expandPoint(float[] p, float cx, float cy, float amt) {
  float dx = p[0] - cx;
  float dy = p[1] - cy;
  float len = sqrt(dx * dx + dy * dy);
  if (len > 0.01f) {
    p[0] += dx / len * amt;
    p[1] += dy / len * amt;
  }
}

public void drawWarp(PGraphics pg, PImage tex, float ox, float oy, float dw, float dh) {
  if (pg == null || tex == null || dw < 2 || dh < 2) return;
  float[][] H = homography(ox, oy, dw, dh);
  boolean p3 = pg.is3D();
  pg.pushStyle();
  pg.blendMode(BLEND);
  pg.noTint();
  pg.noStroke();
  pg.textureMode(NORMAL);
  pg.beginShape(TRIANGLES);
  pg.texture(tex);
  int n = 18;
  float[] a = new float[2];
  float[] b = new float[2];
  float[] c = new float[2];
  float[] d = new float[2];
  for (int y = 0; y < n; y++) {
    for (int x = 0; x < n; x++) {
      float u0 = x / (float) n;
      float v0 = y / (float) n;
      float u1 = (x + 1) / (float) n;
      float v1 = (y + 1) / (float) n;
      applyH(H, u0, v0, a);
      applyH(H, u1, v0, b);
      applyH(H, u1, v1, c);
      applyH(H, u0, v1, d);
      float cx = (a[0] + b[0] + c[0] + d[0]) * 0.25f;
      float cy = (a[1] + b[1] + c[1] + d[1]) * 0.25f;
      expandPoint(a, cx, cy, 0.6f);
      expandPoint(b, cx, cy, 0.6f);
      expandPoint(c, cx, cy, 0.6f);
      expandPoint(d, cx, cy, 0.6f);
      emitTri(pg, p3, a, b, c, u0, v0, u1, v0, u1, v1);
      emitTri(pg, p3, a, c, d, u0, v0, u1, v1, u0, v1);
    }
  }
  pg.endShape();
  pg.textureMode(IMAGE);
  pg.popStyle();
}

void emitTri(PGraphics pg, boolean p3, float[] a, float[] b, float[] c,
             float au, float av, float bu, float bv, float cu, float cv) {
  if (p3) {
    pg.vertex(a[0], a[1], 0, au, av);
    pg.vertex(b[0], b[1], 0, bu, bv);
    pg.vertex(c[0], c[1], 0, cu, cv);
  } else {
    pg.vertex(a[0], a[1], au, av);
    pg.vertex(b[0], b[1], bu, bv);
    pg.vertex(c[0], c[1], cu, cv);
  }
}

public void drawGuides(PGraphics pg, float ox, float oy, float dw, float dh) {
  float[][] H = homography(ox, oy, dw, dh);
  pg.pushStyle();
  pg.noFill();
  pg.stroke(255, 150);
  pg.strokeWeight(2);
  float[] tl = new float[2];
  float[] tr = new float[2];
  float[] br = new float[2];
  float[] bl = new float[2];
  applyH(H, 0, 0, tl);
  applyH(H, 1, 0, tr);
  applyH(H, 1, 1, br);
  applyH(H, 0, 1, bl);
  pg.line(tl[0], tl[1], tr[0], tr[1]);
  pg.line(tr[0], tr[1], br[0], br[1]);
  pg.line(br[0], br[1], bl[0], bl[1]);
  pg.line(bl[0], bl[1], tl[0], tl[1]);
  pg.stroke(255, 80);
  pg.strokeWeight(1);
  float[] p = new float[2];
  float[] q = new float[2];
  for (int i = 1; i <= 2; i++) {
    float t = i / 3f;
    applyH(H, t, 0, p);
    applyH(H, t, 1, q);
    pg.line(p[0], p[1], q[0], q[1]);
    applyH(H, 0, t, p);
    applyH(H, 1, t, q);
    pg.line(p[0], p[1], q[0], q[1]);
  }
  pg.popStyle();
}

public void drawHandles(PGraphics pg, float ox, float oy, float dw, float dh, float radius) {
  pg.pushStyle();
  pg.textFont(uiFont);
  pg.textAlign(CENTER, CENTER);
  pg.textSize(radius * 0.7f);
  for (int i = 0; i < 4; i++) {
    float x = ox + corners[i][0] * dw;
    float y = oy + corners[i][1] * dh;
    pg.noFill();
    pg.stroke(i == activeCorner ? #c9c7c2 : #727884);
    pg.strokeWeight(1);
    float s = max(8, radius);
    pg.rect(x - s / 2f, y - s / 2f, s, s);
    pg.fill(#c9c7c2);
    pg.text(str(i + 1), x, y - 1);
  }
  pg.popStyle();
}

int pickCornerPx(float mx, float my, float ox, float oy, float dw, float dh, float radius) {
  if (dw < 2 || dh < 2) return -1;
  int best = -1;
  float bestD = radius * radius;
  for (int i = 0; i < 4; i++) {
    float x = ox + corners[i][0] * dw;
    float y = oy + corners[i][1] * dh;
    float dx = mx - x;
    float dy = my - y;
    float d = dx * dx + dy * dy;
    if (d <= bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

boolean keystoneActive() {
  for (int i = 0; i < 4; i++) {
    if (abs(corners[i][0] - cornersDefault[i][0]) > 0.001f) return true;
    if (abs(corners[i][1] - cornersDefault[i][1]) > 0.001f) return true;
  }
  return false;
}

PGraphics beamerGfx;

/**
 * Prepare GPU frame for external out. Stays on GPU — no CPU readback.
 * Without keystone, present the program texture directly (an extra image()
 * copy into beamerGfx was half-texel filtering — mirror seams looked shifted).
 * Keystone still warps into beamerGfx.
 */
void prepareBeamerGpu(PImage program) {
  if (program == null || capW < 2 || capH < 2) {
    beamerPresent = null;
    return;
  }
  if (!keystoneActive()) {
    beamerPresent = program;
    return;
  }
  beamerGfx = ensureFrame(beamerGfx);
  beamerGfx.beginDraw();
  beamerGfx.background(0);
  beamerGfx.blendMode(BLEND);
  beamerGfx.noTint();
  drawWarp(beamerGfx, program, 0, 0, capW, capH);
  beamerGfx.endDraw();
  beamerPresent = beamerGfx;
}
