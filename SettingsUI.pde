// Minimal tool palette — one accent, quiet neutrals, no chrome noise.
color INK = #ececef;
color MUTED = #8a8a92;
color DIM = #5c5c64;
color LINE = #2a2a30;
color CARD = #121214;
color WELL = #1a1a1e;
color ACCENT = #d7dde8;
color TONE = #c4a574;
color CHROMA = #7a9e9a;
color GRAIN = #9a8fb0;
color SIGNAL = #d07068;
color MAP = #7aa3c4;
color PAPER = #0b0b0d;
color REC = #d07068;
color PLAY = #c4a574;
color DUB = #c4a574;

int inspectorTab = 0;
int lastWorkTab = 0;

class Hit {
  String id;
  float x, y, w, h;
  Hit(String id, float x, float y, float w, float h) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
  boolean contains(float mx, float my) {
    return mx >= x && mx < x + w && my >= y && my < y + h;
  }
}

class Sld {
  String id;
  float x, track, w, minv, maxv;
  boolean vert;
  boolean radial;
  float unit;
  Sld(String id, float x, float track, float w, float minv, float maxv) {
    this(id, x, track, w, minv, maxv, false);
  }
  Sld(String id, float x, float track, float w, float minv, float maxv, boolean vert) {
    this.id = id;
    this.x = x;
    this.track = track;
    this.w = w;
    this.minv = minv;
    this.maxv = maxv;
    this.vert = vert;
  }
  Sld(String id, float cx, float cy, float radius, float minv, float maxv, float unit, boolean radial) {
    this.id = id;
    this.x = cx;
    this.track = cy;
    this.w = radius;
    this.minv = minv;
    this.maxv = maxv;
    this.unit = unit;
    this.radial = radial;
  }
}

float dockX() {
  return width - 320;
}

class MapFrame {
  String id;
  float x, y, w, h;
  MapFrame(String id, float x, float y, float w, float h) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
}

class NumBox {
  String id;
  float x, y, w, h, v, minv, maxv;
  NumBox(String id, float x, float y, float w, float h, float v, float minv, float maxv) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.v = v;
    this.minv = minv;
    this.maxv = maxv;
  }
}

ArrayList<Sld> slds = new ArrayList<Sld>();
ArrayList<MapFrame> mapFrames = new ArrayList<MapFrame>();
ArrayList<NumBox> nums = new ArrayList<NumBox>();
String dragSlider = null;
float knobGrabY = 0;
float knobGrabU = 0;
float clipTop = -100000;
float clipBot = 100000;
float gradeScroll = 0;
float gradeScrollMax = 0;
float midiScroll = 0;
float midiScrollMax = 0;

boolean inClip(float y, float h) {
  return y + h > clipTop && y < clipBot;
}

float beamerStageX, beamerStageY, beamerStageW, beamerStageH;
/** FX + perf keyboard only (+ space). */
float kbFootH = 122;

void hit(String id, float x, float y, float w, float h) {
  hits.add(new Hit(id, x, y, w, h));
}

void numHit(String id, float x, float y, float w, float h, float v, float minv, float maxv) {
  if (midiMapMode || !inClip(y, h)) return;
  nums.add(new NumBox(id, x, y, w, h, v, minv, maxv));
}

NumBox findNum(String id) {
  if (id == null) return null;
  for (int i = 0; i < nums.size(); i++) {
    if (nums.get(i).id.equals(id)) return nums.get(i);
  }
  return null;
}

void mapTarget(String id, float x, float y, float w, float h) {
  if (!midiMapMode || id == null || findBind(id) == null) return;
  if (!inClip(y, h)) return;
  mapFrames.add(new MapFrame(id, x, y, w, h));
}

String hitTest(float mx, float my) {
  for (int i = hits.size() - 1; i >= 0; i--) {
    if (hits.get(i).contains(mx, my)) return hits.get(i).id;
  }
  return null;
}

Sld findSld(String id) {
  if (id == null) return null;
  // Last match = topmost hit (same order as hitTest).
  for (int i = slds.size() - 1; i >= 0; i--) {
    if (slds.get(i).id.equals(id)) return slds.get(i);
  }
  return null;
}

String fitText(String s, float maxW) {
  if (s == null) return "";
  if (textWidth(s) <= maxW) return s;
  String ell = "…";
  int n = s.length();
  while (n > 1 && textWidth(s.substring(0, n) + ell) > maxW) n--;
  return s.substring(0, n) + ell;
}

float unit(float v, float a, float b) {
  if (abs(b - a) < 0.0001) return 0;
  return constrain((v - a) / (b - a), 0, 1);
}

void kicker(String s, float x, float y, float w) {
  fill(DIM);
  textAlign(LEFT, BASELINE);
  ui(10);
  text(s, x, y);
}

void panel(float x, float y, float w, float h) {
  // No card chrome — just a quiet plane with a hairline edge.
  noStroke();
  fill(CARD);
  rect(x, y, w, h);
  stroke(LINE);
  strokeWeight(1);
  line(x, y, x + w, y);
  noStroke();
}

void button(String id, String label, float x, float y, float w, float h, boolean on) {
  if (inClip(y, h)) hit(id, x, y, w, h);
  noStroke();
  if (on) fill(WELL);
  else noFill();
  if (on) rect(x, y, w, h);
  stroke(LINE);
  strokeWeight(1);
  noFill();
  rect(x + 0.5, y + 0.5, w - 1, h - 1);
  noStroke();
  fill(on ? INK : MUTED);
  textAlign(CENTER, CENTER);
  ui(11);
  text(label, x + w / 2f, y + h / 2f - 1);
}

void check(String id, String label, float x, float y, float w, boolean on) {
  if (inClip(y - 2, 18)) {
    hit(id, x, y - 2, w, 18);
    String bind = bindForHit(id);
    if (bind != null) mapTarget(bind, x, y - 4, w, 22);
  }
  stroke(on ? ACCENT : LINE);
  strokeWeight(1);
  noFill();
  rect(x, y - 1, 12, 12);
  if (on) {
    noStroke();
    fill(ACCENT);
    rect(x + 3, y + 2, 6, 6);
  }
  noStroke();
  fill(on ? INK : MUTED);
  textAlign(LEFT, CENTER);
  ui(11);
  text(fitText(label, w - 22), x + 20, y + 4);
}

void row(String id, String label, float x, float y, float w, boolean on) {
  if (inClip(y, 26)) hit(id, x, y, w, 26);
  noStroke();
  if (on) {
    stroke(ACCENT);
    strokeWeight(1);
    line(x, y + 4, x, y + 22);
    noStroke();
  }
  fill(on ? INK : MUTED);
  textAlign(LEFT, CENTER);
  ui(11);
  text(fitText(label, w - 16), x + 12, y + 13);
}

void segments(String[] ids, String[] labels, int selected, float x, float y, float w, float h) {
  float cw = w / labels.length;
  stroke(LINE);
  strokeWeight(1);
  line(x, y + h, x + w, y + h);
  noStroke();
  for (int i = 0; i < labels.length; i++) {
    float tx = x + i * cw;
    if (inClip(y, h)) hit(ids[i], tx, y, cw, h);
    if (i == selected) {
      stroke(ACCENT);
      strokeWeight(1);
      line(tx + 2, y + h, tx + cw - 2, y + h);
      noStroke();
    }
    fill(i == selected ? INK : MUTED);
    textAlign(CENTER, CENTER);
    ui(11);
    text(labels[i], tx + cw / 2f, y + h / 2f - 1);
  }
}

color bankInk(String title) {
  if (title.equals("LIGHT")) return TONE;
  if (title.equals("COLOR")) return CHROMA;
  if (title.equals("DETAILS") || title.equals("EFFECTS")) return GRAIN;
  return ACCENT;
}

void resetLink(String id, float x, float baseline) {
  ui(10);
  String label = "Reset";
  float tw = textWidth(label);
  float hy = baseline - 11;
  boolean hot = mouseX >= x && mouseX < x + tw && mouseY >= hy && mouseY < hy + 14;
  fill(hot ? INK : MUTED);
  textAlign(LEFT, BASELINE);
  text(label, x, baseline);
  if (inClip(hy, 14)) hit(id, x, hy, tw + 2, 14);
}

/** Thin horizontal slider — label left, value right, track below. */
float hSlide(String id, String label, String value, float x, float y, float w,
             float v, float minv, float maxv) {
  float trackY = y + 16;
  float trackH = 2;
  float u = unit(v, minv, maxv);
  boolean hot = dragSlider != null && dragSlider.equals(id);

  fill(MUTED);
  textAlign(LEFT, BASELINE);
  ui(11);
  text(fitText(label, w * 0.55f), x, y + 10);
  fill(hot ? INK : DIM);
  textAlign(RIGHT, BASELINE);
  text(value, x + w, y + 10);

  noStroke();
  fill(WELL);
  rect(x, trackY, w, trackH);
  fill(hot ? ACCENT : INK);
  rect(x, trackY, max(2, w * u), trackH);
  // thumb
  float tx = x + w * u;
  fill(INK);
  rect(tx - 1, trackY - 3, 2, trackH + 6);

  if (inClip(y, 28)) {
    slds.add(new Sld(id, x, trackY, w, minv, maxv, false));
    hit(id, x, y, w, 28);
    mapTarget(id, x, y, w, 28);
    numHit(id, x + w - 48, y, 48, 14, v, minv, maxv);
  }
  return y + 34;
}

float sliderRow(String id, String label, String value, float x, float y, float w, float v, float minv, float maxv) {
  return hSlide(id, label, value, x, y, w, v, minv, maxv);
}

float faderBank(String title, String[] ids, String[] shorts, String[] names, String[] values,
                float[] vs, float[] mins, float[] maxs, float x, float y, float w) {
  fill(DIM);
  textAlign(LEFT, BASELINE);
  ui(10);
  text(title, x, y + 10);
  float titleW = textWidth(title);
  resetLink("rst-" + title, x + titleW + 14, y + 10);
  float cy = y + 20;
  for (int i = 0; i < ids.length; i++) {
    cy = hSlide(ids[i], shorts[i], values[i], x, cy, w, vs[i], mins[i], maxs[i]);
  }
  return cy + 4;
}

void drawInterface() {
  float top = 52;
  float margin = 0;
  float x2 = dockX();
  float cardH = height - top;
  float prevW = x2;
  float dockW = width - x2;

  // Full-bleed preview plane + quiet dock separator
  noStroke();
  fill(#0e0e10);
  rect(0, top, prevW, cardH);
  fill(CARD);
  rect(x2, top, dockW, cardH);
  stroke(LINE);
  strokeWeight(1);
  line(x2, top, x2, height);
  line(0, top, width, top);
  noStroke();

  drawHeader(x2);
  drawPreview(0, top, prevW, cardH);
  drawInspector(x2, top, dockW, cardH);
  drawMapFrames();
  drawEditField();
}

void drawHeader(float x2) {
  float logoS = 28;
  float textX = 16 + logoS + 10;
  drawBrandMark(16, 10, logoS);
  fill(INK);
  textAlign(LEFT, CENTER);
  ui(12);
  text("LuckyLoop", textX, 26);

  float barX = textX + textWidth("LuckyLoop") + 28;
  float barW = min(600, x2 - barX - 160);
  drawTopModeBar(barX, 10, barW, 28);

  String modeName = modeLabel();
  color mc = MUTED;
  if (mode == MODE_REC) mc = REC;
  else if (mode == MODE_DUB || mode == MODE_PLAY) mc = PLAY;
  else if (stopModeOn() && stopPlaying) mc = PLAY;
  fill(mc);
  textAlign(LEFT, CENTER);
  ui(11);
  text(modeName, barX + barW + 16, 26);

  fill(DIM);
  textAlign(RIGHT, CENTER);
  ui(10);
  text(capW + "×" + capH + "  ·  " + capFps, x2 - 20, 26);

  // Dock: MIDI · cam · EXPORT · SET
  float bx = x2 + 16;
  hit("midi-map", bx, 14, 48, 24);
  fill(midiMapMode ? MAP : MUTED);
  textAlign(LEFT, CENTER);
  ui(11);
  text("MIDI", bx, 26);

  boolean exporting = exportBusy || archiveBusy;
  String exportLab = exporting ? "…" : "EXPORT";
  ui(11);
  float exportW = max(52, textWidth(exportLab) + 8);
  float exportX = width - 44 - 8 - exportW;
  boolean canExport = hasLoop() && !exporting;
  hit("proj-export", exportX, 14, exportW, 24);
  fill(exporting ? PLAY : (canExport ? MUTED : DIM));
  textAlign(CENTER, CENTER);
  text(exportLab, exportX + exportW / 2f, 25);
  if (exporting) {
    stroke(PLAY);
    strokeWeight(1);
    line(exportX + 4, 37, exportX + exportW - 4, 37);
    noStroke();
  }

  if (midiMapMode) {
    stroke(midiPickId != null ? PLAY : MAP);
    strokeWeight(1);
    line(bx, 38, bx + 36, 38);
    noStroke();
    float hx = bx + 48;
    float hw = max(40, exportX - 12 - hx);
    fill(midiPickId != null ? PLAY : MAP);
    ui(midiPickId != null ? 11 : 10);
    textAlign(LEFT, CENTER);
    text(fitText(midiHint(), hw), hx, 26);
  } else {
    String cam = sourceLabel();
    float camRight = exportX - 12;
    float camLeft = bx + 52;
    float camW = max(40, camRight - camLeft);
    fill(DIM);
    ui(10);
    textAlign(RIGHT, CENTER);
    text(fitText(cam, camW), camRight, 26);
  }
  paintGear(width - 44, 14, 28, 24, inspectorTab == 3);
}

/** Cool ALL-CAPS strip: LIVE · STOPTRICK · DRAW · TEXT · FX · OUTPUT */
void drawTopModeBar(float x, float y, float w, float h) {
  int[] modes = {TOP_LIVE, TOP_STOP, TOP_DRAW, TOP_NOTES, TOP_FX, TOP_OUTPUT};
  String[] labs = {"LIVE", "STOPTRICK", "DRAW", "TEXT", "FX", "OUTPUT"};
  float gap = 3;
  float cw = (w - gap * (labs.length - 1)) / labs.length;
  for (int i = 0; i < labs.length; i++) {
    float tx = x + i * (cw + gap);
    hit("top-" + modes[i], tx, y, cw, h);
    boolean on = topMode == modes[i];
    boolean sep = modes[i] == TOP_FX; // visual break before FX / OUTPUT
    if (sep) {
      stroke(LINE);
      strokeWeight(1);
      line(tx - gap * 0.5f, y + 6, tx - gap * 0.5f, y + h - 6);
      noStroke();
    }
    fill(on ? INK : DIM);
    textAlign(CENTER, CENTER);
    ui(10);
    text(labs[i], tx + cw / 2f, y + h / 2f - 1);
    if (on) {
      stroke(ACCENT);
      strokeWeight(1);
      line(tx + 4, y + h - 1, tx + cw - 4, y + h - 1);
      noStroke();
    }
  }
}

void drawPreview(float x, float y, float w, float h) {
  float pad = 20;
  float footH = kbFootH;
  float timelineH = (stopModeOn() || drawModeOn()) ? 28 : 0;
  float statusBand = 36; // progress + status under preview
  float topLabel = 28; // source / blend label above the frame
  float maxW = w - pad * 2;
  float maxH = h - footH - statusBand - timelineH - topLabel - 8;
  float aspect = capW / (float) capH;
  float iw = maxW;
  float ih = iw / aspect;
  if (ih > maxH) {
    ih = maxH;
    iw = ih * aspect;
  }
  float ix = round(x + (w - iw) / 2f);
  float iy = round(y + topLabel); // top-aligned — room for status + frame timeline below
  iw = round(iw);
  ih = round(ih);

  textAlign(LEFT, CENTER);
  ui(11);
  if (outputEditOn()) {
    fill(DIM);
    text("OUTPUT KEYSTONE", ix, iy - 14);
    textAlign(RIGHT, CENTER);
    text("R reset  ·  I inset", ix + iw, iy - 14);
  } else if (notesViewOn()) {
    fill(DIM);
    text("TEXT", ix, iy - 14);
    textAlign(RIGHT, CENTER);
    String textHint = textPlaceOn ? "pinch  ·  rotate  ·  drag"
      : (textSel < 0 ? "drag a line" : "esc deselects  ·  drag a line");
    text(textHint, ix + iw, iy - 14);
  } else {
    drawLayerTicks(ix, iy - 14);
    drawPreviewMixChrome(ix, iy - 14, iw);
  }

  noStroke();
  fill(0);
  rect(ix, iy, iw, ih);
  previewIx = ix;
  previewIy = iy;
  previewIw = iw;
  previewIh = ih;
  float badgeY = iy + 8;
  boolean showDesktopPip = false;

  if (outputEditOn()) {
    previewBoxX = ix;
    previewBoxY = iy;
    previewBoxW = iw;
    previewBoxH = ih;
    PImage pinSrc = shownFrame();
    if (!blackoutSolid() && pinSrc != null) drawWarp(g, pinSrc, ix, iy, iw, ih);
    if (showGrid) drawGuides(g, ix, iy, iw, ih);
    drawHandles(g, ix, iy, iw, ih, 14);
    blendMode(BLEND);
    noTint();
    tag(ix + 8, badgeY, "DRAG CORNERS");
  } else {
    boolean loopPreview = !blackoutSolid() && loopAudible() && syncLoopImage();
    boolean stopPrev = !blackoutSolid() && stopOverlayAlpha() > 0 && syncStopImage();
    boolean drawPrev = !blackoutSolid() && drawModeOn() && drawImg != null;
    if (drawPrev || (stopPrev && gpuGradeActive)) {
      // One CPU plate so onion shares the camera grid. A separate image()
      // of the ghost is half a texel off on the external screen.
      boolean liveOn = liveOpacity > 0.001 && liveShowing() && outputIncludesLive();
      PImage loopPlate = loopPreview ? loopImg : null;
      drawPreviewImg = composeDrawProgramCPU(drawPreviewImg, loopPlate, liveOn, stopOverlayAlpha(false));
      drawPreviewGfx = uploadPlate(drawPreviewGfx, drawPreviewImg);
      imageMode(CORNER);
      PImage plate = drawPreviewGfx != null ? drawPreviewGfx : drawPreviewImg;
      if (plate != null) image(plate, ix, iy, iw, ih);
    } else if (loopPreview && gpuGradeActive) {
      PImage loopPlate = loopPreview ? loopImg : (loopHistGhost ? loopHistImg : null);
      if (loopPlate != null) {
        int la = constrain(round(shownLoopOpacity() * 255), 0, 255);
        if (la < 255) tint(255, la);
        if (la > 0) image(loopPlate, ix, iy, iw, ih);
        if (la < 255) noTint();
      }
      // Live under onion — opacity after Live FX; soft Mul/Scr via bake+lerp.
      if (liveOpacity > 0.001 && liveShowing() && outputIncludesLive()) {
        PImage liveSrc = liveCompositeSource();
        if (liveSrc != null) {
          int a = constrain(round(liveOpacity * 255), 0, 255);
          previewLiveLayer(ix, iy, iw, ih, loopPreview ? loopImg : null, liveSrc, a);
        }
      }
      if (stopPrev) {
        PImage stopSrc = stopDisplayImage();
        if (stopSrc != null) {
          int sa = stopOverlayAlpha();
          blendMode(BLEND);
          if (stopHeadIsInkPlate()) {
            PImage plate = stopOnionPlate(sa);
            noTint();
            if (plate != null) image(plate, ix, iy, iw, ih);
          } else if (sa >= 255) {
            int sb = stopOverlayBlend();
            if (sb == BLEND_NORMAL) blendMode(BLEND);
            else blendMode(sb == BLEND_SCREEN ? SCREEN : MULTIPLY);
            image(stopSrc, ix, iy, iw, ih);
            blendMode(BLEND);
          } else {
            previewLiveLayer(ix, iy, iw, ih, loopPreview ? loopImg : null, stopSrc, sa);
          }
        }
      }
      paintHapCoverPreview(ix, iy, iw, ih);
    } else if (!loopHistGhost && !blackoutSolid() && liveOpacity > 0.001 && liveOpacity < 0.999
        && liveShowing() && outputIncludesLive()) {
      // Live alone, soft opacity — fade against black (shownFrame may lag one tick).
      PImage liveSrc = liveCompositeSource();
      if (liveSrc == null) liveSrc = shownFrame();
      if (liveSrc != null) {
        noStroke();
        fill(0);
        rect(ix, iy, iw, ih);
        blendMode(BLEND);
        tint(255, constrain(round(liveOpacity * 255), 0, 255));
        image(liveSrc, ix, iy, iw, ih);
        noTint();
      }
    } else {
      PImage shown = shownFrame();
      if (shown != null) image(shown, ix, iy, iw, ih);
    }
    if (drawModeOn() && drawTool != DRAW_FILL && drawTool != DRAW_PICK) {
      float cx = ix + drawNX * iw;
      float cy = iy + (1f - drawNY) * ih;
      noFill();
      stroke(drawTool == DRAW_ERASER ? MUTED : drawInk());
      strokeWeight(drawTouching ? 1.4 : 1);
      float r = max(3, drawBrushPx() * 0.5f * (ih / (float) capH));
      if (drawRaster) rect(cx - r, cy - r, r * 2, r * 2);
      else ellipse(cx, cy, r * 2, r * 2);
      noStroke();
    }
    color mark = LINE;
    if (mode == MODE_REC || mode == MODE_DUB) mark = REC;
    else if (mode == MODE_PLAY) mark = PLAY;
    regMarks(ix, iy, iw, ih, mark);

    if (mode == MODE_REC || mode == MODE_DUB || mode == MODE_PLAY) {
      noFill();
      color frame = mode == MODE_PLAY ? PLAY : REC;
      stroke(frame);
      strokeWeight(1);
      rect(ix - 0.5, iy - 0.5, iw + 1, ih + 1);
      noStroke();
    }

    if (!liveValid && !drawModeOn()) {
      fill(INK);
      textAlign(CENTER, CENTER);
      ui(12);
      String msg = (sourceMode == SRC_CAM && !camerasReady) ? "Searching for cameras"
        : (sourceMode == SRC_TETHER && tether != null) ? tether.status
        : (inputError.length() > 0 ? inputError : "Waiting for image");
      text(msg, ix + iw / 2f, iy + ih / 2f);
    }
    drawTetherReticle();

    showDesktopPip = rawPipDesktop && !liveCropEdit && rawCameraImage() != null;
    if (showDesktopPip) {
      placeRawPip(ix, iy, iw, ih);
      badgeY = rawPipY + rawPipH + 6;
    }

    if (blackout || blackoutVisible()) tag(ix + 8, badgeY, "BLACK");
    else if (drawModeOn()) {
      String tagDraw;
      if (luckyPadLive()) {
        tagDraw = drawTouching ? "DRAW  ·  LuckyPad" : "DRAW  ·  LuckyPad ready";
      } else if (drawTrackpadMode) {
        tagDraw = drawPadFingerDown || drawTouching ? "DRAW  ·  trackpad" : "DRAW  ·  touch pad";
      } else {
        tagDraw = drawTouching ? "DRAW" : "DRAW  ·  click & drag";
      }
      tag(ix + 8, badgeY, tagDraw);
    }
    else if (sourceMode == SRC_TETHER && tetherFocusAssist && liveValid) tag(ix + 8, badgeY, "TAP FOCUS");
    else if (stopPlaying && hasStop()) tag(ix + 8, badgeY, "STOP " + (stopHead() + 1) + "/" + stopCount());
    else if (liveFreezeOnMonitor()) tag(ix + 8, badgeY, "LIVE FREEZE");
    else if (liveCropEdit) tag(ix + 8, badgeY, "CROP");
    else if (liveCropActive()) tag(ix + 8, badgeY, "CROPPED");

    drawLiveCropOverlay();

    // Global active-FX strip (bottom of preview).
    String fxLine = fxHudLine();
    if (fxLine.length() > 0) {
      fill(0, 140);
      noStroke();
      float fxPad = 8;
      ui(11);
      float tw = textWidth(fxLine) + fxPad * 2;
      float th = 22;
      float tx = ix + 8;
      float ty = iy + ih - th - 8;
      rect(tx, ty, min(tw, iw - 16), th);
      fill(PAPER);
      textAlign(LEFT, CENTER);
      text(fitText(fxLine, iw - 32), tx + fxPad, ty + th * 0.5f);
    }
  }

  // Text fields sit on the live image. On air also goes to Syphon / beamer.
  drawTextOverlay(ix, iy, iw, ih);

  if (blackoutVisible()) {
    noStroke();
    fill(0, constrain(round(blackoutAmt * 255), 0, 255));
    rect(ix, iy, iw, ih);
  }

  // Operator overlay only. Record samples the graded bus before this is drawn.
  if (showDesktopPip) drawRawPipDesktop();

  float barY = iy + ih + 8;
  drawBar(ix, barY, iw);
  color sc = MUTED;
  if (mode == MODE_REC) sc = REC;
  else if (mode == MODE_PLAY) sc = PLAY;
  else if (stopModeOn() && stopPlaying) sc = PLAY;
  fill(sc);
  textAlign(LEFT, CENTER);
  ui(10);
  text(fitText(statusLine(), iw * 0.72f), ix, barY + 14);
  if (millis() < hudNoteUntil) {
    fill(PLAY);
    textAlign(RIGHT, CENTER);
    text(fitText(hudNote, iw * 0.28f), ix + iw, barY + 14);
  }
  if (timelineH > 0) drawStopTimeline(ix, barY + 22, iw, 22);
  drawFooter(x + 16, y + h - footH, w - 32);
}

/** Frame strip for Stoptrick — click to scrub. */
void drawStopTimeline(float x, float y, float w, float h) {
  int n = stopCount();
  noStroke();
  fill(WELL);
  rect(x, y, w, h);
  if (n <= 0) {
    fill(DIM);
    textAlign(LEFT, CENTER);
    ui(10);
    text(stopModeOn() ? "No frames  ·  Enter shoots" : "No frames", x + 10, y + h / 2f);
    return;
  }
  int head = stopHead();
  float gap = 2;
  float cell = min(28, (w - 8 - gap * (n - 1)) / n);
  if (cell < 6) cell = max(4, (w - 8) / n);
  float total = n * cell + (n - 1) * gap;
  float start = x + 4;
  if (total > w - 8) {
    // Keep playhead visible when many frames.
    float view = w - 8;
    float playX = head * (cell + gap);
    start = x + 4 - constrain(playX - view * 0.5f, 0, max(0, total - view));
  }
  for (int i = 0; i < n; i++) {
    float cx = start + i * (cell + gap);
    if (cx + cell < x || cx > x + w) continue;
    hit("stop#" + i, max(x, cx), y + 4, min(cell, x + w - cx), h - 8);
    boolean on = i == head;
    boolean sel = !stopPlaying && stopHold == i;
    noStroke();
    fill(on ? (stopPlaying ? PLAY : ACCENT) : (sel ? INK : LINE));
    rect(cx, y + 6, cell, h - 12);
    if (cell >= 14) {
      fill(on || sel ? #101012 : MUTED);
      textAlign(CENTER, CENTER);
      ui(9);
      text(str(i + 1), cx + cell / 2f, y + h / 2f - 1);
    }
  }
  fill(DIM);
  textAlign(RIGHT, CENTER);
  ui(10);
  text((head + 1) + " / " + n, x + w - 6, y + h / 2f);
}

void regMarks(float x, float y, float w, float h, color c) {
  stroke(c);
  strokeWeight(1);
  int m = 8;
  line(x - 6, y, x - 6, y + m);
  line(x - 6, y, x - 6 + m, y);
  line(x + w + 6, y, x + w + 6 - m, y);
  line(x + w + 6, y, x + w + 6, y + m);
  line(x - 6, y + h, x - 6 + m, y + h);
  line(x - 6, y + h, x - 6, y + h - m);
  line(x + w + 6, y + h, x + w + 6 - m, y + h);
  line(x + w + 6, y + h, x + w + 6, y + h - m);
}

void tag(float x, float y, String s) {
  ui(10);
  fill(INK);
  textAlign(LEFT, CENTER);
  text(s, x, y + 8);
}

String statusLine() {
  if (mode == MODE_REC) {
    float sec = hapRec.recordedFrames() / (float) max(1, capFps);
    if (recFromStop) {
      if (lengthLocked()) {
        float len = lockedFrames / (float) max(1, capFps);
        return "Bake stoptrick  " + fmtSec(sec) + " / " + fmtSec(len) + "  ·  Bake cancels";
      }
      return "Bake stoptrick  " + fmtSec(sec) + "    Bake again locks length";
    }
    if (lengthLocked()) {
      float len = lockedFrames / (float) max(1, capFps);
      return "Overdub  " + fmtSec(sec) + " / " + fmtSec(len) + "  ·  layer " + (layerCount() + 1) + "  ·  Space cancels";
    }
    return "Recording  " + fmtSec(sec) + "    Space locks length  ·  max " + MAX_SECONDS + " s";
  }
  if (mode == MODE_PLAY && hasLoop()) {
    if (recWait) return stopIsRecordSource()
      ? "Waiting for loop start — bake stoptrick"
      : "Waiting for loop start — overdub same length";
    float pos = currentHead() / (float) capFps;
    float len = loopFrames / (float) capFps;
    int takes = undoHist.size() + layerCount();
    String base = fmtSec(pos) + " / " + fmtSec(len) + "    " + takes + " take" + (takes == 1 ? "" : "s");
    if (flattenBusy) base += "  ·  baking…";
    else if (flattenIncoming != null) base += "  ·  fade";
    else if (layerCount() > 1) base += "  ·  " + layerCount() + " play";
    if (hasStop()) base += "  ·  stop " + stopCount() + (stopPlaying ? " ▶" : "");
    return base;
  }
  if (archiveBusy && !hasLoop() && exportStatus != null && exportStatus.length() > 0) return exportStatus;
  if (stopModeOn()) {
    if (!hasStop()) return "Stoptrick  ·  Enter shoots  ·  Space plays";
    return "Stoptrick  " + (stopHead() + 1) + "/" + stopCount() + " @ " + stopFps + " fps"
      + (stopPlaying ? " ▶" : "  ‖")
      + "  ·  Enter shoot  ·  Space play  ·  C clears frames";
  }
  if (drawModeOn()) {
    return "Draw  ·  Space plays"
      + (stopPlaying ? " ▶" : "")
      + (hasStop() ? ("  ·  " + stopCount() + "f") : "");
  }
  if (hasStop()) {
    return "Stoptrick stack  " + stopCount() + "  ·  switch to Stoptrick mode";
  }
  if (!projectOpen) return "File → New Project…  (required before recording)";
  if (lengthLocked()) return "Length locked  " + fmtSec(lockedFrames / (float) capFps) + "  ·  Space overdubs  ·  X X clears";
  return "Space records and sets loop length";
}

/** Loop-history ticks strung left→right above the preview. */
void drawLayerTicks(float x, float cy) {
  int n = layerCount();
  int show = min(12, n);
  boolean overflow = n > show;
  float pitch = 6;
  float tickH = 10;
  float y = cy - tickH * 0.5f;
  int shown = activeLayer;
  if (shown < 0 && n > 0) shown = n - 1;

  noStroke();
  int col = 0;
  for (int i = 0; i < show; i++) {
    float tx = x + col * pitch;
    boolean on = i <= shown;
    boolean top = i == shown;
    boolean sel = selectedLayer == i;
    float tw = sel ? 2.5f : (top ? 2 : 1.5f);
    float th = sel ? tickH : (top ? tickH - 1 : tickH - 3);
    hit("lay#" + i, tx - 2, y - 2, pitch + 2, tickH + 4);
    fill(sel ? PAPER : (on ? PLAY : DIM));
    rect(tx, y + (tickH - th) * 0.5f, tw, th);
    col++;
  }
  if (show == 0) {
    fill(DIM);
    rect(x, y + 2, 1.5f, tickH - 4);
    col = 1;
  }
  if (overflow) {
    float tx = x + col * pitch;
    fill(MUTED);
    rect(tx, y + 3, 1.5f, tickH - 6);
    col++;
  }

  float sx = x + col * pitch;
  boolean stopSel = selectedLayer == SEL_STOP;
  boolean stopOn = hasStop();
  hit("lay#stop", sx - 2, y - 2, pitch + 2, tickH + 4);
  fill(stopSel ? PAPER : (stopOn ? (stopPlaying ? REC : PLAY) : DIM));
  rect(sx, y + (stopSel ? 0 : 1.5f), stopSel ? 2.5f : 2, stopSel ? tickH : tickH - 3);
  col++;

  float lx = x + col * pitch;
  boolean liveSel = selectedLayer == -1;
  hit("lay#live", lx - 2, y - 2, pitch + 2, tickH + 4);
  fill(liveSel ? PAPER : ACCENT);
  rect(lx, y + (liveSel ? 0 : 1), liveSel ? 2.5f : 2, liveSel ? tickH : tickH - 2);
}

/** Top-right mix chrome: FX affect · CROP · LOOP / LIVE opacity + blend toggle. */
void drawPreviewMixChrome(float ix, float cy, float iw) {
  ui(10);
  boolean screen = shownBlend() == BLEND_SCREEN;
  String blendLab = screen ? "SCR" : "MUL";
  float blendW = textWidth(blendLab) + 14;
  String cropLab = "CROP";
  float cropW = textWidth(cropLab) + 14;
  String fxLiveLab = "FX LIVE";
  String fxLoopLab = "FX LOOP";
  float fxLiveW = textWidth(fxLiveLab) + 14;
  float fxLoopW = textWidth(fxLoopLab) + 14;
  // Own ids (sl-mix-*) so FX-panel sl-opac / sl-loop-opac don't steal the drag geometry.
  float faderW = min(110, max(78, iw * 0.16f));
  float gap = 10;
  float block = fxLiveW + gap + fxLoopW + gap + cropW + gap + faderW + gap + faderW + gap + blendW;
  float x = ix + iw - block;
  float hy = cy - 8;

  drawFxAffectToggle("fx-affect-live", fxLiveLab, x, cy, hy, fxLiveW, fxAffectLive, ACCENT);
  x += fxLiveW + gap;
  drawFxAffectToggle("fx-affect-loop", fxLoopLab, x, cy, hy, fxLoopW, fxAffectLoop, PLAY);
  x += fxLoopW + gap;

  // CROP left of LOOP.
  boolean cropHot = liveCropEdit || (mouseX >= x && mouseX < x + cropW && mouseY >= hy && mouseY < hy + 16);
  boolean cropOn = liveCropEdit || liveCropActive();
  noStroke();
  fill(liveCropEdit ? ACCENT : (cropOn ? WELL : (cropHot ? WELL : CARD)));
  rect(x, hy, cropW, 16, 2);
  fill(liveCropEdit ? PAPER : (cropOn ? ACCENT : SIGNAL));
  textAlign(CENTER, CENTER);
  ui(10);
  text(cropLab, x + cropW * 0.5f, cy - 1);
  hit("live-crop", x, hy, cropW, 16);
  x += cropW + gap;

  drawMixFaderInline("sl-mix-loop", "sl-loop-opac", "LOOP", x, cy, faderW, loopOpacity, PLAY);
  x += faderW + gap;
  drawMixFaderInline("sl-mix-live", "sl-opac", "LIVE", x, cy, faderW, liveOpacity, ACCENT);
  x += faderW + gap;

  boolean blendHot = mouseX >= x && mouseX < x + blendW && mouseY >= hy && mouseY < hy + 16;
  noStroke();
  fill(screen ? SIGNAL : (blendHot ? WELL : CARD));
  rect(x, hy, blendW, 16, 2);
  fill(screen ? PAPER : SIGNAL);
  textAlign(CENTER, CENTER);
  ui(10);
  text(blendLab, x + blendW * 0.5f, cy - 1);
  hit("mix-blend", x, hy, blendW, 16);
  mapTarget("blend", x, hy, blendW, 16);
}

void drawFxAffectToggle(String id, String lab, float x, float cy, float hy, float w, boolean on, color hot) {
  boolean hover = mouseX >= x && mouseX < x + w && mouseY >= hy && mouseY < hy + 16;
  noStroke();
  if (on) fill(hot, 210);
  else fill(hover ? WELL : CARD);
  rect(x, hy, w, 16, 2);
  fill(on ? PAPER : SIGNAL);
  textAlign(CENTER, CENTER);
  ui(10);
  text(lab, x + w * 0.5f, cy - 1);
  hit(id, x, hy, w, 16);
  mapTarget(id, x, hy, w, 16);
}

/** Upper-left inset: full cam grade, no FX. Never into the recorded frame. */
void drawRawPipDesktop() {
  PImage raw = desktopPipImage();
  if (raw == null || rawPipW < 8 || rawPipH < 8) return;
  pushStyle();
  blendMode(BLEND);
  noTint();
  imageMode(CORNER);
  noStroke();
  fill(0);
  rect(rawPipX, rawPipY, rawPipW, rawPipH);
  image(raw, rawPipX, rawPipY, rawPipW, rawPipH);
  noFill();
  stroke(255, 210);
  strokeWeight(1);
  rect(rawPipX + 0.5f, rawPipY + 0.5f, rawPipW - 1, rawPipH - 1);
  noStroke();
  ui(10);
  String lab = "raw-preview";
  float tw = textWidth(lab) + 10;
  fill(0, 150);
  rect(rawPipX, rawPipY, tw, 16);
  fill(255);
  textAlign(LEFT, CENTER);
  text(lab, rawPipX + 5, rawPipY + 8);
  popStyle();
}

/**
 * Preview live layer at screen rect. Same opacity semantics as drawLiveLayerInto
 * (after Live FX; soft Mul/Scr = bake then lerp).
 */
void previewLiveLayer(float ix, float iy, float iw, float ih, PImage loopBase, PImage liveSrc, int alpha) {
  if (liveSrc == null || alpha <= 0) return;
  int lb = liveMixBlend();
  boolean softBlend = alpha < 255 && lb != BLEND_NORMAL && loopBase != null;
  blendMode(BLEND);
  noTint();
  if (softBlend) {
    liveMixGfx = ensureFrame(liveMixGfx);
    liveMixGfx.beginDraw();
    liveMixGfx.background(0);
    liveMixGfx.blendMode(BLEND);
    liveMixGfx.noTint();
    liveMixGfx.image(loopBase, 0, 0, capW, capH);
    liveMixGfx.blendMode(lb == BLEND_SCREEN ? SCREEN : MULTIPLY);
    liveMixGfx.image(liveSrc, 0, 0, capW, capH);
    liveMixGfx.blendMode(BLEND);
    liveMixGfx.noTint();
    liveMixGfx.endDraw();
    tint(255, alpha);
    image(liveMixGfx, ix, iy, iw, ih);
    noTint();
    return;
  }
  if (lb == BLEND_NORMAL) blendMode(BLEND);
  else blendMode(lb == BLEND_SCREEN ? SCREEN : MULTIPLY);
  if (alpha < 255) tint(255, alpha);
  image(liveSrc, ix, iy, iw, ih);
  noTint();
  blendMode(BLEND);
}

/** Compact opacity fader. Track drags; label toggles 0 ↔ 100. */
void drawMixFaderInline(String hitId, String mapId, String lab, float x, float cy, float w, float v, color lit) {
  float hy = cy - 8;
  float u = constrain(v, 0, 1);
  boolean hot = dragSlider != null && dragSlider.equals(hitId);
  fill(hot || v > 0.001f ? lit : MUTED);
  textAlign(LEFT, CENTER);
  ui(9);
  text(lab, x, cy);
  float labW = textWidth(lab) + 6;
  // Label click = mute/unmute (not a slider hit — avoids snap-to-0).
  String togId = hitId.equals("sl-mix-loop") ? "mix-loop-tog" : "mix-live-tog";
  hit(togId, x - 2, hy, labW, 16);
  float trackX = x + labW;
  float trackW = max(28, w - labW);
  float trackY = cy - 1;
  noStroke();
  fill(WELL);
  rect(trackX, trackY, trackW, 2);
  fill(hot ? lit : INK);
  rect(trackX, trackY, max(2, trackW * u), 2);
  float tx = trackX + trackW * u;
  fill(INK);
  rect(tx - 1, trackY - 3, 2, 8);
  slds.add(new Sld(hitId, trackX, trackY, trackW, 0, 1, false));
  hit(hitId, trackX, hy, trackW, 16);
  // Full chrome width so MAP picking hits label + track.
  mapTarget(mapId, x - 2, hy, w + 4, 16);
}

void drawBar(float x, float y, float w) {
  float bh = 4;
  float top = y - bh / 2f;
  noStroke();
  fill(WELL);
  rect(x, top, w, bh);
  // Dub-arm blink: pulse color only — keep the playhead length steady.
  boolean waitFlash = recWait && (millis() / 160) % 2 == 0;
  if (mode == MODE_REC) {
    int target = max(1, recTargetFrames());
    float t = constrain(hapRec.recordedFrames() / (float) target, 0, 1);
    fill(REC);
    rect(x, top, max(2, w * t), bh);
  } else if (hasLoop() && mode == MODE_PLAY) {
    float t = constrain(currentHead() / (float) loopFrames, 0, 1);
    fill(waitFlash ? PAPER : PLAY);
    rect(x, top, max(2, w * t), bh);
  } else if (recWait) {
    fill(waitFlash ? PAPER : PLAY);
    rect(x, top, w, bh);
  } else if (lengthLocked() && lockedFrames > 0) {
    stroke(DIM);
    strokeWeight(1);
    line(x, top + bh * 0.5f, x + w, top + bh * 0.5f);
    noStroke();
  }
}

// —— Keyboard mirror: FX (asdf…) + perf (yxcv…) only ——————————————

String[] kbPerfKeys() {
  return new String[] {"Y", "X", "C", "V", "B", "N", "M", ",", ".", "-"};
}
String[] kbPerfIds() {
  return new String[] {
    "k-undo", "k-clear", "k-frames", "k-live", "k-black", "k-blend", "k-play", "k-step-back", "k-step-fwd", "k-dash"
  };
}
String[] kbPerfLabs() {
  String undoLab = undoHist.isEmpty() && !hasLoop() ? "UNDO" : ("UND" + undoHist.size());
  if (drawModeOn()) undoLab = drawUndoStack.isEmpty() ? "UNDO" : ("UND" + drawUndoStack.size());
  else if (stopModeOn()) undoLab = "POP";
  String playLab = stopPlaying ? "HOLD" : "PLAY";
  String dash = "—";
  if (stopModeOn() || drawModeOn()) {
    if (mode == MODE_REC && recFromStop) dash = lengthLocked() ? "CANCEL" : "LOCK";
    else if (recWait && stopIsRecordSource()) dash = "CANCEL";
    else dash = "BAKE";
  }
  return new String[] {
    undoLab, "CLEAR", "FRMS",
    liveInOutput ? "LIVE" : "FRZ", "BLACK",
    blendLabel().toUpperCase(), playLab, "PREV", "NEXT", dash
  };
}
boolean[] kbPerfHot() {
  return new boolean[] {
    false,
    clearArm > 0 && millis() - clearArm < 900,
    false,
    !liveInOutput,
    blackout,
    false,
    stopPlaying,
    false, false,
    (stopModeOn() || drawModeOn()) && mode == MODE_REC && recFromStop
  };
}

String spaceActionLab() {
  // FX view: same labels as Live (record), even if Stop/Draw work-mode is underneath.
  if ((stopModeOn() || drawModeOn()) && !textPlaceRecords() && !fxViewOn()) return stopPlaying ? "HOLD" : "PLAY";
  if (recWait) return "WAIT";
  if (mode == MODE_REC) return lengthLocked() ? "CANCEL" : "LOCK";
  if (mode == MODE_PLAY) return "DUB";
  return "REC";
}

boolean spaceActionHot() {
  if ((stopModeOn() || drawModeOn()) && !textPlaceRecords() && !fxViewOn()) return stopPlaying;
  return mode == MODE_REC || mode == MODE_PLAY || recWait;
}

color spaceActionColor() {
  if (mode == MODE_REC) return REC;
  if ((stopModeOn() || drawModeOn()) && !textPlaceRecords() && !fxViewOn() && stopPlaying) return PLAY;
  if (mode == MODE_PLAY) return PLAY;
  return INK;
}

/**
 * Vector brand mark: closed loop + magic spark.
 * Drawn procedurally so it stays sharp at any density (no bitmap knock-out).
 */
void drawBrandMark(float x, float y, float s) {
  pushStyle();
  pushMatrix();
  translate(x + s * 0.5f, y + s * 0.5f);
  float sw = max(1.5f, s * 0.11f);
  noFill();
  strokeCap(ROUND);
  strokeJoin(ROUND);

  // Loop ring
  stroke(INK, 235);
  strokeWeight(sw);
  ellipse(0, s * 0.05f, s * 0.72f, s * 0.64f);

  // Magic cut — warm arc through the ring
  stroke(PLAY);
  strokeWeight(sw * 0.9f);
  arc(0, s * 0.05f, s * 0.72f, s * 0.64f, -PI * 0.12f, PI * 0.62f);

  // Spark at the knot
  float sx = s * 0.30f;
  float sy = -s * 0.28f;
  float r = s * 0.19f;
  noStroke();
  fill(PLAY);
  beginShape();
  for (int i = 0; i < 8; i++) {
    float a = -HALF_PI + i * (TWO_PI / 8f);
    float rad = (i % 2 == 0) ? r : r * 0.34f;
    vertex(sx + cos(a) * rad, sy + sin(a) * rad);
  }
  endShape(CLOSE);
  fill(INK, 210);
  circle(sx + r * 0.85f, sy - r * 0.1f, max(1.2f, s * 0.05f));
  circle(sx - r * 0.15f, sy - r * 0.9f, max(1f, s * 0.038f));

  popMatrix();
  popStyle();
}

void drawBrandMark(PGraphics pg, float x, float y, float s) {
  if (pg == null) return;
  pg.pushStyle();
  pg.pushMatrix();
  pg.translate(x + s * 0.5f, y + s * 0.5f);
  float sw = max(1.5f, s * 0.11f);
  pg.noFill();
  pg.strokeCap(ROUND);
  pg.strokeJoin(ROUND);
  pg.stroke(INK, 235);
  pg.strokeWeight(sw);
  pg.ellipse(0, s * 0.05f, s * 0.72f, s * 0.64f);
  pg.stroke(PLAY);
  pg.strokeWeight(sw * 0.9f);
  pg.arc(0, s * 0.05f, s * 0.72f, s * 0.64f, -PI * 0.12f, PI * 0.62f);
  float sx = s * 0.30f;
  float sy = -s * 0.28f;
  float r = s * 0.19f;
  pg.noStroke();
  pg.fill(PLAY);
  pg.beginShape();
  for (int i = 0; i < 8; i++) {
    float a = -HALF_PI + i * (TWO_PI / 8f);
    float rad = (i % 2 == 0) ? r : r * 0.34f;
    pg.vertex(sx + cos(a) * rad, sy + sin(a) * rad);
  }
  pg.endShape(CLOSE);
  pg.fill(INK, 210);
  pg.circle(sx + r * 0.85f, sy - r * 0.1f, max(1.2f, s * 0.05f));
  pg.circle(sx - r * 0.15f, sy - r * 0.9f, max(1f, s * 0.038f));
  pg.popMatrix();
  pg.popStyle();
}

/** One keycap: glyph + label, optional lit fill. Compact 2-line. */
void drawKbKey(String glyph, String lab, String id, float x, float y, float w, float h, boolean on, color onCol) {
  hit(id, x, y, w, h);
  noStroke();
  if (on) {
    fill(onCol, 50);
    rect(x, y, w, h);
    stroke(onCol);
    strokeWeight(1);
    noFill();
    rect(x + 0.5f, y + 0.5f, w - 1, h - 1);
    noStroke();
    fill(onCol);
  } else {
    fill(WELL);
    rect(x, y, w, h);
    fill(DIM);
  }
  textAlign(CENTER, CENTER);
  // Tall ISO return: keep glyph+label as a tight pair in the middle.
  float gy = h > w * 1.4f ? y + h * 0.42f : y + h * 0.32f;
  float ly = h > w * 1.4f ? y + h * 0.58f : y + h * 0.72f;
  ui(13);
  text(glyph, x + w * 0.5f, gy);
  fill(on ? INK : MUTED);
  ui(11);
  text(fitText(lab, w - 3), x + w * 0.5f, ly);
}

/**
 * Visible keyboard: FX (Q + A rows) + performance.
 * Modes stay on 1–5 (no chrome).
 *   Q W E R T Z U I O P Ü +
 *   A S D F G H J K L Ö Ä # ┃
 *    Y X C V B N M , . -    ┃ ENT (tall, ISO return)
 *           [   SPACE   ]
 */
void drawFxKbRow(ArrayList<FxUnit> stack, int start, float origin, float y, float pitch, float cw, float rowH) {
  boolean mapping = fxKeyMapFrom >= 0;
  for (int i = 0; i < 12; i++) {
    int idx = start + i;
    int slot = fxSlotForKey(idx);
    boolean on = false;
    boolean sel = slot >= 0 && fxFocus == slot;
    boolean mapSrc = mapping && fxKeyForSlot(fxKeyMapFrom) == idx;
    String stateLab = slot >= 0 && slot < FX_RACK.length ? fxShortName(FX_RACK[slot]) : "";
    if (slot >= 0 && slot < stack.size()) {
      FxUnit u = stack.get(slot);
      on = u.on || u.fade > 0.08f;
      if (!u.on && u.fade > 0.08f) stateLab = "…";
      else stateLab = fxShortName(u.type);
    }
    boolean any = on;
    float kx = origin + i * pitch;
    // Click selects; double toggles; triple resets. While mapping, click assigns the key.
    hit("fx-kb#" + idx, kx, y, cw, rowH);
    noStroke();
    if (mapSrc) fill(MAP, on ? 64 : 42);
    else if (sel && on) fill(PLAY, 100);
    else if (sel) fill(ACCENT, 42);
    else if (on) fill(PLAY, 82);
    else if (mapping) fill(MAP, 18);
    else fill(WELL);
    rect(kx, y, cw, rowH);
    if (mapSrc || sel || on || mapping) {
      if (mapSrc) stroke(MAP);
      else if (mapping) stroke(MAP, 170);
      else if (sel) stroke(INK);
      else stroke(PLAY);
      strokeWeight(mapSrc || sel ? 1.6f : (on ? 1.4f : 1));
      noFill();
      rect(kx + 0.5f, y + 0.5f, cw - 1, rowH - 1);
      noStroke();
    }
    textAlign(CENTER, CENTER);
    ui(13);
    fill(mapSrc ? MAP : (sel || on ? INK : (any ? MUTED : DIM)));
    text(fxKeyLabel(idx), kx + cw * 0.5f, y + rowH * 0.38f);
    fill(mapSrc ? MAP : (on ? PLAY : (sel ? INK : MUTED)));
    ui(11);
    text(stateLab, kx + cw * 0.5f, y + rowH * 0.76f);
    mapTarget("fx-" + idx, kx, y, cw, rowH);
  }
}

void drawFooter(float x, float y, float w) {
  ensureAllFxRacks();
  float gap = 2;
  float rowH = 28;
  float spaceH = 24;
  float rowGap = 3;
  // 12 letter columns + ISO return column to the right of ÖÄ#.
  float pitch = w / 13.5f;
  float cw = pitch - gap;
  float enterW = cw * 1.15f;
  float boardW = 12 * pitch + gap + enterW;
  float origin = x + max(0, (w - boardW) * 0.5f);
  float offY = 0.5f * pitch;
  float boardH = rowH * 3 + spaceH + rowGap * 3;

  // Whole keyboard becomes a map bar in MIDI map mode.
  if (midiMapMode) {
    noStroke();
    fill(MAP, 36);
    rect(origin - 6, y - 6, boardW + 12, boardH + 10, 4);
    stroke(MAP, 160);
    strokeWeight(1);
    noFill();
    rect(origin - 6.5f, y - 6.5f, boardW + 13, boardH + 11, 4);
    noStroke();
    fill(MAP);
    ui(10);
    textAlign(LEFT, BOTTOM);
    text("MAP", origin - 2, y - 8);
  }

  ArrayList<FxUnit> stack = fxActiveStack();
  drawFxKbRow(stack, 0, origin, y, pitch, cw, rowH);
  float yA = y + rowH + rowGap;
  drawFxKbRow(stack, 12, origin, yA, pitch, cw, rowH);

  // PERF
  float y1 = yA + rowH + rowGap;
  String[] perfK = kbPerfKeys();
  String[] perfIds = kbPerfIds();
  String[] perfLabs = kbPerfLabs();
  boolean[] perfHot = kbPerfHot();
  for (int i = 0; i < 10; i++) {
    float kx = origin + offY + i * pitch;
    color lit = ACCENT;
    if (perfIds[i].equals("k-live") && perfHot[i]) lit = PLAY;
    if (perfIds[i].equals("k-play") && perfHot[i]) lit = PLAY;
    if (perfIds[i].equals("k-black") && perfHot[i]) lit = REC;
    if (perfIds[i].equals("k-clear") && perfHot[i]) lit = REC;
    drawKbKey(perfK[i], perfLabs[i], perfIds[i], kx, y1, cw, rowH, perfHot[i], lit);
    String bind = bindForHit(perfIds[i]);
    if (bind != null) mapTarget(bind, kx, y1, cw, rowH);
  }

  // ENTER — tall ISO return, right of ÖÄ# (spans A-row + perf row).
  float enterX = origin + 12 * pitch + gap;
  float enterH = rowH * 2 + rowGap;
  String enterLab = (stopModeOn() || drawModeOn()) ? "SHOOT" : "LAYER";
  drawKbKey("ENT", enterLab, "k-enter", enterX, yA, enterW, enterH, false, ACCENT);
  if (stopModeOn() || drawModeOn()) mapTarget("stop-shoot", enterX, yA, enterW, enterH);
  else mapTarget("k-enter", enterX, yA, enterW, enterH);

  // SPACE (bottom row, centered under letter keys — no enter beside it)
  float y2 = y1 + rowH + rowGap;
  float yRowLeft = origin + offY;
  float yRowRight = yRowLeft + 10 * pitch - gap;
  float spaceW = 5.5f * pitch - gap;
  float spaceX = (yRowLeft + yRowRight) * 0.5f - spaceW * 0.5f;
  boolean spHot = spaceActionHot();
  drawKbKey("SPC", spaceActionLab(), "k-space", spaceX, y2, spaceW, spaceH, spHot, spaceActionColor());
  mapTarget("k-space", spaceX, y2, spaceW, spaceH);
}

/** Full-bleed letterbox for the external program out. */
public void layoutOutputStage(float winW, float winH, int contentW, int contentH) {
  float aspect = contentW / (float) max(1, contentH);
  float dw = winW;
  float dh = dw / aspect;
  if (dh > winH) {
    dh = winH;
    dw = dh * aspect;
  }
  beamerStageW = dw;
  beamerStageH = dh;
  beamerStageX = (winW - dw) * 0.5f;
  beamerStageY = (winH - dh) * 0.5f;
}

float drawSourceBlock(float x, float cy, float w) {
  kicker("SOURCE", x, cy, w);
  cy += 12;
  int srcSeg = sourceMode == SRC_CAM ? 0
    : sourceMode == SRC_SYPHON ? 1
    : sourceMode == SRC_TETHER ? 2
    : 3;
  segments(new String[] {"src-cam", "src-syphon", "src-tether", "src-test"},
    new String[] {"Webcam", "Syphon", "Tether", "Test"}, srcSeg, x, cy, w, 24);
  mapTarget("src", x, cy, w, 24);
  cy += 30;

  if (sourceMode == SRC_TETHER) {
    cy = drawTetherBlock(x, cy, w);
  } else if (sourceMode == SRC_SYPHON || sourceMode == SRC_CAM) {
    String fadeVal = inputFadeMs < 1 ? "Off" : round(inputFadeMs) + " ms";
    cy = sliderRow("sl-input-fade", "Switch fade", fadeVal, x, cy, w, inputFadeMs, 0, 1500);
    cy += 6;
    kicker("AVAILABLE", x, cy, w);
    cy += 10;
    int total = camEntries.size() + syEntries.size();
    if (total == 0) {
      fill(MUTED);
      ui(11);
      textAlign(LEFT, TOP);
      String msg = camerasScanning || !camerasReady
        ? "Searching for inputs…"
        : "No inputs found. Connect iPhone or start Syphon, then Refresh.";
      text(msg, x, cy, w, 40);
      cy += 44;
    } else {
      cy = drawInputsGrid(x, cy, w);
    }
    button("refresh-inputs", camerasScanning ? "Refreshing…" : "Refresh", x, cy, w, 24, camerasScanning);
    cy += 32;
  } else {
    kicker("PATTERN", x, cy, w);
    cy += 10;
    float patY = cy;
    cy = drawTestGrid(x, cy, w);
    mapTarget("testpat", x, patY, w, cy - patY);
  }

  if (inputError.length() > 0 && sourceMode != SRC_TEST) {
    fill(DUB);
    ui(10);
    textAlign(LEFT, TOP);
    text(inputError, x, cy, w, 28);
    cy += 32;
  }
  return cy + 8;
}

float drawTetherBlock(float x, float cy, float w) {
  kicker("IPHONE TETHER", x, cy, w);
  cy += 14;
  fill(MUTED);
  ui(11);
  textAlign(LEFT, TOP);
  String st = tether == null ? "Off" : tether.status;
  if (tether != null && tether.connected) {
    int tw = tether.frameW > 1 ? tether.frameW : 1920;
    int th = tether.frameH > 1 ? tether.frameH : 1080;
    long seq = tether.frameSeq.get();
    st = "LIVE · " + tw + "×" + th + " · f" + seq + " · ISO " + tether.iso;
    if (!tetherAutoFocus || !tetherAutoExposure) {
      st += " · ";
      if (!tetherAutoFocus) st += "AF lock";
      if (!tetherAutoFocus && !tetherAutoExposure) st += " · ";
      if (!tetherAutoExposure) st += "AE lock";
    }
  }
  text(st, x, cy, w, 28);
  cy += 30;

  fill(MUTED);
  textAlign(LEFT, CENTER);
  text("Lens", x, cy + 12);
  String[] lensIds = {"tether-cam#0", "tether-cam#1", "tether-cam#2"};
  String[] lensLabs = {"0.5×", "1×", "2×"};
  float sw = min(w * 0.62f, 140);
  float lx = x + w - sw;
  // segments() highlights by index; disable unavailable by not selecting them via click guard
  segments(lensIds, lensLabs, constrain(tetherCam, 0, 2), lx, cy, sw, 24);
  float cw = sw / lensIds.length;
  for (int i = 0; i < lensIds.length; i++) mapTarget(lensIds[i], lx + i * cw, cy, cw, 24);
  cy += 32;
  // grey out unavailable in a subtle way via labels note
  boolean anyOff = !tetherLensEnabled(0) || !tetherLensEnabled(2);
  if (anyOff) {
    fill(MUTED);
    ui(10);
    textAlign(LEFT, TOP);
    text("Unavailable lenses stay inactive.", x, cy, w, 18);
    cy += 20;
  }

  cy = toggleRow("tether-exp-off", "tether-exp-on", "Auto exposure", tetherAutoExposure, x, cy, w);
  // EV bias works with continuous AE; keep it available either way.
  cy = sliderRow("sl-tether-bias", "Exposure", nf(tetherBias, 1, 1) + " EV", x, cy, w, tetherBias, -2, 2);
  cy = toggleRow("tether-foc-off", "tether-foc-on", "Auto focus", tetherAutoFocus, x, cy, w);
  if (!tetherAutoFocus) {
    cy = sliderRow("sl-tether-focus", "Focus", round(tetherFocus * 100) + "%", x, cy, w, tetherFocus, 0, 1);
  }
  check("tether-assist", "Focus assist — tap the stage", x, cy, w, tetherFocusAssist);
  cy += 28;
  fill(MUTED);
  ui(10);
  textAlign(LEFT, TOP);
  text("Stream is 1920×1080 H.264. LuckyTether on the iPhone (USB or same Wi‑Fi).", x, cy, w, 36);
  cy += 40;
  return cy;
}

float drawInputsGrid(float x, float cy, float w) {
  int cols = 2;
  float gap = 8;
  float tw = (w - gap) / cols;
  float th = tw * 9f / 16f + 22;
  int camN = camEntries.size();
  int syN = min(8, syEntries.size());
  int n = camN + syN;
  int rows = (n + cols - 1) / cols;
  for (int i = 0; i < n; i++) {
    int col = i % cols;
    int row = i / cols;
    float tx = x + col * (tw + gap);
    float ty = cy + row * (th + gap);
    if (i < camN) {
      CamEntry e = camEntries.get(i);
      boolean on = sourceMode == SRC_CAM && e.label.equals(cameraName);
      String badge = e.continuity ? "iPhone" : "Cam";
      drawSourceTile("cam#" + i, tx, ty, tw, th, e.shortLabel(), badge, on, on && liveValid);
    } else {
      int si = i - camN;
      SyEntry e = syEntries.get(si);
      boolean on = sourceMode == SRC_SYPHON && si == syIndex;
      drawSourceTile("sy#" + si, tx, ty, tw, th, e.label, "Syphon", on, on && liveValid);
    }
  }
  return cy + rows * (th + gap) + 4;
}

float drawTestGrid(float x, float cy, float w) {
  String[] patterns = {"Checkerboard", "Color bars", "Grid"};
  int cols = 2;
  float gap = 8;
  float tw = (w - gap) / cols;
  float th = tw * 9f / 16f + 22;
  for (int i = 0; i < patterns.length; i++) {
    int col = i % cols;
    int row = i / cols;
    float tx = x + col * (tw + gap);
    float ty = cy + row * (th + gap);
    boolean on = testPattern == i;
    drawSourceTile("test#" + i, tx, ty, tw, th, patterns[i], "Test", on, on && liveValid);
  }
  int rows = (patterns.length + cols - 1) / cols;
  return cy + rows * (th + gap) + 4;
}

void drawSourceTile(String id, float x, float y, float w, float h, String label, String badge, boolean on, boolean showLive) {
  if (!inClip(y, h)) return;
  hit(id, x, y, w, h);
  float mediaH = h - 22;
  noStroke();
  fill(WELL);
  rect(x, y, w, h, 6);
  if (on) {
    stroke(ACCENT);
    strokeWeight(1.5);
    noFill();
    rect(x + 0.75, y + 0.75, w - 1.5, h - 1.5, 6);
    noStroke();
  }

  float mx = x + 1;
  float my = y + 1;
  float mw = w - 2;
  float mh = mediaH - 1;
  if (showLive && sourceGfx != null && sourceGfx.width > 1) {
    drawTileCover(sourceGfx, mx, my, mw, mh);
  } else {
    fill(on ? #32323a : #242428);
    rect(mx, my, mw, mh);
    stroke(MUTED);
    strokeWeight(1.2);
    noFill();
    float cx = mx + mw / 2f;
    float cy = my + mh / 2f;
    float rw = min(mw, mh) * 0.28f;
    rect(cx - rw, cy - rw * 0.62f, rw * 2, rw * 1.24f, 3);
    ellipse(cx, cy, rw * 0.9f, rw * 0.9f);
    noStroke();
  }

  if (badge != null && badge.length() > 0) {
    ui(10);
    fill(on ? ACCENT : #3a3a44);
    float bw = textWidth(badge) + 10;
    rect(x + 6, y + 6, bw, 14, 3);
    fill(PAPER);
    textAlign(LEFT, CENTER);
    text(badge, x + 11, y + 12);
  }

  fill(on ? INK : MUTED);
  ui(10);
  textAlign(LEFT, CENTER);
  text(fitText(label, w - 12), x + 6, y + mediaH + 10);
}

void drawTileCover(PImage src, float x, float y, float w, float h) {
  if (src == null || src.width < 2 || src.height < 2 || w < 2 || h < 2) return;
  float s = max(w / (float) src.width, h / (float) src.height);
  float srcW = w / s;
  float srcH = h / s;
  float sx1 = (src.width - srcW) * 0.5f;
  float sy1 = (src.height - srcH) * 0.5f;
  image(src, x, y, w, h, (int) sx1, (int) sy1, (int) (sx1 + srcW), (int) (sy1 + srcH));
}

void paintGear(float x, float y, float w, float h, boolean on) {
  hit("gear", x, y, w, h);
  fill(on ? INK : MUTED);
  textAlign(CENTER, CENTER);
  ui(11);
  text("SET", x + w / 2f, y + h / 2f - 1);
  if (on) {
    stroke(ACCENT);
    strokeWeight(1);
    line(x + 2, y + h - 1, x + w - 2, y + h - 1);
    noStroke();
  }
}

void drawTabs(float x, float y, float w, float h) {
  String[] names = {"Input", "Layer", "Output"};
  float tw = w / names.length;
  for (int i = 0; i < names.length; i++) {
    float tx = x + i * tw;
    hit("tab-" + i, tx, y, tw, h);
    boolean on = inspectorTab == i;
    fill(on ? INK : MUTED);
    textAlign(CENTER, CENTER);
    ui(11);
    text(names[i], tx + tw / 2f, y + h / 2f - 1);
    if (on) {
      stroke(ACCENT);
      strokeWeight(1);
      line(tx + 8, y + h - 1, tx + tw - 8, y + h - 1);
      noStroke();
    }
  }
}

void drawInspector(float x, float y, float w, float h) {
  float ix = x + 20;
  float iw = w - 40;
  float cy = y + 16;
  float bottom = y + h - 20;
  // Anim modes stay pinned at the top of the right dock (not source / not Layer-only).
  if (inspectorTab == 3) {
    drawGlobalPanel(ix, cy, iw, bottom);
    return;
  }
  if (fxViewOn()) {
    drawEffectsPanel(ix, cy, iw, bottom);
    return;
  }
  if (outputEditOn()) {
    drawOutputPanel(ix, cy, iw, bottom);
    return;
  }
  if (notesViewOn()) {
    gradeScrollMax = 0;
    gradeScroll = 0;
    drawNotesPanel(ix, cy, iw, bottom);
    return;
  }
  // STOPTRICK / DRAW → mode tools only. LIVE → camera / input panel (no tip block).
  if (topMode == TOP_STOP || topMode == TOP_DRAW) {
    gradeScrollMax = 0;
    gradeScroll = 0;
    drawAnimBlock(ix, cy, iw);
    return;
  }
  drawCameraPanel(ix, cy, iw, bottom);
}

void drawEditField() {
  if (editId == null) return;
  noStroke();
  fill(WELL);
  stroke(ACCENT);
  strokeWeight(1);
  rect(editX, editY, editW, editH, 3);
  fill(INK);
  textAlign(CENTER, CENTER);
  ui(10);
  float ty = editY + editH / 2f - 1;
  text(editText, editX + editW / 2f, ty);
  if ((millis() / 480) % 2 == 0) {
    float cx = editX + editW / 2f + textWidth(editText) / 2f + 2;
    stroke(INK);
    strokeWeight(1);
    line(cx, editY + 3, cx, editY + editH - 3);
  }
  noStroke();
}

void drawMapFrames() {
  if (!midiMapMode) return;
  for (int i = 0; i < mapFrames.size(); i++) {
    MapFrame f = mapFrames.get(i);
    boolean sel = f.id != null && midiPickId != null && f.id.equals(midiPickId);
    String tag = mapFrameTag(f.id, sel);
    boolean mapped = tag.length() > 0 && !tag.equals("ARMED");
    // Topmost pick targets — inflated so selection is easy.
    hit("midi-pick#" + f.id, f.x - 3, f.y - 3, f.w + 6, f.h + 6);
    noStroke();
    if (sel) {
      float pulse = 0.62f + 0.28f * (0.5f + 0.5f * sin(millis() / 160f));
      fill(PLAY, (int) (255 * pulse));
      rect(f.x - 3, f.y - 3, f.w + 6, f.h + 6);
      stroke(INK);
      strokeWeight(2);
      noFill();
      rect(f.x - 3, f.y - 3, f.w + 6, f.h + 6);
      noStroke();
      drawMapNoteBadge(f.x, f.y, f.w, f.h, mapped ? tag : "ARMED", true);
    } else if (mapped) {
      fill(MAP, 64);
      rect(f.x, f.y, f.w, f.h);
      drawMapNoteBadge(f.x, f.y, f.w, f.h, tag, false);
    } else {
      stroke(MAP, 140);
      strokeWeight(1);
      noFill();
      rect(f.x + 0.5f, f.y + 0.5f, f.w - 1, f.h - 1);
      noStroke();
    }
  }
  noStroke();
}

/** Opaque note/CC chip on the map overlay (label always 100%). */
void drawMapNoteBadge(float x, float y, float w, float h, String tag, boolean sel) {
  if (tag == null || tag.length() == 0) return;
  ui(sel ? 12 : 11);
  float padX = sel ? 12 : 8;
  float tw = textWidth(tag) + padX;
  float bh = min(sel ? 20 : 18, max(14, h - (sel ? 2 : 6)));
  float bw = min(max(w - 2, tw), max(tw, sel ? 52 : 22));
  float bx = x + (w - bw) * 0.5f;
  float by = y + (h - bh) * 0.5f;
  noStroke();
  fill(sel ? #1a1408 : #0b0b0d, sel ? 240 : 200);
  rect(bx, by, bw, bh, 3);
  if (sel) {
    stroke(PLAY);
    strokeWeight(1);
    noFill();
    rect(bx + 0.5f, by + 0.5f, bw - 1, bh - 1, 3);
    noStroke();
  }
  fill(INK);
  textAlign(CENTER, CENTER);
  text(fitText(tag, bw - 4), bx + bw * 0.5f, by + bh * 0.5f - 1);
}

String mapFrameTag(String id, boolean sel) {
  MidiBind b = findBind(id);
  if (b != null && b.cc >= 0) return midiLabel(b.note, b.channel, b.cc);
  if (sel) return "ARMED";
  return "";
}

void drawMidiPanel(float x, float y, float w, float bottom) {
  float cy = y;
  kicker("MIDI", x, cy, w);
  cy += 12;
  if (midiNames.length == 0) {
    fill(MUTED);
    ui(11);
    textAlign(LEFT, TOP);
    String empty = "Searching for MIDI.";
    if (midiReady) {
      boolean present = false;
      try {
        present = midiNativeOn && MidiCtl.loaded && MidiCtl.sourceCount() > 0;
      } catch (Throwable t) {}
      empty = present
        ? "MIDI present — tap Search inputs."
        : "No input found. Plug in nanoKONTROL2, then Search.";
    }
    text(empty, x, cy, w, 24);
    cy += 28;
  }
  int n = min(8, midiNames.length);
  for (int i = 0; i < n; i++) {
    midiDeviceRow("midi-in#" + i, midiNames[i], x, cy, w, midiNames[i].equals(midiDeviceName));
    cy += 28;
  }
  fill(INK);
  ui(10);
  textAlign(LEFT, TOP);
  String st = midiStatus == null ? "" : midiStatus;
  if (midiNativeOn) st = (st.length() == 0 ? "Connected" : st);
  if (midiLastSeen > 0 && millis() - midiLastSeen < 1500) {
    st = st + "  ·  live";
  }
  text(fitText(st, w), x, cy, w, 16);
  cy += 20;
  button("midi-refresh", "Search inputs", x, cy, w, 24, false);
  cy += 34;
  fill(DIM);
  ui(10);
  textAlign(LEFT, TOP);
  text("Click a highlighted target, move a controller. MIDI again saves. Delete clears.", x, cy, w, 32);
  cy += 36;
  kicker("MAPPED", x, cy, w);
  cy += 12;
  int mapped = 0;
  for (int i = 0; i < midiBinds.size(); i++) if (midiBinds.get(i).cc >= 0) mapped++;
  if (mapped == 0) {
    fill(MUTED);
    ui(11);
    textAlign(LEFT, TOP);
    text("Nothing mapped yet.", x, cy, w, 20);
    return;
  }
  float listTop = cy;
  clipTop = listTop;
  clipBot = bottom;
  clip(x - 20, listTop, w + 40, max(1, bottom - listTop));
  float rowY = listTop - midiScroll;
  for (int i = 0; i < midiBinds.size(); i++) {
    MidiBind b = midiBinds.get(i);
    if (b.cc < 0 && !b.id.equals(midiPickId)) continue;
    drawMidiBind(b, x, rowY, w);
    rowY += 26;
  }
  float contentH = rowY - (listTop - midiScroll);
  midiScrollMax = max(0, contentH - (bottom - listTop) + 4);
  if (midiScroll > midiScrollMax) midiScroll = midiScrollMax;
  noClip();
  clipTop = -100000;
  clipBot = 100000;
  if (midiScrollMax > 1) {
    float trackH = max(1, bottom - listTop);
    float thumb = max(24, trackH * trackH / (trackH + midiScrollMax));
    float ty = listTop + (trackH - thumb) * (midiScroll / midiScrollMax);
    noStroke();
    fill(MAP, 90);
    rect(x + w + 8, ty, 4, thumb, 2);
  }
}

void midiDeviceRow(String id, String label, float x, float y, float w, boolean on) {
  hit(id, x, y, w, 26);
  noStroke();
  if (on) {
    fill(#16324f);
    rect(x, y, w, 26);
    fill(MAP);
    rect(x, y, 2, 26);
  }
  fill(on ? INK : MUTED);
  textAlign(LEFT, CENTER);
  ui(11);
  text(fitText(label, w - 16), x + 10, y + 13);
}

void drawMidiBind(MidiBind b, float x, float y, float w) {
  boolean armed = midiPickId != null && midiPickId.equals(b.id);
  if (midiMapMode && inClip(y, 24)) hit("midi-bind#" + b.id, x, y, w, 24);
  if (armed) {
    noStroke();
    fill(MAP, 128);
    rect(x, y, w, 24);
  }
  String tag = midiLabel(b.note, b.channel, b.cc);
  fill(armed ? INK : MUTED);
  ui(11);
  textAlign(LEFT, CENTER);
  text(fitText(b.label, w - textWidth(tag) - 24), x + 8, y + 12);
  textAlign(RIGHT, CENTER);
  fill(INK);
  text(tag, x + w - 8, y + 12);
}

void drawCameraPanel(float x, float y, float w, float bottom) {
  clipTop = y;
  clipBot = bottom;
  clip(x - 20, y, w + 40, bottom - y);
  float cy = y - gradeScroll;
  cy = drawSourceBlock(x, cy, w);
  if (sourceMode == SRC_CAM) cy = drawInputLock(x, cy, w);
  kicker("IMAGE", x, cy, w);
  cy += 16;
  segments(new String[] {"scale-fit", "scale-fill", "scale-1"}, new String[] {"Fit", "Fill", "1:1"}, camScale, x, cy, w, 24);
  mapTarget("scale", x, cy, w, 24);
  cy += 36;
  int rotIdx = camRotation / 90;
  if (rotIdx < 0 || rotIdx > 3) rotIdx = 0;
  segments(new String[] {"rot-0", "rot-90", "rot-180", "rot-270"}, new String[] {"0°", "90°", "180°", "270°"}, rotIdx, x, cy, w, 24);
  mapTarget("rot", x, cy, w, 24);
  cy += 36;
  // Framing unit: zoom + pan + mirror
  cy = sliderRow("sl-zoom", "Zoom", nf(camZoom, 1, 2) + "×", x, cy, w, camZoom, LIVE_ZOOM_MIN, LIVE_ZOOM_MAX);
  cy = sliderRow("sl-panx", "X", signedPct(camPanX), x, cy, w, camPanX, -3, 3);
  cy = sliderRow("sl-pany", "Y", signedPct(camPanY), x, cy, w, camPanY, -3, 3);
  cy = sliderRow("sl-feather", "Feather", str(round(liveFeather)), x, cy, w, liveFeather, 0, 100);
  check("mirror", "Mirror", x, cy, w, mirror);
  cy += 28;
  button("live-frame-reset", "Reset frame  ·  0", x, cy, w, 24, false);
  cy += 32;
  cy += 6;
  // Tone curves first — black/white handlers also move on X.
  cy = drawCurveEditor(x, cy, w);
  cy += 10;
  cy = faderBank("LIGHT",
    new String[] {"sl-expo", "sl-bril", "sl-high", "sl-shad", "sl-contrast", "sl-bright", "sl-black"},
    new String[] {"Exp", "Bril", "Hi", "Shad", "Cont", "Brit", "Blk"},
    new String[] {"Exposure", "Brilliance", "Highlights", "Shadows", "Contrast", "Brightness", "Black point"},
    new String[] {signedPct(camExposure), signedPct(camBrilliance), signedPct(camHighlights), signedPct(camShadows), signedPct(camContrast), signedPct(camBrightness), signedPct(camBlack)},
    new float[] {camExposure, camBrilliance, camHighlights, camShadows, camContrast, camBrightness, camBlack},
    new float[] {-1, -1, -1, -1, -1, -1, -1},
    new float[] {1, 1, 1, 1, 1, 1, 1},
    x, cy, w);
  cy += 8;
  cy = faderBank("COLOR",
    new String[] {"sl-sat", "sl-vib", "sl-warm", "sl-tint"},
    new String[] {"Sat", "Vib", "Warm", "Tint"},
    new String[] {"Saturation", "Vibrance", "Warmth", "Tint"},
    new String[] {signedPct(camSaturation), signedPct(camVibrance), signedPct(camWarmth), signedPct(camTint)},
    new float[] {camSaturation, camVibrance, camWarmth, camTint},
    new float[] {-1, -1, -1, -1},
    new float[] {1, 1, 1, 1},
    x, cy, w);
  cy += 8;
  cy = faderBank("DETAILS",
    new String[] {"sl-sharp", "sl-clar", "sl-noise", "sl-vig"},
    new String[] {"Sharp", "Def", "Noise", "Vign"},
    new String[] {"Sharpness", "Definition", "Noise reduction", "Vignette"},
    new String[] {str(round(camSharp * 100)), signedPct(camClarity), str(round(camNoise * 100)), signedPct(camVignette)},
    new float[] {camSharp, camClarity, camNoise, camVignette},
    new float[] {0, -1, 0, -1},
    new float[] {1, 1, 1, 1},
    x, cy, w);
  cy += 8;
  button("cam-reset", "Reset camera", x, cy, w, 24, false);
  cy += 24;
  float contentH = cy - (y - gradeScroll);
  gradeScrollMax = max(0, contentH - (bottom - y) + 4);
  if (gradeScroll > gradeScrollMax) gradeScroll = gradeScrollMax;
  noClip();
  clipTop = -100000;
  clipBot = 100000;
  if (gradeScrollMax > 1) {
    float trackH = bottom - y;
    float thumb = max(24, trackH * trackH / (trackH + gradeScrollMax));
    float ty = y + (trackH - thumb) * (gradeScroll / gradeScrollMax);
    noStroke();
    fill(ACCENT, 90);
    rect(x + w + 8, ty, 4, thumb, 2);
  }
}

float toggleRow(String offId, String onId, String label, boolean on, float x, float y, float w) {
  fill(MUTED);
  textAlign(LEFT, CENTER);
  ui(11);
  text(fitText(label, w - 140), x, y + 12);
  float sw = 128;
  segments(new String[] {offId, onId}, new String[] {"Off", "On"}, on ? 1 : 0, x + w - sw, y, sw, 24);
  return y + 32;
}

float drawInputLock(float x, float cy, float w) {
  kicker("CAMERA", x, cy, w);
  cy += 16;
  if (!CamCtl.loaded) {
    fill(MUTED);
    ui(11);
    textAlign(LEFT, TOP);
    text(CamCtl.fail.length() > 0 ? CamCtl.fail : "Camera control is unavailable.", x, cy, w, 32);
    return cy + 40;
  }
  if (!hwFound && !hwApplied) {
    fill(MUTED);
    ui(11);
    textAlign(LEFT, TOP);
    String wait = camerasReady && cam == null ? "Waiting for a camera." : "Reading the camera.";
    text(wait, x, cy, w, 20);
    return cy + 28;
  }
  if (!hwFound) {
    fill(MUTED);
    ui(11);
    textAlign(LEFT, TOP);
    text(hwError.length() > 0 ? hwError : "This camera has no hardware controls.", x, cy, w, 32);
    return cy + 40;
  }
  if (hwExpLock || hwExpAuto) {
    if (hwExpLock && hwExpAuto) cy = toggleRow("hw-exp-off", "hw-exp-on", "Auto exposure", hwAutoExposure, x, cy, w);
    else {
      fill(MUTED);
      ui(11);
      textAlign(LEFT, CENTER);
      text(hwExpLock ? "Exposure locked" : "Exposure stays automatic", x, cy + 8);
      cy += 24;
    }
    if (!hwAutoExposure && hwBiasOk) {
      String expLabel = hwUvc ? round(hwBias * 100) + "%" : nf(hwBias, 1, 1) + " EV";
      cy = sliderRow("sl-hw-bias", "Exposure", expLabel, x, cy, w, hwBias, hwBiasMin, hwBiasMax);
    }
  }
  if (hwFocLock || hwFocAuto) {
    if (hwFocLock && hwFocAuto) cy = toggleRow("hw-foc-off", "hw-foc-on", "Auto focus", hwAutoFocus, x, cy, w);
    else {
      fill(MUTED);
      ui(11);
      textAlign(LEFT, CENTER);
      text(hwFocLock ? "Focus locked" : "Focus stays automatic", x, cy + 8);
      cy += 24;
    }
    if (!hwAutoFocus && hwFocusOk) {
      cy = sliderRow("sl-hw-focus", "Focus", round(hwFocus * 100) + "%", x, cy, w, hwFocus, 0, 1);
    }
  }
  if (hwWbLock && hwWbAuto) cy = toggleRow("hw-wb-off", "hw-wb-on", "Auto white balance", hwAutoWhite, x, cy, w);
  else if (hwWbLock) {
    fill(MUTED);
    ui(11);
    textAlign(LEFT, CENTER);
    text("White balance locked", x, cy + 8);
    cy += 24;
  }
  if (hwLensCount > 1) {
    fill(MUTED);
    textAlign(LEFT, CENTER);
    ui(11);
    text("Lens", x, cy + 12);
    String[] ids = new String[hwLensCount];
    String[] labels = new String[hwLensCount];
    for (int i = 0; i < hwLensCount; i++) {
      ids[i] = "hw-lens#" + i;
      labels[i] = hwLensNames[i];
    }
    int selected = hwLens >= 0 ? hwLens : hwLensAt;
    float sw = min(w * 0.62f, 36f * hwLensCount);
    segments(ids, labels, selected, x + w - sw, cy, sw, 24);
    cy += 32;
  }
  if (hwLensOk) cy = toggleRow("hw-lensauto-off", "hw-lensauto-on", "Auto lens", !hwLensLock, x, cy, w);
  else if (hwZoomOk && hwZoomMax > hwZoomMin + 0.05f && hwLensCount < 2) {
    cy = sliderRow("sl-hw-zoom", "Lens", nf(hwZoom, 1, 1) + "×", x, cy, w, hwZoom, hwZoomMin, hwZoomMax);
  }
  if (hwStageOk) cy = toggleRow("hw-stage-off", "hw-stage-on", "Center Stage", hwCenterStage, x, cy, w);
  if (hwPortrait || hwStudio) {
    fill(DUB);
    ui(10);
    textAlign(LEFT, TOP);
    String warn = hwPortrait && hwStudio ? "Portrait and Studio Light are on in Control Center."
      : hwPortrait ? "Portrait is on in Control Center." : "Studio Light is on in Control Center.";
    text(warn, x, cy, w, 28);
    cy += 32;
  }
  if (hwError.length() > 0) {
    fill(DUB);
    ui(10);
    textAlign(LEFT, TOP);
    text(hwError, x, cy, w, 28);
    cy += 32;
  }
  return cy + 6;
}

void drawEffectsPanel(float x, float y, float w, float bottom) {
  drawFxPanel(x, y, w, bottom);
}

float drawAnimBlock(float x, float cy, float w) {
  if (topMode > TOP_DRAW || animMode == ANIM_LIVE) return cy;
  kicker(workModeLabel().toUpperCase(), x, cy, w);
  fill(hasStop() ? (stopPlaying ? REC : PLAY) : MUTED);
  textAlign(RIGHT, BASELINE);
  ui(10);
  text(stopCount() + " f", x + w, cy);
  cy += 14;
  if (animMode == ANIM_STOP) cy = drawStoptrickSettings(x, cy, w);
  else if (animMode == ANIM_DRAW) cy = drawDrawSettings(x, cy, w);
  return cy;
}

float drawStoptrickSettings(float x, float cy, float w) {
  float bw = (w - 24) / 4f;
  button("stop-shoot", "Shoot", x, cy, bw, 26, false);
  button("stop-play", stopPlaying ? "Hold" : "Play", x + bw + 8, cy, bw, 26, stopPlaying);
  button("stop-pop", "Pop", x + 2 * (bw + 8), cy, bw, 26, false);
  String bakeLab = "Bake";
  if (mode == MODE_REC && recFromStop) bakeLab = lengthLocked() ? "Cancel" : "Lock";
  else if (recWait && stopIsRecordSource()) bakeLab = "Cancel";
  boolean bakeHot = (mode == MODE_REC && recFromStop) || (recWait && stopIsRecordSource());
  button("stop-bake", bakeLab, x + 3 * (bw + 8), cy, bw, 26, bakeHot);
  mapTarget("stop-shoot", x, cy, bw, 26);
  mapTarget("stop-play", x + bw + 8, cy, bw, 26);
  cy += 34;
  cy = drawAnimFpsRow(x, cy, w);
  cy = drawOnionControls(x, cy, w);
  check("stop-clear-bake", "Clear frames after bake", x, cy, w, stopClearOnBake);
  cy += 22;
  button("stop-clear", "Clear frames", x, cy, w, 26, false);
  mapTarget("stop-clear", x, cy, w, 26);
  cy += 34;
  fill(DIM);
  ui(10);
  textAlign(LEFT, TOP);
  text("Enter shoots · Space plays · - bakes · - - bakes and clears", x, cy, w, 36);
  return cy + 40;
}

float drawOnionControls(float x, float cy, float w) {
  check("stop-onion", "Onion skin", x, cy, w, stopOnion);
  cy += 22;
  check("stop-onion-ext", "Onion on external", x, cy, w, stopOnionExternal);
  cy += 22;
  if (drawModeOn()) {
    check("draw-live-bg", "Live underlay", x, cy, w, drawLiveUnderlay);
    cy += 22;
    check("draw-cursor-ext", "Cursor on external", x, cy, w, drawCursorExternal);
    cy += 22;
  }
  return sliderRow("sl-onion", "Onion", round(stopOnionAmt * 100) + "%", x, cy, w, stopOnionAmt, 0, 1);
}

float drawDrawSettings(float x, float cy, float w) {
  float bw = (w - 16) / 3f;
  button("stop-shoot", "Shoot", x, cy, bw, 26, false);
  button("stop-play", stopPlaying ? "Hold" : "Play", x + bw + 8, cy, bw, 26, stopPlaying);
  button("stop-pop", "Pop", x + 2 * (bw + 8), cy, bw, 26, false);
  cy += 34;
  cy = drawAnimFpsRow(x, cy, w);
  cy = drawOnionControls(x, cy, w);

  kicker("TOOLS", x, cy, w);
  cy += 14;
  cy = drawPaintToolGrid(x, cy, w);
  float tw = (w - 16) / 3f;
  button("draw-raster", drawRaster ? "Raster · on" : "Raster · soft", x, cy, tw, 26, drawRaster);
  button("draw-shape-fill", drawShapeFill ? "Filled" : "Outline", x + tw + 8, cy, tw, 26, drawShapeFill);
  button("draw-trackpad", drawTrackpadMode ? "Trackpad · on" : "Trackpad Mode", x + 2 * (tw + 8), cy, tw, 26, drawTrackpadMode);
  cy += 34;
  cy = sliderRow("sl-brush", "Size", round(drawBrush) + " px", x, cy, w, drawBrush, DRAW_BRUSH_MIN, DRAW_BRUSH_MAX);

  kicker("COLOR", x, cy, w);
  cy += 14;
  cy = drawSwatchRow(x, cy, w);
  if (drawHslOpen) {
    fill(MUTED);
    ui(10);
    textAlign(LEFT, TOP);
    text("Double-click a swatch · drag to edit", x, cy, w, 16);
    cy += 18;
    cy = drawHslPadUI(x, cy, w);
  }

  button("draw-clear", "Clear frame", x, cy, w, 26, false);
  return cy + 34;
}

float drawSwatchRow(float x, float cy, float w) {
  int n = drawSwatches.length;
  float gap = 6;
  float sw = min(36, (w - gap * (n - 1)) / n);
  float total = n * sw + (n - 1) * gap;
  float sx0 = x + max(0, (w - total) * 0.5f);
  for (int i = 0; i < n; i++) {
    float sx = sx0 + i * (sw + gap);
    hit("draw-sw#" + i, sx, cy, sw, sw);
    noStroke();
    fill(drawSwatches[i]);
    rect(sx, cy, sw, sw, 4);
    if (drawColorIdx == i) {
      noFill();
      stroke(drawHslOpen ? PAPER : INK);
      strokeWeight(drawHslOpen ? 2 : 1.5);
      rect(sx - 1.5, cy - 1.5, sw + 3, sw + 3, 5);
      noStroke();
    }
  }
  return cy + sw + 12;
}

float drawPaintToolGrid(float x, float cy, float w) {
  int cols = 5;
  float gap = 4;
  float cw = (w - gap * (cols - 1)) / cols;
  float ch = max(28, min(36, cw));
  for (int i = 0; i <= DRAW_ROUNDRECT; i++) {
    int col = i % cols;
    int row = i / cols;
    float tx = x + col * (cw + gap);
    float ty = cy + row * (ch + gap);
    drawPaintToolButton("draw-tool-" + i, i, tx, ty, cw, ch, drawTool == i);
  }
  return cy + 2 * (ch + gap) + 4;
}

void drawPaintToolButton(String id, int tool, float x, float y, float w, float h, boolean on) {
  if (inClip(y, h)) hit(id, x, y, w, h);
  noStroke();
  if (on) {
    fill(WELL);
    rect(x, y, w, h);
  }
  stroke(on ? INK : LINE);
  strokeWeight(1);
  noFill();
  rect(x + 0.5, y + 0.5, w - 1, h - 1);
  drawPaintToolIcon(tool, x + w * 0.5f, y + h * 0.5f, min(w, h) * 0.42f, on ? INK : MUTED);
}

/** Classic MS Paint–style glyphs, centered at (cx, cy). */
void drawPaintToolIcon(int tool, float cx, float cy, float r, color col) {
  stroke(col);
  strokeWeight(1.2f);
  strokeCap(ROUND);
  strokeJoin(ROUND);
  fill(col);
  switch (tool) {
    case DRAW_PENCIL: {
      noFill();
      beginShape();
      vertex(cx - r * 0.55f, cy + r * 0.55f);
      vertex(cx - r * 0.15f, cy + r * 0.15f);
      vertex(cx + r * 0.45f, cy - r * 0.45f);
      vertex(cx + r * 0.65f, cy - r * 0.25f);
      vertex(cx + r * 0.05f, cy + r * 0.35f);
      vertex(cx - r * 0.35f, cy + r * 0.75f);
      endShape(CLOSE);
      line(cx - r * 0.15f, cy + r * 0.15f, cx + r * 0.45f, cy - r * 0.45f);
      break;
    }
    case DRAW_BRUSH: {
      noFill();
      // handle
      line(cx - r * 0.55f, cy + r * 0.55f, cx + r * 0.15f, cy - r * 0.15f);
      strokeWeight(2.4f);
      line(cx + r * 0.05f, cy - r * 0.05f, cx + r * 0.45f, cy - r * 0.45f);
      strokeWeight(1.2f);
      // ferrule + tip blob
      fill(col);
      noStroke();
      ellipse(cx + r * 0.52f, cy - r * 0.52f, r * 0.55f, r * 0.55f);
      stroke(col);
      noFill();
      break;
    }
    case DRAW_ERASER: {
      pushMatrix();
      translate(cx, cy);
      rotate(-0.45f);
      noFill();
      rect(-r * 0.55f, -r * 0.28f, r * 1.1f, r * 0.56f);
      line(-r * 0.1f, -r * 0.28f, -r * 0.1f, r * 0.28f);
      popMatrix();
      break;
    }
    case DRAW_FILL: {
      // bucket body
      noFill();
      beginShape();
      vertex(cx - r * 0.45f, cy - r * 0.15f);
      vertex(cx + r * 0.35f, cy - r * 0.35f);
      vertex(cx + r * 0.55f, cy + r * 0.25f);
      vertex(cx - r * 0.25f, cy + r * 0.45f);
      endShape(CLOSE);
      // handle
      arc(cx - r * 0.05f, cy - r * 0.45f, r * 0.7f, r * 0.55f, PI * 0.95f, PI * 1.85f);
      // drip
      fill(col);
      noStroke();
      ellipse(cx + r * 0.55f, cy + r * 0.55f, r * 0.28f, r * 0.38f);
      stroke(col);
      noFill();
      break;
    }
    case DRAW_PICK: {
      noFill();
      // tube
      line(cx - r * 0.5f, cy + r * 0.5f, cx + r * 0.2f, cy - r * 0.2f);
      // bulb
      ellipse(cx + r * 0.4f, cy - r * 0.4f, r * 0.42f, r * 0.42f);
      // tip notch
      line(cx - r * 0.55f, cy + r * 0.35f, cx - r * 0.35f, cy + r * 0.55f);
      break;
    }
    case DRAW_SPRAY: {
      noFill();
      // can
      rect(cx - r * 0.35f, cy - r * 0.1f, r * 0.55f, r * 0.75f, 2);
      // nozzle
      line(cx - r * 0.08f, cy - r * 0.1f, cx - r * 0.08f, cy - r * 0.35f);
      line(cx - r * 0.28f, cy - r * 0.35f, cx + r * 0.12f, cy - r * 0.35f);
      // mist dots
      noStroke();
      fill(col);
      float[][] dots = {
        {0.35f, -0.55f}, {0.55f, -0.35f}, {0.7f, -0.55f},
        {0.45f, -0.75f}, {0.65f, -0.7f}, {0.8f, -0.4f}
      };
      for (int i = 0; i < dots.length; i++) {
        ellipse(cx + r * dots[i][0], cy + r * dots[i][1], 2.2f, 2.2f);
      }
      stroke(col);
      noFill();
      break;
    }
    case DRAW_LINE: {
      noFill();
      line(cx - r * 0.65f, cy + r * 0.55f, cx + r * 0.65f, cy - r * 0.55f);
      break;
    }
    case DRAW_RECT: {
      noFill();
      rect(cx - r * 0.6f, cy - r * 0.45f, r * 1.2f, r * 0.9f);
      break;
    }
    case DRAW_ELLIPSE: {
      noFill();
      ellipse(cx, cy, r * 1.25f, r * 0.95f);
      break;
    }
    case DRAW_ROUNDRECT: {
      noFill();
      rect(cx - r * 0.6f, cy - r * 0.45f, r * 1.2f, r * 0.9f, r * 0.28f);
      break;
    }
  }
  strokeWeight(1);
  strokeCap(ROUND);
  noStroke();
  noFill();
}

float drawHslPadUI(float x, float cy, float w) {
  float pad = min(w, 140);
  hslPadX = x + (w - pad) * 0.5f;
  hslPadY = cy;
  hslPadW = pad;
  hslPadH = pad;

  ensureHslPadImage(max(2, round(pad)), max(2, round(pad)));
  if (hslPadImg != null) image(hslPadImg, hslPadX, hslPadY, pad, pad);
  else {
    noStroke();
    fill(WELL);
    rect(hslPadX, hslPadY, pad, pad);
  }

  float sx = hslPadX + (drawHue / 360f) * pad;
  float sy = hslPadY + (1f - drawLight) * pad;
  stroke(PAPER);
  strokeWeight(1);
  noFill();
  ellipse(sx, sy, 10, 10);
  stroke(INK);
  ellipse(sx, sy, 8, 8);

  stroke(LINE);
  strokeWeight(1);
  noFill();
  rect(hslPadX + 0.5, hslPadY + 0.5, pad - 1, pad - 1);
  noStroke();

  if (inClip(cy, pad)) hit("hsl-pad", hslPadX, hslPadY, pad, pad);
  return cy + pad + 12;
}

float drawAnimFpsRow(float x, float cy, float w) {
  return sliderRow("sl-stop-fps", "FPS", stopFps + " fps", x, cy, w, stopFps, 1, 25);
}

float drawProjectBlock(float x, float cy, float w) {
  kicker("PROJECT", x, cy, w);
  cy += 14;
  fill(projectOpen ? PAPER : DUB);
  textAlign(LEFT, CENTER);
  ui(11);
  text(fitText(projectOpen ? projectName : "No project — required for loops", w), x, cy);
  cy += 16;
  fill(MUTED);
  ui(10);
  text(fitText(projectOpen ? projectDir : "File → New Project… chooses the save location", w), x, cy);
  cy += 14;
  float bw3 = (w - 16) / 3f;
  button("proj-new", "New", x, cy, bw3, 24, false);
  button("proj-open", "Open", x + bw3 + 8, cy, bw3, 24, false);
  button("proj-save", "Save", x + 2 * (bw3 + 8), cy, bw3, 24, false);
  cy += 32;
  if (projectOpen) {
    button("proj-show", "Show in Finder", x, cy, w, 24, false);
    cy += 32;
  }
  if (!recentProjects.isEmpty()) {
    kicker("RECENT", x, cy, w);
    cy += 10;
    int n = min(5, recentProjects.size());
    for (int i = 0; i < n; i++) {
      String title = projectTitleForPath(recentProjects.get(i));
      boolean on = projectOpen && recentProjects.get(i).equals(projectDir);
      row("proj-recent#" + i, title, x, cy, w, on);
      cy += 26;
    }
    cy += 8;
  }
  kicker("LOOP", x, cy, w);
  cy += 12;
  int resRow = capW == 640 ? 0 : capW == 854 ? 1 : capW == 960 ? 2 : capW == 1280 ? 3 : capW == 1920 ? 4 : -1;
  segments(new String[] {"res-640", "res-854", "res-960", "res-1280", "res-1920"}, new String[] {"360", "480", "540", "720", "1080"}, resRow, x, cy, w, 24);
  cy += 32;
  int fpsRow = capFps == 24 ? 0 : capFps == 25 ? 1 : capFps == 30 ? 2 : -1;
  segments(new String[] {"fps-24", "fps-25", "fps-30"}, new String[] {"24", "25", "30"}, fpsRow, x, cy, w, 24);
  cy += 32;
  int[] steps = undoStepChoices();
  String[] undoIds = new String[steps.length];
  String[] undoLabs = new String[steps.length];
  int undoRow = -1;
  for (int i = 0; i < steps.length; i++) {
    undoIds[i] = "undo-steps#" + i;
    undoLabs[i] = steps[i] <= 0 ? "Off" : str(steps[i]);
    if (steps[i] == undoSteps) undoRow = i;
  }
  kicker("UNDO", x, cy, w);
  cy += 12;
  segments(undoIds, undoLabs, undoRow, x, cy, w, 24);
  cy += 30;
  float mb = HapCodec.dxt1Size(capW, capH) * capFps / (1024f * 1024f);
  fill(DIM);
  ui(10);
  textAlign(LEFT, TOP);
  String undoHelp = undoSteps <= 0
    ? "No Hap undo. X X saves an MP4 and deletes Hap files."
    : ("Keeps " + undoSteps + " Hap undo steps. X X saves an MP4 and deletes the rest.");
  text("Hap1  " + nf(mb, 0, 1) + " MB/s · max " + MAX_SECONDS + "s. Change clears.\n" + undoHelp, x, cy, w, 56);
  return cy + 64;
}

float drawRawPipSettings(float x, float cy, float w) {
  kicker("raw-preview", x, cy, w);
  cy += 14;
  check("raw-pip", "raw-preview", x, cy, w, rawPipDesktop);
  cy += 22;
  check("raw-pip-ext", "raw-preview external", x, cy, w, rawPipExternal);
  return cy + 28;
}

void drawGlobalPanel(float x, float y, float w, float bottom) {
  float cy = drawRawPipSettings(x, y, w);
  cy = drawProjectBlock(x, cy, w);
  drawMidiPanel(x, cy, w, bottom);
}

void drawOutputPanel(float x, float y, float w, float bottom) {
  clipTop = y;
  clipBot = bottom;
  clip(x - 20, y, w + 40, max(1, bottom - y));
  float cy = y;
  // Prefer scrolling from top content; no separate scroll var — keep short.
  kicker("EXTERNAL OUT", x, cy, w);
  cy += 12;
  fill(DIM);
  ui(10);
  textAlign(LEFT, TOP);
  text("Fullscreen program feed only — no GUI. Toggle a screen to send.", x, cy, w, 32);
  cy += 34;
  ArrayList<ExtDisplay> ext = listExternalDisplays();
  if (ext.isEmpty()) {
    fill(DUB);
    ui(11);
    textAlign(LEFT, TOP);
    text("No external display connected.\nPlug in a beamer / monitor, then toggle it here.", x, cy, w, 48);
    cy += 52;
  } else {
    for (int i = 0; i < ext.size(); i++) {
      ExtDisplay d = ext.get(i);
      boolean on = beamerOnExternal(d.id);
      check("ext#" + i, (on ? "On · " : "Send · ") + d.label, x, cy, w, on);
      cy += 26;
    }
    cy += 6;
  }
  float bw = (w - 8) / 2f;
  cy += 4;
  check("grid", "Keystone grid (preview)", x, cy, w, showGrid);
  cy += 24;
  check("blackout", "Black", x, cy, w, blackout);
  cy += 24;
  check("live-out", liveInOutput ? "Live updating" : "Live frozen (last frame)", x, cy, w, liveInOutput);
  cy += 24;
  check("syphon-out", "Syphon “LuckyLoop”", x, cy, w, syphonOut);
  cy += 28;
  kicker("raw-preview", x, cy, w);
  cy += 14;
  check("raw-pip", "raw-preview", x, cy, w, rawPipDesktop);
  cy += 22;
  check("raw-pip-ext", "raw-preview external", x, cy, w, rawPipExternal);
  cy += 28;
  cy = drawCurveEditor(x, cy, w, 1, "OUTPUT CURVE");
  cy += 10;
  kicker("KEYSTONE", x, cy, w);
  cy += 12;
  fill(DIM);
  ui(10);
  textAlign(LEFT, TOP);
  text("Drag corners on the large preview. Arrow keys nudge.", x, cy, w, 32);
  cy += 36;
  button("reset-key", "Reset", x, cy, bw, 24, false);
  button("inset-key", "Inset 3%", x + bw + 8, cy, bw, 24, false);
  noClip();
  clipTop = -100000;
  clipBot = 100000;
}

String signedPct(float v) {
  int p = round(v * 100);
  if (p > 0) return "+" + p;
  return str(p);
}
