PGraphics sourceGfx;
PGraphics gradeGfx;
PGraphics coreGfx;
PGraphics blurFineGfx;
PGraphics blurWideGfx;
PGraphics blurTemp;
PGraphics compGfx;
PGraphics liveMixGfx; // soft Multiply/Screen: lerp(loop, blend(loop, live), opac)
PGraphics feedbackGfx;
PGraphics histGfx;
PImage gradedView;
PImage viewImage;
PImage stackImg;       // CPU draw stack for program out / Syphon
PImage drawPreviewImg; // CPU draw stack for operator preview (local onion)
PGraphics stackGfx;       // retina upload of stackImg — same texture type as the camera
PGraphics drawPreviewGfx; // retina upload of the operator plate
PImage lutM;
PImage lutR;
PImage lutG;
PImage lutB;
PShader gradeShader;
PShader blurShader;
boolean gpuGradeActive = false;
boolean gradeGpuBroken = false;
boolean gradeGpuAnnounced = false;
boolean loggedFrameDensity = false;
int recordPullFrame = -1;

PGraphics frameGraphics(int w, int h) {
  PGraphics pg = createGraphics(w, h, P2D);
  int scale = pg.width > 0 ? max(1, pg.pixelWidth / pg.width) : 1;
  pg.pixelDensity = scale;
  if (!loggedFrameDensity && pg != null) {
    loggedFrameDensity = true;
    println("Frame buffer " + pg.width + "×" + pg.height + " density " + pg.pixelDensity + " pixels " + pg.pixelWidth + "×" + pg.pixelHeight);
  }
  return pg;
}

PGraphics ensureFrame(PGraphics pg) {
  if (pg != null && pg.width == capW && pg.height == capH) return pg;
  return frameGraphics(capW, capH);
}

void releaseGradeGpu() {
  sourceGfx = null;
  gradedView = null;
  viewImage = null;
  gradeGfx = null;
  coreGfx = null;
  blurFineGfx = null;
  blurWideGfx = null;
  blurTemp = null;
  compGfx = null;
  liveMixGfx = null;
  stackImg = null;
  drawPreviewImg = null;
  stackGfx = null;
  drawPreviewGfx = null;
  clearFadeGfx = null;
  liveCropGfx = null;
  stopViewGfx = null;
  stopViewImg = null;
  feedbackGfx = null;
  histGfx = null;
  gpuGradeActive = false;
  recordPullFrame = -1;
}

/**
 * Composite live into dst. Opacity applies AFTER Live FX (liveSrc is already graded+FX).
 * Soft Multiply/Screen: bake blend(loop, live) then lerp with opacity —
 * OpenGL tint()+MULTIPLY does not match blendInto and looks like the fader is dead.
 */
void drawLiveLayerInto(PGraphics dst, PImage loopBase, PImage liveSrc, int alpha) {
  if (dst == null || liveSrc == null || alpha <= 0) return;
  int lb = liveMixBlend();
  boolean softBlend = alpha < 255 && lb != BLEND_NORMAL && loopBase != null;
  dst.blendMode(BLEND);
  dst.noTint();
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
    dst.tint(255, alpha);
    dst.image(liveMixGfx, 0, 0, capW, capH);
    dst.noTint();
    return;
  }
  if (lb == BLEND_NORMAL) dst.blendMode(BLEND);
  else dst.blendMode(lb == BLEND_SCREEN ? SCREEN : MULTIPLY);
  if (alpha < 255) dst.tint(255, alpha);
  dst.image(liveSrc, 0, 0, capW, capH);
  if (alpha < 255) dst.noTint();
  dst.blendMode(BLEND);
}

PImage shownFrame() {
  if (blackoutSolid()) return null;
  if (gpuGradeActive && viewImage != null) return viewImage;
  return monitorImg;
}

boolean applyGradeGpu() {
  gpuGradeActive = false;
  gradedView = null;
  if (gradeGpuBroken || sourceGfx == null || capW < 2 || capH < 2) return false;
  try {
    if (gradeShader == null) gradeShader = loadShader("grade.glsl");
    if (blurShader == null) blurShader = loadShader("blur.glsl");
    if (gradeShader == null || blurShader == null) return false;
    renderGraded();
    gpuGradeActive = true;
    if (!gradeGpuAnnounced) {
      gradeGpuAnnounced = true;
      println("Grade on GPU.");
    }
    if (inspectorTab == 0) sampleGradeHist();
    return true;
  } catch (Exception e) {
    gradeGpuBroken = true;
    gpuGradeActive = false;
    println("Grade shader failed, using the CPU. " + e.getMessage());
    e.printStackTrace();
    return false;
  }
}

void renderGraded() {
  syncCurveLuts();
  boolean spatial = spatialOn();
  boolean work = spatial || toneOn() || curvesOn() || finishOn();
  if (!work) {
    gradedView = sourceGfx;
    return;
  }
  if (spatial) {
    coreGfx = ensureFrame(coreGfx);
    drawGrade(sourceGfx, coreGfx, 0, 1);
    PGraphics fine = coreGfx;
    PGraphics wide = coreGfx;
    if (camSharp > 0.004 || camNoise > 0.004) {
      blurFineGfx = ensureFrame(blurFineGfx);
      gpuBlurInto(coreGfx, blurFineGfx, 1);
      fine = blurFineGfx;
    }
    if (abs(camClarity) > 0.004) {
      blurWideGfx = ensureFrame(blurWideGfx);
      gpuBlurInto(coreGfx, blurWideGfx, 8);
      wide = blurWideGfx;
    }
    gradeGfx = ensureFrame(gradeGfx);
    drawGrade(coreGfx, gradeGfx, 1, 0, fine, wide);
  } else {
    gradeGfx = ensureFrame(gradeGfx);
    drawGrade(sourceGfx, gradeGfx, 0, 0, sourceGfx, sourceGfx);
  }
  gradedView = gradeGfx;
}

void drawGrade(PGraphics src, PGraphics dst, float stage, float coreOnly) {
  drawGrade(src, dst, stage, coreOnly, src, src);
}

void drawGrade(PGraphics src, PGraphics dst, float stage, float coreOnly, PGraphics fine, PGraphics wide) {
  dst.beginDraw();
  dst.background(0);
  dst.shader(gradeShader);
  bindGrade(stage, coreOnly, fine == null ? src : fine, wide == null ? src : wide);
  dst.image(src, 0, 0, capW, capH);
  dst.resetShader();
  dst.endDraw();
}

void bindGrade(float stage, float coreOnly, PGraphics fine, PGraphics wide) {
  // Stylistic FX (hue/post/thr/pix/invert/feedback) run via FxStack after grade.
  gradeShader.set("texels", 1f / capW, 1f / capH);
  gradeShader.set("exposure", camExposure);
  gradeShader.set("brilliance", camBrilliance);
  gradeShader.set("highlights", camHighlights);
  gradeShader.set("shadows", camShadows);
  gradeShader.set("contrast", camContrast);
  gradeShader.set("brightness", camBrightness);
  gradeShader.set("blackPoint", camBlack);
  gradeShader.set("saturation", camSaturation);
  gradeShader.set("vibrance", camVibrance);
  gradeShader.set("warmth", camWarmth);
  gradeShader.set("tint", camTint);
  gradeShader.set("vignette", camVignette);
  gradeShader.set("hueOn", 0);
  gradeShader.set("hueCos", 1);
  gradeShader.set("hueSin", 0);
  gradeShader.set("posterize", 0);
  gradeShader.set("threshold", 0);
  gradeShader.set("invert", 0);
  gradeShader.set("feedback", 0);
  gradeShader.set("feedbackTex", sourceGfx);
  gradeShader.set("sharpAmt", camSharp * 1.55f);
  gradeShader.set("noiseAmt", constrain(camNoise, 0, 1));
  gradeShader.set("clarityAmt", camClarity * 1.1f);
  gradeShader.set("stage", stage);
  gradeShader.set("coreOnly", coreOnly);
  gradeShader.set("pixSize", 1);
  gradeShader.set("lutM", lutM);
  gradeShader.set("lutR", lutR);
  gradeShader.set("lutG", lutG);
  gradeShader.set("lutB", lutB);
  gradeShader.set("blurFine", fine);
  gradeShader.set("blurWide", wide);
}

void gpuBlurInto(PGraphics src, PGraphics dst, float radius) {
  blurTemp = ensureFrame(blurTemp);
  runBlur(src, blurTemp, radius, 1, 0);
  runBlur(blurTemp, dst, radius, 0, 1);
}

void runBlur(PGraphics src, PGraphics dst, float radius, float dx, float dy) {
  dst.beginDraw();
  dst.shader(blurShader);
  blurShader.set("texels", 1f / capW, 1f / capH);
  blurShader.set("dir", dx, dy);
  blurShader.set("radius", radius);
  dst.image(src, 0, 0, capW, capH);
  dst.resetShader();
  dst.endDraw();
}

PImage makeLut() {
  return createImage(256, 1, ARGB);
}

void syncCurveLuts() {
  if (curves == null) initCurves();
  boolean dirty = false;
  for (int i = 0; i < 4; i++) if (curves[i].dirty) dirty = true;
  ensureCurveLuts();
  if (lutM == null || lutR == null || lutG == null || lutB == null) {
    lutM = makeLut();
    lutR = makeLut();
    lutG = makeLut();
    lutB = makeLut();
    dirty = true;
  }
  if (!dirty) return;
  writeLut(lutM, curves[0]);
  writeLut(lutR, curves[1]);
  writeLut(lutG, curves[2]);
  writeLut(lutB, curves[3]);
}

void writeLut(PImage img, ToneCurve c) {
  img.loadPixels();
  int n = min(256, img.pixels.length);
  for (int i = 0; i < n; i++) {
    int v = c.lut[i];
    img.pixels[i] = 0xFF000000 | (v << 16) | (v << 8) | v;
  }
  img.updatePixels();
}

void sampleGradeHist() {
  if (gradedView == null) return;
  if (histGfx == null || histGfx.width != 96 || histGfx.height != 54) histGfx = frameGraphics(96, 54);
  histGfx.beginDraw();
  histGfx.background(0);
  histGfx.image(gradedView, 0, 0, 96, 54);
  histGfx.endDraw();
  histGfx.loadPixels();
  for (int ch = 0; ch < 4; ch++) {
    java.util.Arrays.fill(curveHist[ch], 0);
    curveHistPeak[ch] = 1;
  }
  int n = histGfx.pixels.length;
  for (int i = 0; i < n; i++) {
    int p = histGfx.pixels[i];
    int r = (p >> 16) & 255;
    int g = (p >> 8) & 255;
    int b = p & 255;
    int luma = (r * 299 + g * 587 + b * 114) / 1000;
    int binL = luma * 63 / 255;
    int binR = r * 63 / 255;
    int binG = g * 63 / 255;
    int binB = b * 63 / 255;
    if (++curveHist[0][binL] > curveHistPeak[0]) curveHistPeak[0] = curveHist[0][binL];
    if (++curveHist[1][binR] > curveHistPeak[1]) curveHistPeak[1] = curveHist[1][binR];
    if (++curveHist[2][binG] > curveHistPeak[2]) curveHistPeak[2] = curveHist[2][binG];
    if (++curveHist[3][binB] > curveHistPeak[3]) curveHistPeak[3] = curveHist[3][binB];
  }
}

void copyFramePixels(PImage src, int[] dest) {
  if (src == null || dest == null) return;
  src.loadPixels();
  int dw = src.pixelWidth > 0 ? src.pixelWidth : src.width;
  int dh = src.pixelHeight > 0 ? src.pixelHeight : src.height;
  int density = src.width > 0 ? max(1, dw / src.width) : 1;
  if (dw == capW && dh == capH) {
    int n = min(dest.length, src.pixels.length);
    for (int i = 0; i < n; i++) dest[i] = src.pixels[i] | 0xFF000000;
    return;
  }
  int n = min(dest.length, capW * capH);
  for (int i = 0; i < n; i++) {
    int x = i % capW;
    int y = i / capW;
    int sx = min(dw - 1, x * density + density / 2);
    int sy = min(dh - 1, y * density + density / 2);
    dest[i] = src.pixels[sy * dw + sx] | 0xFF000000;
  }
}

void ensureRecordPixels() {
  if (!gpuGradeActive || gradedView == null || livePixels == null) return;
  if (recordPullFrame == frameCount) return;
  recordPullFrame = frameCount;
  copyFramePixels(gradedView, livePixels);
}

/**
 * Full CPU stack: loop → live → onion → ink on one pixel grid.
 * A separate image() of the onion into the GPU frame is half a texel off on the external screen.
 * stopA: use stopOverlayAlpha(false) for operator preview, (true) for program out.
 * Pass a dedicated dest so preview (local onion) does not clobber Syphon's buffer.
 */
PImage composeDrawProgramCPU(PImage dest, PImage loopFrame, boolean liveOn, int stopA) {
  if (dest == null || dest.width != capW || dest.height != capH) {
    dest = createImage(capW, capH, ARGB);
  }
  int n = capW * capH;
  dest.loadPixels();
  java.util.Arrays.fill(dest.pixels, 0xFF000000);
  if (loopHistGhost && loopHistSrc != null && loopHistSrc.length == n) {
    int la = constrain(round(shownLoopOpacity() * 255), 0, 255);
    if (la > 0) blendInto(dest.pixels, loopHistSrc, la, BLEND_NORMAL);
  } else if (loopFrame != null) {
    int la = constrain(round(shownLoopOpacity() * 255), 0, 255);
    int[] srcPx = (loopPixels != null && loopPixels.length == n) ? loopPixels : null;
    if (srcPx == null) {
      loopFrame.loadPixels();
      if (loopFrame.pixels != null && loopFrame.pixels.length == n) srcPx = loopFrame.pixels;
    }
    if (srcPx != null && la > 0) {
      if (la >= 255) arrayCopy(srcPx, dest.pixels);
      else blendInto(dest.pixels, srcPx, la, BLEND_NORMAL);
    }
  }
  if (liveOn) {
    int[] livePx = liveCompositePixels();
    if (livePx != null && livePx.length == n) {
      int a = constrain(round(liveOpacity * 255), 0, 255);
      if (a > 0) blendInto(dest.pixels, livePx, a, liveMixBlend());
    }
  }
  if (stopA > 0) {
    // Ink plates need baked alpha (same as GPU onion path) — plain blendInto
    // drops sparse ARGB ghosts, so Draw onion looked empty on LuckyPad.
    if (stopHeadIsInkPlate()) {
      PImage plate = stopOnionPlate(stopA);
      if (plate != null) {
        plate.loadPixels();
        if (plate.pixels != null && plate.pixels.length == n) {
          blendInto(dest.pixels, plate.pixels, 255, BLEND_NORMAL);
        }
      }
    } else {
      int[] sp = stopCurrentPixels();
      if (sp != null && sp.length == n) {
        blendInto(dest.pixels, sp, stopA, stopOverlayBlend());
      }
    }
  }
  if (drawModeOn() && drawImg != null) {
    drawImg.loadPixels();
    int inkA = liveBusAlpha();
    if (inkA > 0 && drawImg.pixels != null && drawImg.pixels.length == n) {
      blendInto(dest.pixels, drawImg.pixels, inkA, BLEND_NORMAL);
    }
  }
  blendHapCover(dest.pixels);
  dest.updatePixels();
  return dest;
}

/**
 * Upload a capW×capH plate into a retina PGraphics without image().
 * image() of a density-1 plate into the density-2 program is half a texel off,
 * so the onion sat beside the camera. Pixel upload keeps the camera's texture grid.
 */
PGraphics uploadPlate(PGraphics dest, PImage plate) {
  if (plate == null) return dest;
  dest = ensureFrame(dest);
  plate.loadPixels();
  dest.loadPixels();
  int dw = dest.pixelWidth > 0 ? dest.pixelWidth : dest.width;
  int dh = dest.pixelHeight > 0 ? dest.pixelHeight : dest.height;
  int density = dest.width > 0 ? max(1, dw / dest.width) : 1;
  int[] src = plate.pixels;
  int[] px = dest.pixels;
  if (src == null || px == null || src.length < capW * capH || px.length < dw * dh) return null;
  if (density == 1) {
    arrayCopy(src, 0, px, 0, capW * capH);
  } else {
    for (int y = 0; y < capH; y++) {
      int srow = y * capW;
      int y0 = y * density;
      for (int x = 0; x < capW; x++) {
        int c = src[srow + x];
        int x0 = x * density;
        for (int py = 0; py < density; py++) {
          int drow = (y0 + py) * dw + x0;
          for (int pxx = 0; pxx < density; pxx++) px[drow + pxx] = c;
        }
      }
    }
  }
  dest.updatePixels();
  // Push the CPU plate into the GL texture now. Otherwise Syphon / the beamer
  // keep the old framebuffer and the onion stays on the shifted image() path.
  try {
    if (g instanceof processing.opengl.PGraphicsOpenGL) {
      ((processing.opengl.PGraphicsOpenGL) g).getTexture(dest);
    }
  } catch (Throwable t) {
    println("plate upload: " + t.getMessage());
  }
  return dest;
}

void publishGpuFrames() {
  boolean playing = loopAudible();
  PImage loopFrame = null;
  if (playing && syncLoopImage()) loopFrame = loopImg;
  else if (loopHistGhost && loopHistImg != null && loopHistAmt > 0.001f) loopFrame = loopHistImg;
  // Program out uses external onion policy; operator preview composites locally.
  int stopA = stopOverlayAlpha(true);
  PImage stopSrc = (stopA > 0) ? stopDisplayImage() : null;
  boolean stopOn = stopA > 0 && stopSrc != null;
  boolean drawOn = drawModeOn() && drawImg != null;
  PImage liveSrc = liveCompositeSource();
  // Live (graded + Live FX) stays under ink while drawing — don't replace it with the plate alone.
  boolean liveOn = liveSrc != null && liveOpacity > 0.001 && liveShowing() && outputIncludesLive();
  // Draw with no Hap loop must never open onto a black program out.
  if (drawOn && !liveOn && liveSrc != null && liveOpacity > 0.001 && liveShowing() && !loopAudible() && !liveFrozen()) {
    liveOn = true;
  }
  boolean loopSoft = loopFrame != null && shownLoopOpacity() < 0.999f;
  boolean liveSoft = liveOn && liveOpacity < 0.999f;
  // Also composite when live is alone but dimmed — otherwise opacity is ignored.
  // drawOn alone must composite too (ink over black).
  boolean needComp = (loopFrame != null || stopOn || drawOn || liveSoft)
    && (stopOn || liveOn || drawOn || loopSoft || liveSoft);
  // Onion and frame stacks share the camera's pixel grid. image() of that
  // plate into the GPU comp sits half a texel off on Syphon / the beamer.
  if ((drawOn || stopOn) && !blackoutSolid()) {
    if (loopFrame != null) syncLoopImage();
    stackImg = composeDrawProgramCPU(stackImg, loopFrame, liveOn, stopA);
    // Keep viewImage on the CPU plate. stackGfx is upload-only; image()/beginDraw
    // on it for cursor/feed/blackout samples empty → black external (cursor only).
    stackGfx = uploadPlate(stackGfx, stackImg);
    viewImage = stackImg != null ? stackImg : stackGfx;
  } else if (needComp) {
    compGfx = ensureFrame(compGfx);
    compGfx.beginDraw();
    compGfx.background(0);
    compGfx.blendMode(BLEND);
    compGfx.noTint();
    if (loopFrame != null) {
      int la = constrain(round(shownLoopOpacity() * 255), 0, 255);
      if (la < 255) compGfx.tint(255, la);
      if (la > 0) compGfx.image(loopFrame, 0, 0, capW, capH);
      if (la < 255) compGfx.noTint();
    }
    // Live under onion — opacity mixes AFTER Live FX (liveSrc is post-FX).
    if (liveOn) {
      int a = constrain(round(liveOpacity * 255), 0, 255);
      drawLiveLayerInto(compGfx, loopFrame, liveSrc, a);
    }
    if (stopOn) {
      compGfx.blendMode(BLEND);
      if (stopHeadIsInkPlate()) {
        // Bake onion alpha into plate — tint()+ARGB drops solid rect fills.
        PImage plate = stopOnionPlate(stopA);
        compGfx.noTint();
        if (plate != null) compGfx.image(plate, 0, 0, capW, capH);
      } else if (stopA >= 255) {
        int sb = stopOverlayBlend();
        if (sb == BLEND_NORMAL) compGfx.blendMode(BLEND);
        else compGfx.blendMode(sb == BLEND_SCREEN ? SCREEN : MULTIPLY);
        compGfx.image(stopSrc, 0, 0, capW, capH);
        compGfx.blendMode(BLEND);
      } else {
        // tint()+MULTIPLY ignores the live fader — same bake-then-lerp as the camera.
        drawLiveLayerInto(compGfx, loopFrame, stopSrc, stopA);
      }
    }
    paintHapCoverGfx(compGfx);
    compGfx.endDraw();
    viewImage = compGfx;
  } else if (loopFrame != null) {
    viewImage = loopFrame;
  } else if (stopOn) {
    viewImage = stopSrc;
  } else if (liveOn) {
    viewImage = liveSrc;
  } else {
    viewImage = blackImg;
  }
  if (blackoutSolid()) {
    viewImage = blackImg;
    sendSyphon(blackImg);
    if (beamerOpen) prepareBeamerGpu(blackImg);
    return;
  }
  PImage program = viewImage;
  if (program == null) return;
  if (outCurvesOn()) {
    // Pull program → output curves → preview / publish / syphon.
    if (outputImg == null || outputImg.width != capW || outputImg.height != capH) {
      outputImg = createImage(capW, capH, ARGB);
    }
    outputImg.loadPixels();
    copyFramePixels(program, outputImg.pixels);
    applyOutCurves(outputImg.pixels);
    outputImg.updatePixels();
    program = outputImg;
    viewImage = outputImg;
  }
  program = applyClearFadeImage(program);
  viewImage = program;
  // Preview stays clean — text is drawn on top in the UI.
  // Wire out gets the same fields when Text is on air.
  PImage outgoing = applyFeedToProgram(program);
  PImage ext = applyBlackoutImage(withDrawCursorExternal(outgoing));
  sendSyphon(ext);
  if (!beamerOpen) return;
  prepareBeamerGpu(ext);
}
