boolean hwAutoExposure = false;
boolean hwAutoFocus = false;
boolean hwAutoWhite = false;
boolean hwLensLock = true;
boolean hwCenterStage = false;
float hwBias = 0;
float hwFocus = 0.5;
float hwZoom = 1;
int hwLens = -1;
boolean hwBiasTouched = false;
boolean hwFocusTouched = false;
boolean hwZoomTouched = false;

boolean hwDirty = true;
boolean hwApplied = false;
boolean hwLogged = false;
int hwTries = 0;
int hwNextTry = 0;

boolean hwFound = false;
boolean hwUvc = false;
boolean hwContinuity = false;
boolean hwExpLock = false;
boolean hwExpAuto = false;
boolean hwFocLock = false;
boolean hwFocAuto = false;
boolean hwWbLock = false;
boolean hwWbAuto = false;
boolean hwLensOk = false;
boolean hwStageOk = false;
boolean hwBiasOk = false;
boolean hwFocusOk = false;
boolean hwZoomOk = false;
float hwBiasMin = -2;
float hwBiasMax = 2;
float hwZoomMin = 1;
float hwZoomMax = 1;
int hwLensAt = -1;
int hwLensCount = 0;
String[] hwLensNames = new String[0];
String hwPrimary = "";
boolean hwPortrait = false;
boolean hwStudio = false;
String hwError = "";
String hwSeen = "";
byte[] hwStatusBuf = new byte[1600];

void loadHardwareLibrary() {
  CamCtl.load(sketchPath("data/libcamctl.dylib"));
  if (!CamCtl.loaded && CamCtl.fail.length() > 0) println(CamCtl.fail);
}

void requestHardware() {
  hwDirty = true;
  hwApplied = false;
  hwTries = 0;
  hwNextTry = 0;
}

int hwDebounceUntil = 0;

void serviceHardware() {
  if (sourceMode != SRC_CAM || cam == null) return;
  // Wait until the capture pipeline is alive, then talk UVC on the side-band.
  if (!camGotFrame) return;
  if (!CamCtl.loaded) {
    if (CamCtl.fail.length() > 0) return;
    loadHardwareLibrary();
    if (!CamCtl.loaded) return;
  }
  if (!hwDirty && hwApplied) return;
  if (millis() < hwNextTry) return;
  // Coalesce rapid slider moves so USB isn't hammered every frame.
  if (hwBiasTouched || hwFocusTouched || hwZoomTouched) {
    if (millis() < hwDebounceUntil) return;
    hwDebounceUntil = millis() + 40;
  }
  applyHardware();
}

String hardwareCameraUid() {
  CamEntry e = findCamByName(cameraName);
  if (e != null && e.uniqueId != null) return e.uniqueId;
  return "";
}

void applyHardware() {
  String name = cameraName == null ? "" : cameraName;
  String uid = hardwareCameraUid();
  int found = 0;
  try {
    found = CamCtl.configure(name, uid, hwStatusBuf,
      hwAutoExposure ? 1 : 0,
      hwAutoFocus ? 1 : 0,
      hwAutoWhite ? 1 : 0,
      hwLensLock ? 1 : 0,
      hwCenterStage ? 1 : 0,
      hwBias, hwFocus, hwZoom, hwLens,
      hwBiasTouched ? 1 : 0,
      hwFocusTouched ? 1 : 0,
      hwZoomTouched ? 1 : 0,
      hwLens >= 0 ? 1 : 0);
  } catch (Throwable t) {
    hwError = t.getMessage() == null ? "Camera control failed." : t.getMessage();
    hwFound = false;
    hwNextTry = millis() + 1000;
    hwTries++;
    if (hwTries > 6) hwDirty = false;
    return;
  }
  readHardwareStatus();
  hwFound = found == 1;
  if (!hwFound) {
    hwTries++;
    hwNextTry = millis() + 700;
    if (hwTries > 8) {
      hwDirty = false;
      hwApplied = true;
      if (hwError.length() == 0) hwError = hwSeen.length() == 0 ? "No controllable camera." : "Camera not matched.";
    }
    return;
  }
  hwTries = 0;
  hwDirty = false;
  hwApplied = true;
  hwError = "";
  if (!hwLogged) {
    hwLogged = true;
    println("Camera hardware locked.");
    System.out.flush();
  }
}

void readHardwareStatus() {
  int n = 0;
  while (n < hwStatusBuf.length && hwStatusBuf[n] != 0) n++;
  String line = new String(hwStatusBuf, 0, n);
  hwUvc = flag(line, "uvc");
  hwContinuity = flag(line, "cont");
  hwExpLock = flag(line, "expL");
  hwExpAuto = flag(line, "expA");
  hwFocLock = flag(line, "focL");
  hwFocAuto = flag(line, "focA");
  hwWbLock = flag(line, "wbL");
  hwWbAuto = flag(line, "wbA");
  hwLensOk = flag(line, "lensOk");
  hwStageOk = flag(line, "stageOk");
  hwBiasOk = flag(line, "biasOk");
  hwFocusOk = flag(line, "focOk");
  hwZoomOk = flag(line, "zoomOk");
  hwPortrait = flag(line, "portrait");
  hwStudio = flag(line, "studio");
  hwLensAt = (int) num(line, "lensAt", -1);
  hwLensCount = (int) num(line, "nlens", 0);
  hwBiasMin = num(line, "bmin", hwUvc ? 0 : -2);
  hwBiasMax = num(line, "bmax", hwUvc ? 1 : 2);
  hwZoomMin = num(line, "zmin", 1);
  hwZoomMax = num(line, "zmax", 1);
  if (!hwBiasTouched) hwBias = num(line, "bias", hwBias);
  if (!hwFocusTouched) hwFocus = num(line, "focus", hwFocus);
  if (!hwZoomTouched) hwZoom = num(line, "zoom", hwZoom);
  if (hwUvc) {
    // UVC exposure/focus use a normalized 0..1 range.
    if (hwBiasMin >= hwBiasMax) { hwBiasMin = 0; hwBiasMax = 1; }
    hwBias = constrain(hwBias, hwBiasMin, hwBiasMax);
    hwFocus = constrain(hwFocus, 0, 1);
  }
  hwPrimary = field(line, "primary");
  hwSeen = field(line, "seen");
  String err = field(line, "err");
  if (err.length() > 0) hwError = err.replace('+', ' ');
  String lenses = field(line, "lenses");
  if (lenses.length() == 0) hwLensNames = new String[0];
  else hwLensNames = lenses.split(",");
  if (hwLensCount > hwLensNames.length) hwLensCount = hwLensNames.length;
}

boolean flag(String line, String key) {
  return num(line, key, 0) > 0.5;
}

float num(String line, String key, float fallback) {
  String v = field(line, key);
  if (v.length() == 0) return fallback;
  try {
    return Float.parseFloat(v);
  } catch (NumberFormatException e) {
    return fallback;
  }
}

String field(String line, String key) {
  String token = key + "=";
  int at = 0;
  while (at >= 0 && at < line.length()) {
    int hit = line.indexOf(token, at);
    if (hit < 0) return "";
    if (hit == 0 || line.charAt(hit - 1) == '|') {
      int start = hit + token.length();
      int end = line.indexOf('|', start);
      if (end < 0) end = line.length();
      return line.substring(start, end);
    }
    at = hit + token.length();
  }
  return "";
}

void onHardwareClick(String id) {
  if (id.equals("hw-exp-off")) hwAutoExposure = false;
  else if (id.equals("hw-exp-on")) hwAutoExposure = true;
  else if (id.equals("hw-foc-off")) hwAutoFocus = false;
  else if (id.equals("hw-foc-on")) hwAutoFocus = true;
  else if (id.equals("hw-wb-off")) hwAutoWhite = false;
  else if (id.equals("hw-wb-on")) hwAutoWhite = true;
  else if (id.equals("hw-lensauto-off")) hwLensLock = true;
  else if (id.equals("hw-lensauto-on")) hwLensLock = false;
  else if (id.equals("hw-stage-off")) hwCenterStage = false;
  else if (id.equals("hw-stage-on")) hwCenterStage = true;
  else if (id.startsWith("hw-lens#")) {
    hwLens = constrain(int(id.substring(8)), 0, max(0, hwLensCount - 1));
  } else return;
  hwDirty = true;
  hwApplied = false;
  hwTries = 0;
  markDirty();
}

void loadHardwareSettings(JSONObject o) {
  hwAutoExposure = o.getBoolean("hwAutoExposure", false);
  hwAutoFocus = o.getBoolean("hwAutoFocus", false);
  hwAutoWhite = o.getBoolean("hwAutoWhite", false);
  hwLensLock = o.getBoolean("hwLensLock", true);
  hwCenterStage = o.getBoolean("hwCenterStage", false);
  hwBias = o.getFloat("hwBias", 0);
  hwFocus = o.getFloat("hwFocus", 0.5);
  hwZoom = o.getFloat("hwZoom", 1);
  hwLens = o.getInt("hwLens", -1);
  hwBiasTouched = o.getBoolean("hwBiasTouched", false);
  hwFocusTouched = o.getBoolean("hwFocusTouched", false);
  hwZoomTouched = o.getBoolean("hwZoomTouched", false);
}

void saveHardwareSettings(JSONObject o) {
  o.setBoolean("hwAutoExposure", hwAutoExposure);
  o.setBoolean("hwAutoFocus", hwAutoFocus);
  o.setBoolean("hwAutoWhite", hwAutoWhite);
  o.setBoolean("hwLensLock", hwLensLock);
  o.setBoolean("hwCenterStage", hwCenterStage);
  o.setFloat("hwBias", hwBias);
  o.setFloat("hwFocus", hwFocus);
  o.setFloat("hwZoom", hwZoom);
  o.setInt("hwLens", hwLens);
  o.setBoolean("hwBiasTouched", hwBiasTouched);
  o.setBoolean("hwFocusTouched", hwFocusTouched);
  o.setBoolean("hwZoomTouched", hwZoomTouched);
}
