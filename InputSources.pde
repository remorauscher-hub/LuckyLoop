String[] cameras = new String[0];
ArrayList<CamEntry> camEntries = new ArrayList<CamEntry>();
int camScroll = 0;
Capture cam;
volatile boolean camGotFrame = false;
boolean camLiveOk = false; // true after a healthy stream; stops watchdog thrash
int camSeenW;
int camSeenH;
int camStable;
volatile boolean camSizeChanged;
volatile boolean camerasScanning = false;
boolean continuityOptIn = false;
boolean continuitySeen = false;
String continuityHint = "";

SyphonServer server;
SyphonClient client;
PGraphics syphonFrame;
ArrayList<SyEntry> syEntries = new ArrayList<SyEntry>();
int syIndex = 0;
String syphonStatus = "Syphon off";

PGraphics scaleGfx;
PGraphics testGfx;
int scaleFilter = -1;

class CamEntry {
  String label;
  String openKey;
  String uniqueId;
  boolean continuity;
  boolean gst;
  int gstIndex; // index in Capture.list() / avfvideosrc device-index; -1 if unknown

  CamEntry(String label, String openKey, String uniqueId, boolean continuity, boolean gst) {
    this(label, openKey, uniqueId, continuity, gst, -1);
  }

  CamEntry(String label, String openKey, String uniqueId, boolean continuity, boolean gst, int gstIndex) {
    this.label = label == null ? "Camera" : label;
    this.openKey = openKey == null ? this.label : openKey;
    this.uniqueId = uniqueId == null ? "" : uniqueId;
    this.continuity = continuity;
    this.gst = gst;
    this.gstIndex = gstIndex;
  }

  String shortLabel() {
    if (continuity) {
      String n = label;
      int at = n.indexOf(" (");
      if (at > 0) n = n.substring(0, at);
      return n;
    }
    return label;
  }
}

class SyEntry {
  String app;
  String server;
  String label;
  SyEntry(String app, String server, String label) {
    this.app = app == null ? "" : app;
    this.server = server == null ? "" : server;
    this.label = label;
  }
}

void ensureCamCtl() {
  if (CamCtl.loaded) return;
  loadHardwareLibrary();
}

void dumpCameraDiag(String[] gst) {
  try {
    String path = sketchPath("data/camera-diag.txt");
    String[] lines = new String[0];
    lines = append(lines, "time=" + year() + "-" + nf(month(), 2) + "-" + nf(day(), 2) + " " + nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2));
    lines = append(lines, "continuityOptIn=" + continuityOptIn);
    lines = append(lines, "continuitySeen=" + continuitySeen);
    lines = append(lines, "camCtlLoaded=" + CamCtl.loaded + " fail=" + CamCtl.fail);
    lines = append(lines, "gstCount=" + (gst == null ? -1 : gst.length));
    if (gst != null) {
      for (int i = 0; i < gst.length; i++) lines = append(lines, "gst[" + i + "]=" + gst[i]);
    }
    lines = append(lines, "entries=" + camEntries.size());
    for (int i = 0; i < camEntries.size(); i++) {
      CamEntry e = camEntries.get(i);
      lines = append(lines, "cam[" + i + "] label=" + e.label + " cont=" + e.continuity + " gst=" + e.gst + " gstIndex=" + e.gstIndex + " uid=" + e.uniqueId);
    }
    lines = append(lines, "hint=" + continuityHint);
    saveStrings(path, lines);
    println("Wrote " + path);
  } catch (Throwable t) {
    println("diag: " + t.getMessage());
  }
}

void refreshCameras() {
  ArrayList<CamEntry> next = new ArrayList<CamEntry>();
  try {
    String[] gst = null;
    try {
      gst = Capture.list();
    } catch (Throwable t) {
      println("Capture.list: " + t.getMessage());
    }
    if (gst == null) gst = new String[0];

    for (int i = 0; i < gst.length; i++) {
      String name = gst[i];
      if (name == null || name.length() == 0) continue;
      boolean cont = looksLikeContinuity(name);
      // Keep Capture.list() index — avfvideosrc device-index uses this order (not our UI sort).
      next.add(new CamEntry(name, name, "", cont, true, i));
    }

    ensureCamCtl();
    continuityOptIn = false;
    continuitySeen = false;
    if (CamCtl.loaded) {
      try {
        continuityOptIn = CamCtl.continuityOptIn() == 1;
      } catch (Throwable t) {
        continuityOptIn = false;
      }
      try {
        String[] avf = CamCtl.listDevices();
        if (avf != null) {
          for (int i = 0; i < avf.length; i++) {
            CamEntry e = parseAvfDevice(avf[i]);
            if (e == null) continue;
            if (e.continuity) continuitySeen = true;
            int hit = findCamEntry(next, e.label, e.uniqueId);
            if (hit >= 0) {
              CamEntry cur = next.get(hit);
              cur.continuity = cur.continuity || e.continuity;
              if (cur.uniqueId.length() == 0) cur.uniqueId = e.uniqueId;
              if (e.continuity && !cur.label.toLowerCase().contains("iphone")
                  && e.label.toLowerCase().contains("iphone")) {
                cur.label = e.label;
              }
            } else {
              // GStreamer DeviceMonitor often omits Continuity Camera — open via unique ID.
              String key = e.uniqueId.length() > 0
                ? "pipeline:avfvideosrc device=" + e.uniqueId
                : "pipeline:avfvideosrc device-name=\"" + e.label.replace("\"", "") + "\"";
              next.add(new CamEntry(e.label, key, e.uniqueId, e.continuity || looksLikeContinuity(e.label), false));
            }
          }
        }
      } catch (Throwable t) {
        println("CamCtl.listDevices: " + t.getMessage());
      }
    }
    for (int i = 0; i < next.size(); i++) {
      if (next.get(i).continuity) continuitySeen = true;
    }
    continuityHint = buildContinuityHint();

    sortCamEntries(next);
    camEntries = next;
    cameras = new String[camEntries.size()];
    for (int i = 0; i < camEntries.size(); i++) cameras[i] = camEntries.get(i).label;

    if (cameras.length == 0) inputError = "No camera found";
    else if (cameraName == null || cameraName.length() == 0 || !cameraListed(cameraName)) {
      cameraName = preferIphoneEntry();
      inputError = "";
    } else {
      inputError = "";
    }
    dumpCameraDiag(gst);
  } catch (Throwable t) {
    cameras = new String[0];
    camEntries = new ArrayList<CamEntry>();
    inputError = "Cameras: " + t.getMessage();
    dumpCameraDiag(new String[0]);
  }
}

String buildContinuityHint() {
  if (continuitySeen) return "";
  if (!continuityOptIn) {
    return "macOS hides Continuity Camera from this sketch JVM. Run enable-iphone-camera.command (patches Processing + Java runtime), Cmd+Q, reopen, Refresh.";
  }
  return "No Continuity Camera yet. Unlock iPhone nearby, same Apple ID, Wi‑Fi + Bluetooth on, then Refresh.";
}

CamEntry parseAvfDevice(String row) {
  if (row == null || row.length() == 0) return null;
  String[] parts = split(row, '\t');
  if (parts.length < 1) return null;
  String name = parts[0];
  String uid = parts.length > 1 ? parts[1] : "";
  boolean cont = parts.length > 2 && parts[2].equals("1");
  return new CamEntry(name, name, uid, cont || looksLikeContinuity(name), false);
}

boolean looksLikeContinuity(String name) {
  if (name == null) return false;
  String n = name.toLowerCase();
  return n.contains("iphone") || n.contains("ipad") || n.contains("continuity")
    || n.contains("kontinuit") || n.contains("continuity camera");
}

int findCamEntry(ArrayList<CamEntry> list, String name, String uid) {
  if (uid != null && uid.length() > 0) {
    for (int i = 0; i < list.size(); i++) {
      if (uid.equals(list.get(i).uniqueId)) return i;
    }
  }
  if (name == null || name.length() == 0) return -1;
  String want = name.toLowerCase();
  for (int i = 0; i < list.size(); i++) {
    String have = list.get(i).label.toLowerCase();
    if (have.equals(want)) return i;
    if (have.startsWith(want + " #")) return i;
    if (want.startsWith(have + " #")) return i;
    if (have.contains(want) || want.contains(have)) return i;
  }
  return -1;
}

void sortCamEntries(ArrayList<CamEntry> list) {
  for (int i = 0; i < list.size(); i++) {
    for (int j = i + 1; j < list.size(); j++) {
      int si = camSortScore(list.get(i));
      int sj = camSortScore(list.get(j));
      if (sj < si || (sj == si && list.get(j).label.compareToIgnoreCase(list.get(i).label) < 0)) {
        CamEntry tmp = list.get(i);
        list.set(i, list.get(j));
        list.set(j, tmp);
      }
    }
  }
}

int camSortScore(CamEntry e) {
  if (e.continuity) return 0;
  String n = e.label.toLowerCase();
  if (n.contains("facetime") || n.contains("built-in") || n.contains("studio display")) return 2;
  return 1;
}

String preferIphoneEntry() {
  for (int i = 0; i < camEntries.size(); i++) {
    if (camEntries.get(i).continuity) return camEntries.get(i).label;
  }
  for (int i = 0; i < camEntries.size(); i++) {
    if (looksLikeContinuity(camEntries.get(i).label)) return camEntries.get(i).label;
  }
  // Prefer USB webcams (Logitech C922 etc.) over built-in FaceTime.
  for (int i = 0; i < camEntries.size(); i++) {
    if (camSortScore(camEntries.get(i)) == 1) return camEntries.get(i).label;
  }
  return camEntries.size() > 0 ? camEntries.get(0).label : "";
}

boolean cameraListed(String name) {
  return findCamByName(name) != null;
}

CamEntry findCamByName(String name) {
  if (name == null) return null;
  for (int i = 0; i < camEntries.size(); i++) {
    CamEntry e = camEntries.get(i);
    if (e.label.equals(name) || e.openKey.equals(name)) return e;
  }
  return null;
}

CamEntry selectedCamEntry() {
  CamEntry e = findCamByName(cameraName);
  if (e != null) return e;
  return camEntries.size() > 0 ? camEntries.get(0) : null;
}

int camStartMs = 0;
int camModeAttempt = 0;
int[][] camModeList = new int[0][];
String camOpenDevice = "";
int camIdPhase = 0; // 0=pending, 1=wait dark, -1=done
int camIdAt = 0;
float camIdBaseline = 0;
float camIdSavedBias = 0;
boolean camIdSavedTouch = false;

boolean isUsbWebcam(CamEntry entry) {
  if (entry == null) return false;
  if (entry.continuity) return false;
  String n = entry.label.toLowerCase();
  if (n.contains("facetime") || n.contains("built-in") || n.contains("studio display")) return false;
  return n.contains("c922") || n.contains("c920") || n.contains("c910") || n.contains("c930")
    || n.contains("logitech") || n.contains("webcam") || n.contains("usb");
}

String cameraDeviceKey(CamEntry entry) {
  if (entry == null) return "";
  if (entry.gst && entry.openKey != null && entry.openKey.length() > 0
      && !entry.openKey.startsWith("pipeline:")) {
    return entry.openKey;
  }
  return entry.label;
}

/**
 * USB cams (C922): Capture's Device.createElement path fails with stream errors.
 * device-name is not writable on this GStreamer build — use device-index.
 * IMPORTANT: Capture.list() order flips between calls; always resolve index fresh.
 */
int freshGstIndex(CamEntry entry) {
  if (entry == null) return -1;
  try {
    String[] list = Capture.list();
    if (list == null) return -1;
    String label = entry.label;
    String key = cameraDeviceKey(entry);
    for (int i = 0; i < list.length; i++) {
      if (list[i] == null) continue;
      if (list[i].equals(label) || list[i].equals(key)) {
        println("GST index " + i + " = " + list[i]);
        return i;
      }
    }
    println("GST index miss for " + label + " in " + join(list, " | "));
  } catch (Throwable t) {
    println("GST index: " + t.getMessage());
  }
  return -1;
}

/**
 * USB: device-index only. Hard source caps (esp. framerate=30/1) make avfvideosrc
 * fail on macOS — Capture already sets appsink size/fps; prefer matching 16:9 modes.
 */
String usbPipelineKey(CamEntry entry, int[] mode) {
  int idx = freshGstIndex(entry);
  if (idx < 0) idx = entry.gstIndex;
  if (idx < 0) return cameraDeviceKey(entry);
  entry.gstIndex = idx;
  return "pipeline:avfvideosrc device-index=" + idx;
}

String cameraOpenKey(CamEntry entry) {
  return cameraOpenKey(entry, null);
}

/**
 * Continuity: uniqueId path. Size-only caps (no framerate=N/1 — breaks AVF on macOS).
 * Capture constructor still asks 720p30 so videorate isn't forced 30→25.
 */
String continuityPipelineKey(CamEntry entry, int[] mode) {
  int w = mode != null && mode.length >= 2 ? mode[0] : 1280;
  int h = mode != null && mode.length >= 2 ? mode[1] : 720;
  String caps = " ! video/x-raw,width=" + w + ",height=" + h;
  if (entry.uniqueId != null && entry.uniqueId.length() > 0) {
    return "pipeline:avfvideosrc device=" + entry.uniqueId + caps;
  }
  String safe = entry.label.replace("\"", "");
  return "pipeline:avfvideosrc device-name=\"" + safe + "\"" + caps;
}

String cameraOpenKey(CamEntry entry, int[] mode) {
  if (entry == null) return "";
  if (entry.continuity || looksLikeContinuity(entry.label)) {
    return continuityPipelineKey(entry, mode);
  }
  if (!entry.gst) {
    // AVF-only Continuity already stores a pipeline openKey — keep uniqueId path.
    if (entry.openKey != null && entry.openKey.startsWith("pipeline:")) {
      return continuityPipelineKey(entry, mode);
    }
    String safe = entry.label.replace("\"", "");
    return "pipeline:avfvideosrc device-name=\"" + safe + "\"";
  }
  if (isUsbWebcam(entry)) return usbPipelineKey(entry, mode);
  return cameraDeviceKey(entry);
}

int[][] cameraModeCandidates(CamEntry entry) {
  ArrayList<int[]> modes = new ArrayList<int[]>();
  modes.add(chooseCaptureMode(entry));
  if (entry != null && (entry.continuity || looksLikeContinuity(entry.label))) {
    // Wireless Continuity: 720p30 first. 1080p@25 forces videorate drops → stutter.
    int[][] cont = {
      { 1280, 720, 30 },
      { 1280, 720, 25 },
      { 1920, 1080, 30 },
      { 1920, 1080, 25 },
      { 960, 540, 30 },
      { 640, 360, 30 }
    };
    for (int i = 0; i < cont.length; i++) modes.add(cont[i]);
  } else if (isUsbWebcam(entry)) {
    // Prefer true 16:9 modes first — 4:3 forced through a 16:9 sink looks skewed.
    int[][] usb = {
      { 1280, 720, 30 },
      { 1920, 1080, 30 },
      { 960, 540, 30 },
      { 640, 360, 30 },
      { 640, 480, 30 },
      { 800, 600, 30 }
    };
    for (int i = 0; i < usb.length; i++) modes.add(usb[i]);
  } else {
    modes.add(new int[] { capW, capH, max(1, capFps) });
    modes.add(new int[] { 1280, 720, 30 });
    modes.add(new int[] { 640, 480, 30 });
  }
  ArrayList<int[]> out = new ArrayList<int[]>();
  for (int i = 0; i < modes.size(); i++) {
    int[] m = modes.get(i);
    boolean seen = false;
    for (int j = 0; j < out.size(); j++) {
      int[] o = out.get(j);
      if (o[0] == m[0] && o[1] == m[1] && o[2] == m[2]) { seen = true; break; }
    }
    if (!seen) out.add(m);
  }
  return out.toArray(new int[0][]);
}

boolean openCameraWith(CamEntry entry, String openKey, int[] mode) {
  try {
    // Rebuild pipeline with this mode's caps so videoscale/videorate stay 1:1.
    String key = openKey;
    if (isUsbWebcam(entry) || (entry != null && (entry.continuity || looksLikeContinuity(entry.label)))) {
      key = cameraOpenKey(entry, mode);
    }
    cam = new Capture(this, mode[0], mode[1], key, mode[2]);
    cam.start();
    cameraName = entry.label;
    camOpenDevice = key;
    inputError = "";
    println("Camera " + entry.label + " via " + key + " "
      + mode[0] + "×" + mode[1] + " @ " + mode[2]);
    System.out.flush();
    camStartMs = millis();
    camGotFrame = false;
    camLiveOk = false;
    // Identity pulse (dark exposure) stutters the USB stream — skip in normal use.
    camIdPhase = -1;
    requestHardware();
    return true;
  } catch (Exception e) {
    cam = null;
    println("Camera open failed: " + openKey + " " + mode[0] + "x" + mode[1]
      + "@" + mode[2] + " — " + e.getMessage());
    return false;
  }
}

float sampleCamLuma() {
  if (cam == null || cam.width < 2) return 0;
  cam.loadPixels();
  if (cam.pixels == null || cam.pixels.length < 16) return 0;
  long sum = 0;
  int n = 0;
  int step = max(1, cam.pixels.length / 800);
  for (int i = 0; i < cam.pixels.length; i += step) {
    int c = cam.pixels[i];
    int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    sum += (r * 3 + g * 6 + b) / 10;
    n++;
  }
  return n == 0 ? 0 : (float) sum / n;
}

void serviceCameraIdentity() {
  if (camIdPhase < 0 || sourceMode != SRC_CAM || cam == null || !camGotFrame) return;
  CamEntry entry = selectedCamEntry();
  if (entry == null || !isUsbWebcam(entry)) { camIdPhase = -1; return; }

  if (camIdPhase == 0 && millis() - camStartMs > 600) {
    camIdBaseline = sampleCamLuma();
    camIdSavedBias = hwBias;
    camIdSavedTouch = hwBiasTouched;
    hwAutoExposure = false;
    hwBias = 0;
    hwBiasTouched = true;
    hwDirty = true;
    hwApplied = false;
    applyHardware();
    camIdPhase = 1;
    camIdAt = millis();
    return;
  }
  if (camIdPhase == 1 && millis() - camIdAt > 450) {
    float dark = sampleCamLuma();
    boolean ok = (camIdBaseline > 12 && dark < camIdBaseline * 0.6f)
      || (camIdBaseline - dark) > 18;
    println("Camera identity check: baseline=" + nf(camIdBaseline, 1, 1)
      + " dark=" + nf(dark, 1, 1) + " match=" + ok
      + " via " + camOpenDevice);
    System.out.flush();
    hwBias = camIdSavedBias;
    hwBiasTouched = camIdSavedTouch;
    hwDirty = true;
    hwApplied = false;
    applyHardware();
    camIdPhase = -1;
    if (!ok) retryUsbCameraAlternateIndex(entry);
  }
}

void retryUsbCameraAlternateIndex(CamEntry entry) {
  int used = entry.gstIndex;
  int alt = -1;
  try {
    String[] list = Capture.list();
    if (list == null || list.length < 2) return;
    // Prefer the other index whose display name equals our camera.
    for (int i = 0; i < list.length; i++) {
      if (i == used) continue;
      if (list[i] != null && list[i].equals(entry.label)) { alt = i; break; }
    }
    // Two-device swap: DeviceMonitor order often flips FaceTime ↔ C922.
    if (alt < 0 && list.length == 2 && used >= 0 && used < 2) alt = 1 - used;
    if (alt < 0) {
      for (int i = 0; i < list.length; i++) {
        if (i == used || list[i] == null) continue;
        String n = list[i].toLowerCase();
        if (n.contains("facetime") || n.contains("built-in")) continue;
        alt = i;
        break;
      }
    }
  } catch (Throwable t) {
    return;
  }
  if (alt < 0 || alt == used) return;
  println("Wrong USB camera stream — reopening as device-index=" + alt + " (was " + used + ")");
  System.out.flush();
  entry.gstIndex = alt;
  int[] mode = (camModeList != null && camModeAttempt < camModeList.length)
    ? camModeList[camModeAttempt] : new int[] { 1280, 720, 30 };
  stopCamera();
  openCameraWith(entry, cameraOpenKey(entry, mode), mode);
}

void startCamera() {
  stopCamera();
  camModeAttempt = 0;
  if (camEntries == null || camEntries.size() == 0) {
    inputError = "No camera. Connect iPhone as a Continuity Camera, then Refresh.";
    return;
  }
  CamEntry entry = selectedCamEntry();
  if (entry == null) {
    inputError = "No camera.";
    return;
  }
  cameraName = entry.label;
  camModeList = cameraModeCandidates(entry);
  for (int i = 0; i < camModeList.length; i++) {
    if (openCameraWith(entry, cameraOpenKey(entry, camModeList[i]), camModeList[i])) {
      camModeAttempt = i;
      return;
    }
  }
  // Fallback: plain device name (FaceTime-style DeviceMonitor path).
  if (!isUsbWebcam(entry)) {
    String fallback = cameraDeviceKey(entry);
    for (int i = 0; i < camModeList.length; i++) {
      if (openCameraWith(entry, fallback, camModeList[i])) {
        camModeAttempt = i;
        return;
      }
    }
  }
  inputError = entry.continuity ? "iPhone camera unavailable" : "Camera unavailable";
}

void serviceCameraWatchdog() {
  if (sourceMode != SRC_CAM || cam == null || camGotFrame) return;
  // Once the stream has been healthy, don't thrash modes on brief USB hiccups.
  if (camLiveOk) {
    if (camStartMs > 0 && millis() - camStartMs < 5000) return;
  } else if (camStartMs <= 0 || millis() - camStartMs < 3500) {
    return;
  }
  CamEntry entry = selectedCamEntry();
  if (entry == null || camModeList == null || camModeList.length == 0) return;
  if (camLiveOk) {
    // Soft recover: reopen same mode once, don't drop to 640×480.
    println("Camera watchdog: stream stalled, reopening same mode");
    stopCamera();
    int mi = max(0, min(camModeAttempt, camModeList.length - 1));
    openCameraWith(entry, cameraOpenKey(entry, camModeList[mi]), camModeList[mi]);
    return;
  }
  int next = camModeAttempt + 1;
  if (next >= camModeList.length) {
    inputError = "No signal from " + entry.label;
    return;
  }
  println("Camera watchdog: no frames from " + entry.label + ", next mode");
  stopCamera();
  if (openCameraWith(entry, cameraOpenKey(entry, camModeList[next]), camModeList[next])) camModeAttempt = next;
}

int[] chooseCaptureMode(CamEntry entry) {
  int wantW = capW;
  int wantH = capH;
  int wantFps = capFps;
  String label = entry == null ? "" : entry.label.toLowerCase();
  boolean continuity = entry != null && (entry.continuity || looksLikeContinuity(entry.label));
  // USB webcams (Logitech C9xx): prefer 720p30 — GStreamer is flaky on 1080p for some C922s.
  boolean usbCam = label.contains("c922") || label.contains("c920") || label.contains("c910")
    || label.contains("c930") || label.contains("logitech") || label.contains("webcam");
  if (continuity) {
    // Continuity over Wi‑Fi: stay at 720p30. Asking 1080p@projectFps makes videorate drop frames.
    wantW = 1280;
    wantH = 720;
    wantFps = 30;
  } else if (usbCam) {
    if (wantFps == 25 || wantFps == 24) wantFps = 30;
    if (wantW >= 1920) { wantW = 1280; wantH = 720; }
  }
  int[] fallback = new int[] { wantW, wantH, wantFps };
  if (entry == null || !entry.gst || continuity) return fallback;
  String[] caps = null;
  try {
    caps = Capture.getCapabilities(entry.openKey);
  } catch (Throwable t) {
    return fallback;
  }
  if (caps == null || caps.length == 0) return fallback;
  int bestW = wantW;
  int bestH = wantH;
  int bestFps = wantFps;
  long best = Long.MAX_VALUE;
  boolean found = false;
  for (int i = 0; i < caps.length; i++) {
    int[] m = parseCaptureCap(caps[i]);
    if (m == null) continue;
    long dw = m[0] - wantW;
    long dh = m[1] - wantH;
    long df = m[2] - wantFps;
    long score = dw * dw + dh * dh + df * df * 2500L;
    // Prefer exact fps, then higher resolution near target.
    if (m[2] == wantFps) score -= 50000L;
    if (score < best) {
      best = score;
      bestW = m[0];
      bestH = m[1];
      bestFps = max(1, m[2]);
      found = true;
    }
  }
  if (!found) return fallback;
  return new int[] { bestW, bestH, bestFps };
}

int[] parseCaptureCap(String cap) {
  if (cap == null) return null;
  int s = cap.indexOf("size=");
  int fpsAt = cap.indexOf("fps=");
  if (s < 0 || fpsAt < 0) return null;
  int x = cap.indexOf("x", s + 5);
  if (x < 0) return null;
  int hEnd = cap.indexOf(",", x);
  if (hEnd < 0) hEnd = fpsAt;
  int w = parseInt(cap.substring(s + 5, x).trim());
  int h = parseInt(cap.substring(x + 1, hEnd).trim());
  int fps = parseInt(cap.substring(fpsAt + 4).replaceAll("[^0-9]", ""));
  if (w < 160 || h < 120 || fps < 1) return null;
  return new int[] { w, h, fps };
}

void stopCamera() {
  if (cam != null) {
    try {
      cam.stop();
    } catch (Exception e) {
    }
    cam = null;
  }
  camGotFrame = false;
  camSeenW = 0;
  camSeenH = 0;
  camStable = 0;
  camSizeChanged = false;
  // camLiveOk stays — tells watchdog not to cascade through low-res modes
}

void captureEvent(Capture c) {
  c.read();
  if (c != cam) return;
  int w = c.width;
  int h = c.height;
  if (w < 2 || h < 2) return;
  // Pipeline captures often report sourceWidth/Height that disagree with the
  // appsink size — dropping those frames caused stutter + watchdog reopen loops.
  if (w != camSeenW || h != camSeenH) {
    camSeenW = w;
    camSeenH = h;
    camStable = 0;
    camSizeChanged = true;
    // Keep showing while the new size settles — don't clear camGotFrame.
  }
  camStable++;
  if (camStable >= 1) {
    camGotFrame = true;
    camLiveOk = true;
  }
}

void refreshSyphon() {
  syEntries.clear();
  try {
    HashMap<String, String>[] list = SyphonClient.listServers();
    if (list != null) {
      for (int i = 0; i < list.length; i++) {
        if (list[i] == null) continue;
        String app = list[i].get("AppName");
        String name = list[i].get("ServerName");
        if (name != null && (name.equals("LuckyLoop") || name.equals("Lucky Loop") || name.equals("Video Looper"))) continue;
        String label = (name == null || name.length() == 0) ? (app == null ? "Server" : app) : app + " — " + name;
        syEntries.add(new SyEntry(app, name, label));
      }
    }
    if (savedSyApp.length() > 0) {
      for (int i = 0; i < syEntries.size(); i++) {
        SyEntry e = syEntries.get(i);
        if (e.app.equals(savedSyApp) && e.server.equals(savedSyServer)) syIndex = i;
      }
    }
    if (syEntries.isEmpty()) inputError = "No Syphon server";
    else inputError = "";
  } catch (Throwable t) {
    inputError = "Syphon list: " + t.getMessage();
  }
}

void connectSyphon() {
  stopSyphonClient();
  if (syEntries.isEmpty()) refreshSyphon();
  if (syEntries.isEmpty()) {
    inputError = "No Syphon server. Start Camera Live, OBS, or Syphoner.";
    return;
  }
  syIndex = constrain(syIndex, 0, syEntries.size() - 1);
  SyEntry e = syEntries.get(syIndex);
  try {
    if (e.server != null && e.server.length() > 0) client = new SyphonClient(this, e.app, e.server);
    else client = new SyphonClient(this, e.app);
    inputError = "";
  } catch (Exception ex) {
    client = null;
    inputError = "Syphon connection failed";
    println(ex);
  }
}

void stopSyphonClient() {
  if (client != null) {
    try {
      client.stop();
    } catch (Exception e) {
    }
    client = null;
  }
  syphonFrame = null;
}

void ensureSyphonServer() {
  if (server != null) {
    syphonStatus = "Syphon “LuckyLoop”";
    return;
  }
  try {
    server = new SyphonServer(this, "LuckyLoop");
    syphonStatus = "Syphon “LuckyLoop”";
  } catch (Throwable t) {
    server = null;
    syphonOut = false;
    syphonStatus = "Syphon unavailable";
    println(t);
  }
}

void refreshLive() {
  boolean force = liveFrameDirty;
  if (sourceMode == SRC_TEST) {
    if (force || frameCount % 2 == 0) drawTestPattern();
    liveFrameDirty = false;
    return;
  }
  if (sourceMode == SRC_CAM) {
    if (camSizeChanged && cam != null) {
      camSizeChanged = false;
      try {
        g.removeCache(cam);
      } catch (Exception e) {
      }
      // Fall through and still blit — skipping the frame made Continuity feel droppy.
    }
    if ((camGotFrame || force) && cam != null && cam.width > 1 && cam.height > 1) {
      blitCover(cam, mirror);
      liveFrameDirty = false;
    }
    return;
  }
  if (sourceMode == SRC_TETHER) {
    refreshTetherFrame();
    if (tetherImg != null && tetherImg.width > 1) {
      blitCover(tetherImg, mirror);
      liveFrameDirty = false;
    }
    return;
  }
  if (sourceMode == SRC_SYPHON && client != null) {
    try {
      if (client.newFrame()) syphonFrame = client.getGraphics(syphonFrame);
    } catch (Exception e) {
      inputError = "Syphon frame lost";
    }
    if (syphonFrame != null && syphonFrame.width > 1) {
      blitCover(syphonFrame, mirror);
      liveFrameDirty = false;
    }
  }
}

/**
 * Uniform cover/fit framing into dest. Used for live (scaleGfx) and stoptrick stack view.
 * twistDeg is absolute view rotation (live: camRotation+camTwist; stop: stopTwist only).
 */
void frameCoverInto(PGraphics dest, PImage src, boolean doMirror,
                    float zoom, float panXN, float panYN, float twistDeg) {
  if (dest == null || src == null || src.width < 2 || src.height < 2) return;
  float pw = src.width;
  float ph = src.height;
  float ang = twistDeg;
  float rad = radians(ang);
  float ca = abs(cos(rad));
  float sa = abs(sin(rad));
  float boundW = max(1e-6f, pw * ca + ph * sa);
  float boundH = max(1e-6f, pw * sa + ph * ca);
  zoom = constrain(zoom, LIVE_ZOOM_MIN, LIVE_ZOOM_MAX);
  float sFill = max(capW / boundW, capH / boundH);
  float sFit = min(capW / boundW, capH / boundH);
  float s = sFill * zoom;
  if (camScale == SCALE_FIT) s = sFit * zoom;
  else if (camScale == SCALE_ONE) s = zoom;
  float dw = pw * s;
  float dh = ph * s;
  float drawnW = dw * ca + dh * sa;
  float drawnH = dw * sa + dh * ca;
  // ±1 ≈ crop-room (or half-frame when fill≈1×). Values beyond ±1 push past the box.
  float roomX = abs(drawnW - capW) * 0.5f;
  float roomY = abs(drawnH - capH) * 0.5f;
  if (roomX < capW * 0.01f) roomX = capW * 0.5f;
  if (roomY < capH * 0.01f) roomY = capH * 0.5f;
  float panX = panXN * roomX;
  float panY = panYN * roomY;

  dest.beginDraw();
  dest.background(0);
  dest.pushMatrix();
  dest.translate(capW / 2f + panX, capH / 2f + panY);
  if (doMirror) dest.scale(-1, 1);
  dest.rotate(rad);
  dest.imageMode(CENTER);
  dest.image(src, 0, 0, dw, dh);
  dest.imageMode(CORNER);
  dest.popMatrix();
  dest.endDraw();
}

void blitCover(PImage src, boolean doMirror) {
  if (src == null || src.width < 2 || src.height < 2 || livePixels == null) return;
  if (scaleGfx == null || scaleGfx.width != capW || scaleGfx.height != capH) {
    scaleGfx = frameGraphics(capW, capH);
    scaleFilter = -1;
  }
  if (src instanceof Capture) {
    Capture live = (Capture) src;
    if (live.pixels != null && live.pixels.length > 0
        && live.sourceWidth > 1 && live.sourceHeight > 1
        && live.pixels.length != live.width * live.height
        && live.pixels.length != live.sourceWidth * live.sourceHeight) {
      return;
    }
  }
  int wantFilter = camScale == SCALE_ONE ? 0 : 2;
  if (scaleFilter != wantFilter) {
    if (wantFilter == 0) scaleGfx.noSmooth();
    else scaleGfx.smooth(2);
    scaleFilter = wantFilter;
  }
  frameCoverInto(scaleGfx, src, doMirror, camZoom, camPanX, camPanY, liveCoverAngle());
  applyLiveCropBlit();
  sourceGfx = scaleGfx;
  liveValid = true;
}

void drawTestPattern() {
  if (testGfx == null || testGfx.width != capW || testGfx.height != capH) {
    testGfx = frameGraphics(capW, capH);
  }
  testGfx.beginDraw();
  if (testPattern == TEST_BARS) drawBarsPattern();
  else if (testPattern == TEST_GRID) drawGridPattern();
  else drawCheckerPattern();
  testGfx.endDraw();
  sourceGfx = testGfx;
  liveValid = true;
}

void drawCheckerPattern() {
  int cell = max(24, capW / 16);
  int cols = (capW + cell - 1) / cell;
  int rows = (capH + cell - 1) / cell;
  testGfx.noStroke();
  for (int y = 0; y < rows; y++) {
    for (int x = 0; x < cols; x++) {
      testGfx.fill(((x + y) & 1) == 0 ? #e6e6e6 : #161616);
      testGfx.rect(x * cell, y * cell, cell + 1, cell + 1);
    }
  }
  int steps = max(1, cols * rows);
  int idx = (int) ((millis() / 90L) % steps);
  int hx = idx % cols;
  int hy = idx / cols;
  testGfx.noFill();
  testGfx.stroke(#c45444);
  testGfx.strokeWeight(max(2, capW / 320f));
  testGfx.rect(hx * cell + 3, hy * cell + 3, cell - 6, cell - 6);
}

void drawBarsPattern() {
  testGfx.background(12);
  int bars = 8;
  int[] cols = {
    color(180, 20, 30), color(190, 110, 20), color(200, 190, 30), color(20, 160, 50),
    color(20, 170, 170), color(30, 50, 180), color(150, 30, 160), color(190, 190, 190)
  };
  float barW = capW / (float) bars;
  float split = capH * 0.7f;
  testGfx.noStroke();
  for (int i = 0; i < bars; i++) {
    testGfx.fill(cols[i]);
    testGfx.rect(i * barW, 0, barW + 1, split);
  }
  for (int x = 0; x < capW; x++) {
    int g = (int) (x * 255f / capW);
    testGfx.stroke(g);
    testGfx.line(x, split, x, capH);
  }
  float t = (millis() % 2400) / 2400f;
  testGfx.stroke(255);
  testGfx.strokeWeight(max(2, capW / 280f));
  testGfx.line(t * capW, 0, t * capW, capH);
  testGfx.noFill();
  testGfx.strokeWeight(max(3, capW / 200f));
  testGfx.rect(10, 10, capW - 20, capH - 20);
  testGfx.line(0, 0, capW, capH);
  testGfx.line(capW, 0, 0, capH);
  float cx = capW * (0.2f + 0.6f * (0.5f + 0.5f * sin(millis() * 0.002)));
  testGfx.fill(255);
  testGfx.noStroke();
  testGfx.circle(cx, capH * 0.35f, capH * 0.16f);
  testGfx.fill(0);
  testGfx.textAlign(CENTER, CENTER);
  testGfx.textFont(uiFont);
  testGfx.textSize(max(18, capH / 18f));
  testGfx.text("TEST", capW / 2f, capH * 0.82f);
}

void drawGridPattern() {
  testGfx.background(#101114);
  int step = max(20, capW / 24);
  testGfx.stroke(#2a2e36);
  testGfx.strokeWeight(1);
  for (int x = 0; x <= capW; x += step) testGfx.line(x, 0, x, capH);
  for (int y = 0; y <= capH; y += step) testGfx.line(0, y, capW, y);
  testGfx.stroke(#727884);
  int major = step * 4;
  for (int x = 0; x <= capW; x += major) testGfx.line(x, 0, x, capH);
  for (int y = 0; y <= capH; y += major) testGfx.line(0, y, capW, y);
  float cx = capW / 2f;
  float cy = capH / 2f;
  float reach = min(capW, capH) * 0.46f;
  testGfx.noFill();
  testGfx.stroke(#c9c7c2);
  testGfx.strokeWeight(1);
  testGfx.line(cx, 0, cx, capH);
  testGfx.line(0, cy, capW, cy);
  for (int i = 1; i <= 3; i++) testGfx.circle(cx, cy, reach * 2 * i / 3f);
  float a = millis() * 0.0012f;
  testGfx.noStroke();
  testGfx.fill(#c45444);
  testGfx.circle(cx + cos(a) * reach, cy + sin(a) * reach * 0.56f, max(10, capH * 0.035f));
}

String testPatternName() {
  if (testPattern == TEST_BARS) return "Color bars";
  if (testPattern == TEST_GRID) return "Grid";
  return "Checkerboard";
}

String sourceLabel() {
  if (sourceMode == SRC_TEST) return testPatternName();
  if (sourceMode == SRC_TETHER) {
    if (tether != null && tether.connected) return "iPhone Tether";
    return tether != null ? tether.status : "iPhone Tether";
  }
  if (sourceMode == SRC_SYPHON) {
    if (syIndex >= 0 && syIndex < syEntries.size()) return syEntries.get(syIndex).label;
    return "Syphon";
  }
  CamEntry e = findCamByName(cameraName);
  if (e != null) return e.shortLabel();
  if (cameraName != null && cameraName.length() > 0) return cameraName;
  return "Webcam";
}

// —— Seamless input crossfade ————————————————————————————————

/** Crossfade length when switching live inputs. 0 = instant cut. */
float inputFadeMs = 320;
boolean inputFading = false;
float inputFade = 0; // 1 = old hold, 0 = new live
int inputFadeAt = 0;
boolean inputFadeArmed = false; // waiting for first new frame
PImage inputHoldImg;
int[] inputHoldPixels;
PImage inputFadeImg;

boolean liveShowing() {
  return liveValid
    || (inputFading && inputHoldPixels != null)
    || (liveFrozen() && liveFreezePixels != null);
}

void beginInputFade() {
  if (inputFadeMs < 1) {
    inputFading = false;
    inputFade = 0;
    return;
  }
  if (!snapInputHold()) return;
  inputFading = true;
  inputFade = 1;
  inputFadeArmed = true;
  inputFadeAt = millis();
}

boolean snapInputHold() {
  int n = capW * capH;
  if (n < 2) return false;
  if (inputHoldPixels == null || inputHoldPixels.length != n) inputHoldPixels = new int[n];

  PImage src = null;
  if (liveFxReady && liveFxImg != null) src = liveFxImg;
  else if (gpuGradeActive && gradedView != null) src = gradedView;
  else if (liveValid && livePixels != null && livePixels.length == n) {
    arrayCopy(livePixels, inputHoldPixels);
  } else {
    return false;
  }
  if (src != null) {
    if (src == gradedView || src.width != capW || src.height != capH) {
      copyFramePixels(src, inputHoldPixels);
    } else {
      src.loadPixels();
      arrayCopy(src.pixels, 0, inputHoldPixels, 0, min(n, src.pixels.length));
    }
  }
  if (inputHoldImg == null || inputHoldImg.width != capW || inputHoldImg.height != capH) {
    inputHoldImg = createImage(capW, capH, ARGB);
  }
  inputHoldImg.loadPixels();
  arrayCopy(inputHoldPixels, inputHoldImg.pixels);
  inputHoldImg.updatePixels();
  return true;
}

void tickInputFade() {
  if (!inputFading) return;
  if (inputFadeArmed) {
    if (!liveValid) {
      inputFade = 1;
      inputFadeAt = millis();
      return;
    }
    // First good frame from the new source — start the soft dissolve.
    inputFadeArmed = false;
    inputFadeAt = millis();
    inputFade = 1;
    return;
  }
  float dur = max(1, inputFadeMs);
  float t = (millis() - inputFadeAt) / dur;
  inputFade = constrain(1f - t, 0, 1);
  if (inputFade <= 0.001f) {
    inputFade = 0;
    inputFading = false;
  }
}

/** Build the crossfaded live view (hold → new). */
void updateInputFadeView() {
  if (!inputFading || inputHoldPixels == null) return;
  int n = capW * capH;
  if (inputFadeImg == null || inputFadeImg.width != capW || inputFadeImg.height != capH) {
    inputFadeImg = createImage(capW, capH, ARGB);
  }
  inputFadeImg.loadPixels();

  if (!liveValid || inputFade >= 0.999f) {
    arrayCopy(inputHoldPixels, 0, inputFadeImg.pixels, 0, min(n, inputHoldPixels.length));
    inputFadeImg.updatePixels();
    if (livePixels != null && livePixels.length == n) arrayCopy(inputHoldPixels, livePixels);
    return;
  }

  // Current graded/FX live into temp via livePixels when possible.
  int[] neu = livePixels;
  if (neu == null || neu.length != n) {
    arrayCopy(inputHoldPixels, 0, inputFadeImg.pixels, 0, n);
    inputFadeImg.updatePixels();
    return;
  }
  // If FX ran, livePixels is post-FX; if GPU grade only, pull graded.
  if (!liveFxReady && gpuGradeActive && gradedView != null) {
    ensureRecordPixels();
  }

  float f = inputFade;
  float inv = 1f - f;
  int[] out = inputFadeImg.pixels;
  for (int i = 0; i < n; i++) {
    int a = inputHoldPixels[i];
    int b = neu[i];
    int r = (int) (((a >> 16) & 255) * f + ((b >> 16) & 255) * inv);
    int g = (int) (((a >> 8) & 255) * f + ((b >> 8) & 255) * inv);
    int bl = (int) ((a & 255) * f + (b & 255) * inv);
    out[i] = 0xFF000000 | (r << 16) | (g << 8) | bl;
  }
  inputFadeImg.updatePixels();
  // Keep livePixels in sync so record / stack see the dissolve.
  arrayCopy(out, livePixels);
}

PImage inputLiveSource() {
  if (inputFading && inputFadeImg != null && inputFade > 0.001f) return inputFadeImg;
  return null;
}
