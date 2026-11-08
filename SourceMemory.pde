// Per-input-source memory: framing, grade, input curves.
// Switching Cam / Syphon / Tether / Test (or a different camera/server)
// stashes the current look and restores that source's last settings.

JSONObject sourceMemories;
String sourceMemoryActiveKey = "";

String currentSourceKey() {
  if (sourceMode == SRC_CAM) {
    String n = cameraName == null ? "" : cameraName;
    return "cam:" + n;
  }
  if (sourceMode == SRC_SYPHON) {
    String app = savedSyApp == null ? "" : savedSyApp;
    String server = savedSyServer == null ? "" : savedSyServer;
    if (syEntries != null && syIndex >= 0 && syIndex < syEntries.size()) {
      SyEntry e = syEntries.get(syIndex);
      if (e != null) {
        app = e.app == null ? "" : e.app;
        server = e.server == null ? "" : e.server;
      }
    }
    return "syphon:" + app + "/" + server;
  }
  if (sourceMode == SRC_TETHER) return "tether";
  return "test";
}

boolean defaultMirrorForSource(int mode) {
  return mode == SRC_CAM;
}

JSONObject captureSourceMemory() {
  JSONObject o = new JSONObject();
  o.setBoolean("mirror", mirror);
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
  o.setFloat("camExposure", camExposure);
  o.setFloat("camBrilliance", camBrilliance);
  o.setFloat("camHighlights", camHighlights);
  o.setFloat("camShadows", camShadows);
  o.setFloat("camContrast", camContrast);
  o.setFloat("camBrightness", camBrightness);
  o.setFloat("camBlack", camBlack);
  o.setFloat("camSaturation", camSaturation);
  o.setFloat("camVibrance", camVibrance);
  o.setFloat("camWarmth", camWarmth);
  o.setFloat("camTint", camTint);
  o.setFloat("camSharp", camSharp);
  o.setFloat("camClarity", camClarity);
  o.setFloat("camNoise", camNoise);
  o.setFloat("camVignette", camVignette);
  o.setInt("testPattern", testPattern);
  o.setInt("curveChannel", curveChannel);
  if (curves != null) o.setJSONArray("curves", saveCurveBank(curves));
  return o;
}

void applySourceMemoryDefaults() {
  mirror = defaultMirrorForSource(sourceMode);
  camZoom = 1;
  camPanX = 0;
  camPanY = 0;
  camTwist = 0;
  liveCropL = 0;
  liveCropT = 0;
  liveCropR = 1;
  liveCropB = 1;
  liveCropEdit = false;
  liveCropDrag = -1;
  liveFeather = 0;
  liveFeatherFrame = -1;
  camScale = SCALE_FILL;
  camRotation = 0;
  camExposure = 0;
  camBrilliance = 0;
  camHighlights = 0;
  camShadows = 0;
  camContrast = 0;
  camBrightness = 0;
  camBlack = 0;
  camSaturation = 0;
  camVibrance = 0;
  camWarmth = 0;
  camTint = 0;
  camSharp = 0;
  camClarity = 0;
  camNoise = 0;
  camVignette = 0;
  resetAllCurves();
  curveChannel = 0;
}

void applySourceMemory(JSONObject o) {
  if (o == null) {
    applySourceMemoryDefaults();
    return;
  }
  mirror = o.getBoolean("mirror", defaultMirrorForSource(sourceMode));
  camZoom = constrain(o.getFloat("camZoom", 1), LIVE_ZOOM_MIN, LIVE_ZOOM_MAX);
  camPanX = o.getFloat("camPanX", 0);
  camPanY = o.getFloat("camPanY", 0);
  camTwist = o.getFloat("camTwist", 0);
  liveCropL = constrain(o.getFloat("liveCropL", 0), 0, 1);
  liveCropT = constrain(o.getFloat("liveCropT", 0), 0, 1);
  liveCropR = constrain(o.getFloat("liveCropR", 1), 0, 1);
  liveCropB = constrain(o.getFloat("liveCropB", 1), 0, 1);
  normalizeLiveCrop();
  liveCropEdit = false;
  liveCropDrag = -1;
  liveFeather = constrain(o.getFloat("liveFeather", 0), 0, 100);
  liveFeatherFrame = -1;
  camScale = o.getInt("camScale", SCALE_FILL);
  camRotation = o.getInt("camRotation", 0);
  camExposure = o.getFloat("camExposure", 0);
  camBrilliance = o.getFloat("camBrilliance", 0);
  camHighlights = o.getFloat("camHighlights", 0);
  camShadows = o.getFloat("camShadows", 0);
  camContrast = o.getFloat("camContrast", 0);
  camBrightness = o.getFloat("camBrightness", 0);
  camBlack = o.getFloat("camBlack", 0);
  camSaturation = o.getFloat("camSaturation", 0);
  camVibrance = o.getFloat("camVibrance", 0);
  camWarmth = o.getFloat("camWarmth", 0);
  camTint = o.getFloat("camTint", 0);
  camSharp = o.getFloat("camSharp", 0);
  camClarity = o.getFloat("camClarity", 0);
  camNoise = o.getFloat("camNoise", 0);
  camVignette = o.getFloat("camVignette", 0);
  if (o.hasKey("testPattern")) testPattern = constrain(o.getInt("testPattern", testPattern), 0, 2);
  curveChannel = constrain(o.getInt("curveChannel", 0), 0, 3);
  if (curves == null) initCurves();
  resetAllCurves();
  if (o.hasKey("curves")) loadCurveBank(o.getJSONArray("curves"), curves);
  curveDrag = -1;
  curveSel = -1;
}

/** Stash live grade/curves under the current source key. */
void rememberSourceSettings() {
  String key = currentSourceKey();
  if (key == null || key.length() == 0) return;
  if (sourceMemories == null) sourceMemories = new JSONObject();
  sourceMemories.setJSONObject(key, captureSourceMemory());
  sourceMemoryActiveKey = key;
}

/** Restore grade/curves for key (defaults if never seen). */
void recallSourceSettings(String key) {
  if (key == null || key.length() == 0) key = currentSourceKey();
  if (sourceMemories != null && sourceMemories.hasKey(key)) {
    applySourceMemory(sourceMemories.getJSONObject(key));
  } else {
    applySourceMemoryDefaults();
  }
  sourceMemoryActiveKey = key;
}

/**
 * Remember current source, then recall the next.
 * No-op when the identity does not change.
 */
void switchSourceMemory(String nextKey) {
  String prev = sourceMemoryActiveKey;
  if (prev == null || prev.length() == 0) prev = currentSourceKey();
  rememberSourceSettings();
  if (nextKey == null || nextKey.equals(prev)) {
    sourceMemoryActiveKey = nextKey == null ? prev : nextKey;
    return;
  }
  recallSourceSettings(nextKey);
}

void loadSourceMemories(JSONObject o) {
  if (o != null && o.hasKey("sourceMemories")) {
    sourceMemories = o.getJSONObject("sourceMemories");
  } else {
    sourceMemories = new JSONObject();
  }
  String key = currentSourceKey();
  if (sourceMemories.hasKey(key)) {
    // Prefer per-source snapshot over flat grade fields.
    applySourceMemory(sourceMemories.getJSONObject(key));
  } else {
    // Migration: first open — keep loaded globals as this source's memory.
    rememberSourceSettings();
  }
  sourceMemoryActiveKey = key;
}

void saveSourceMemories(JSONObject o) {
  rememberSourceSettings();
  if (sourceMemories == null) sourceMemories = new JSONObject();
  o.setJSONObject("sourceMemories", sourceMemories);
}
