import javax.sound.midi.MidiDevice;
import javax.sound.midi.MidiMessage;
import javax.sound.midi.MidiSystem;
import javax.sound.midi.Receiver;
import javax.sound.midi.ShortMessage;
import javax.sound.midi.Transmitter;

static final int MIDI_SLIDER = 0;
static final int MIDI_TOGGLE = 1;
static final int MIDI_STEP = 2;
static final int MIDI_Q = 64;

class MidiBind {
  String id;
  String group;
  String label;
  int kind;
  float minv;
  float maxv;
  int steps;
  int cc = -1;
  int channel;
  boolean note;
  /** Last message was high. Used so a piano key flips once per press. */
  boolean gate;
}

ArrayList<MidiBind> midiBinds = new ArrayList<MidiBind>();
boolean midiMapMode = false;
String midiPickId = null;
boolean midiPending = false;
boolean midiPendNote = false;
int midiPendCh;
int midiPendNum;
String midiDeviceName = "";
String midiStatus = "Searching for MIDI.";
String[] midiNames = new String[0];
volatile boolean midiReady = false;
volatile MidiDevice midiIn;
volatile Transmitter midiTx; // must keep a hard ref or macOS/Java drops the input
int midiLastCh = -1;
int midiLastCc = -1;
int midiLastVal;
int midiLastSeen;
int midiNudgeAt;

final Object midiLock = new Object();
final Object midiOpenLock = new Object();
int[] midiQ = new int[MIDI_Q * 4];
int midiQRead;
int midiQWrite;
int[] midiNativeBuf = new int[MIDI_Q * 4];
boolean midiNativeOn = false;
int midiLastSourceCount = -1;
int midiHotplugAt;
volatile boolean midiScanQueued;
volatile boolean midiScanning;

Receiver midiReceiver = new Receiver() {
  public void send(MidiMessage message, long timeStamp) {
    if (!(message instanceof ShortMessage)) return;
    ShortMessage m = (ShortMessage) message;
    int cmd = m.getCommand();
    if (cmd == ShortMessage.CONTROL_CHANGE) offerMidi(0, m.getChannel(), m.getData1(), m.getData2());
    else if (cmd == ShortMessage.NOTE_ON) offerMidi(1, m.getChannel(), m.getData1(), m.getData2());
    else if (cmd == ShortMessage.NOTE_OFF) offerMidi(1, m.getChannel(), m.getData1(), 0);
  }
  public void close() {}
};

void initMidiInput() {
  MidiCtl.load(dataPath("libmidictl.dylib"));
  if (MidiCtl.loaded) {
    midiNativeOn = MidiCtl.start() == 1;
    if (midiNativeOn) {
      midiStatus = "CoreMIDI ready";
      println("MIDI: native CoreMIDI input.");
    } else {
      println("MIDI: native start failed — " + MidiCtl.fail);
    }
  } else {
    println("MIDI: " + MidiCtl.fail + " Falling back to javax.sound.midi.");
  }
}

void initMidiBinds() {
  midiBinds.clear();
  addStep("CAMERA", "Source", "src", 4);
  addToggle("CAMERA", "Lens 0.5×", "tether-cam#0");
  addToggle("CAMERA", "Lens 1×", "tether-cam#1");
  addToggle("CAMERA", "Lens 2×", "tether-cam#2");
  addStep("CAMERA", "Pattern", "testpat", 3);
  addToggle("CAMERA", "Mirror", "mirror");
  addStep("CAMERA", "Scale", "scale", 3);
  addStep("CAMERA", "Rotation", "rot", 4);
  addSlider("CAMERA", "Zoom", "sl-zoom", 0.25f, 3);
  addSlider("CAMERA", "Pan X", "sl-panx", -1, 1);
  addSlider("CAMERA", "Pan Y", "sl-pany", -1, 1);
  addSlider("CAMERA", "Feather", "sl-feather", 0, 100);
  addSlider("CAMERA", "Exposure", "sl-expo", -1, 1);
  addSlider("CAMERA", "Brilliance", "sl-bril", -1, 1);
  addSlider("CAMERA", "Highlights", "sl-high", -1, 1);
  addSlider("CAMERA", "Shadows", "sl-shad", -1, 1);
  addSlider("CAMERA", "Contrast", "sl-contrast", -1, 1);
  addSlider("CAMERA", "Brightness", "sl-bright", -1, 1);
  addSlider("CAMERA", "Black point", "sl-black", -1, 1);
  addSlider("CAMERA", "Curve black X", "sl-curve-black", 0, 1);
  addSlider("CAMERA", "Curve white X", "sl-curve-white", 0, 1);
  addSlider("CAMERA", "Saturation", "sl-sat", -1, 1);
  addSlider("CAMERA", "Vibrance", "sl-vib", -1, 1);
  addSlider("CAMERA", "Warmth", "sl-warm", -1, 1);
  addSlider("CAMERA", "Tint", "sl-tint", -1, 1);
  addSlider("CAMERA", "Sharpness", "sl-sharp", 0, 1);
  addSlider("CAMERA", "Definition", "sl-clar", -1, 1);
  addSlider("CAMERA", "Noise reduction", "sl-noise", 0, 1);
  addSlider("CAMERA", "Vignette", "sl-vig", -1, 1);
  addSlider("CAMERA", "Switch fade", "sl-input-fade", 0, 1500);
  addStep("EFFECTS", "Blend", "blend", 2);
  addToggle("EFFECTS", "FX Affect Live", "fx-affect-live");
  addToggle("EFFECTS", "FX Affect Loop", "fx-affect-loop");
  addSlider("EFFECTS", "Loop opacity", "sl-loop-opac", 0, 1);
  addSlider("EFFECTS", "Live opacity", "sl-opac", 0, 1);
  addSlider("EFFECTS", "Feedback", "sl-fb", 0, 0.92);
  addSlider("EFFECTS", "Hue", "sl-hue", 0, 360);
  addSlider("EFFECTS", "Posterize", "sl-post", 0, 8);
  addSlider("EFFECTS", "Threshold", "sl-thr", 0, 1);
  addSlider("EFFECTS", "Pixel", "sl-pix", 1, 32);
  addToggle("EFFECTS", "Invert", "invert");
  addToggle("ANIM", "Shoot", "stop-shoot");
  addToggle("ANIM", "Play", "stop-play");
  addToggle("ANIM", "Onion", "stop-onion");
  addToggle("ANIM", "Onion external", "stop-onion-ext");
  addSlider("ANIM", "Onion", "sl-onion", 0, 1);
  addToggle("ANIM", "Trackpad draw", "draw-trackpad");
  addToggle("ANIM", "Live underlay", "draw-live-bg");
  addToggle("ANIM", "Clear frames", "stop-clear");
  addSlider("ANIM", "FPS", "sl-stop-fps", 1, 25);
  addSlider("ANIM", "Brush", "sl-brush", 1, 200);
  addToggle("KEYS", "Space", "k-space");
  addToggle("KEYS", "Undo", "k-undo");
  addToggle("KEYS", "Clear loop", "k-clear");
  addToggle("KEYS", "Freeze hold (V)", "k-live");
  addToggle("KEYS", "Blackout", "k-black");
  addToggle("OUTPUT", "raw-preview", "raw-pip");
  addToggle("OUTPUT", "raw-preview external", "raw-pip-ext");
  addToggle("KEYS", "Step back", "k-step-back");
  addToggle("KEYS", "Step forward", "k-step-fwd");
  addToggle("KEYS", "Bake", "k-dash");
  for (int i = 0; i < 24; i++) {
    String key = fxKeyLabel(i);
    addToggle("FX", "FX " + key, "fx-" + i);
  }
  // Four sliders follow whichever FX is selected. Empty slots stay mappable.
  for (int i = 0; i < 4; i++) addSlider("FX", "FX  " + (i + 1), "sl-fx#" + i, 0, 1);
}

void addSlider(String group, String label, String id, float minv, float maxv) {
  MidiBind b = new MidiBind();
  b.group = group;
  b.label = label;
  b.id = id;
  b.kind = MIDI_SLIDER;
  b.minv = minv;
  b.maxv = maxv;
  midiBinds.add(b);
}

void addToggle(String group, String label, String id) {
  MidiBind b = new MidiBind();
  b.group = group;
  b.label = label;
  b.id = id;
  b.kind = MIDI_TOGGLE;
  midiBinds.add(b);
}

void addStep(String group, String label, String id, int steps) {
  MidiBind b = new MidiBind();
  b.group = group;
  b.label = label;
  b.id = id;
  b.kind = MIDI_STEP;
  b.steps = steps;
  midiBinds.add(b);
}

MidiBind findBind(String id) {
  if (id == null) return null;
  for (int i = 0; i < midiBinds.size(); i++) {
    if (midiBinds.get(i).id.equals(id)) return midiBinds.get(i);
  }
  return null;
}

void queueMidiScan() {
  if (midiScanning) {
    midiScanQueued = true;
    return;
  }
  midiScanQueued = false;
  thread("scanMidi");
}

void scanMidi() {
  if (midiScanning) return;
  midiScanning = true;
  String[] found = new String[0];
  try {
    found = collectMidiInputs();
  } catch (Throwable t) {
    midiStatus = "MIDI: " + (t.getMessage() == null ? t.toString() : t.getMessage());
    println(t);
  }
  try {
    midiNames = found;
    midiReady = true;
    if (midiNativeOn && MidiCtl.loaded) {
      try { MidiCtl.refresh(); } catch (Throwable t) {}
      try { midiLastSourceCount = MidiCtl.sourceCount(); } catch (Throwable t) {}
    }
    // Never reopen / thrash the port while the user is mapping.
    if (midiMapMode) {
      if (found.length == 0) midiStatus = "No input found";
      else if (midiDeviceName != null && midiDeviceName.length() > 0) midiStatus = "Connected";
      else midiStatus = found.length + " inputs";
      return;
    }
    String pick = resolveMidiPick(found, midiDeviceName);
    boolean already = pick != null && pick.length() > 0
      && midiDeviceName != null && midiLabelMatches(midiDeviceName, pick)
      && (midiNativeOn || midiIn != null);
    if (pick != null && pick.length() > 0) {
      if (!already) openMidi(pick);
      else {
        midiDeviceName = pick;
        midiStatus = "Connected";
      }
    } else if (found.length == 0) {
      midiStatus = "No input found";
    } else {
      midiStatus = found.length + " inputs";
    }
  } catch (Throwable t) {
    midiStatus = "MIDI: " + (t.getMessage() == null ? t.toString() : t.getMessage());
    println(t);
  } finally {
    midiScanning = false;
    if (midiScanQueued) {
      midiScanQueued = false;
      thread("scanMidi");
    }
  }
}

/** Prefer saved name, else sole device, else first nano/KORG match. */
String resolveMidiPick(String[] found, String wanted) {
  if (found == null || found.length == 0) return null;
  if (wanted != null && wanted.length() > 0) {
    for (int i = 0; i < found.length; i++) {
      if (midiLabelMatches(wanted, found[i])) return found[i];
    }
  }
  if (found.length == 1) return found[0];
  for (int i = 0; i < found.length; i++) {
    String s = found[i].toLowerCase();
    if (s.indexOf("nanokontrol") >= 0 || s.indexOf("nano kontrol") >= 0 || s.indexOf("korg") >= 0) {
      return found[i];
    }
  }
  return wanted != null && wanted.length() > 0 ? wanted : null;
}

boolean midiLabelMatches(String a, String b) {
  if (a == null || b == null) return false;
  if (a.equals(b)) return true;
  String al = a.toLowerCase().trim();
  String bl = b.toLowerCase().trim();
  if (al.equals(bl)) return true;
  if (al.indexOf(bl) >= 0 || bl.indexOf(al) >= 0) return true;
  // "SLIDER/KNOB" vs "nanoKONTROL2 SLIDER/KNOB"
  String as = al.replace("nanokontrol2", "").replace("korg", "").trim();
  String bs = bl.replace("nanokontrol2", "").replace("korg", "").trim();
  if (as.length() > 2 && (as.equals(bs) || bl.endsWith(as) || al.endsWith(bs))) return true;
  return false;
}

boolean isSoftMidiDevice(MidiDevice dev, MidiDevice.Info info) {
  String cls = dev.getClass().getName();
  if (cls.indexOf("SoftSynthesizer") >= 0 || cls.indexOf("RealTimeSequencer") >= 0) return true;
  String vendor = info.getVendor();
  if (vendor == null) return false;
  return vendor.indexOf("Oracle") >= 0 || vendor.indexOf("OpenJDK") >= 0;
}

/** Prefer CoreMIDI description ("nanoKONTROL2 SLIDER/KNOB") over short port name ("SLIDER/KNOB"). */
String midiDeviceLabel(MidiDevice.Info info) {
  String name = info.getName();
  if (name == null) name = "";
  String desc = info.getDescription();
  if (desc != null) {
    desc = desc.trim();
    if (desc.length() > 0
        && !desc.equalsIgnoreCase("No details available")
        && !desc.equals(name)
        && (desc.indexOf(name) >= 0 || name.length() <= 4)) {
      return desc;
    }
  }
  String vendor = info.getVendor();
  if (vendor != null) {
    vendor = vendor.trim();
    if (vendor.length() > 0
        && vendor.indexOf("Unknown") < 0
        && vendor.indexOf("Oracle") < 0
        && vendor.indexOf("OpenJDK") < 0
        && name.indexOf(vendor) < 0) {
      return vendor + " " + name;
    }
  }
  return name.length() > 0 ? name : "MIDI device";
}

String[] collectMidiInputs() {
  ArrayList<String> out = new ArrayList<String>();
  // Prefer CoreMIDI source names — javax often misses or renames ports on macOS 15+/26.
  if (midiNativeOn && MidiCtl.loaded) {
    try {
      MidiCtl.refresh();
      int n = MidiCtl.sourceCount();
      for (int i = 0; i < n; i++) {
        String label = MidiCtl.sourceName(i);
        if (label == null) continue;
        label = label.trim();
        if (label.length() == 0) continue;
        // Skip virtual / IAC bus unless that's all we have (added later if empty).
        String low = label.toLowerCase();
        if (low.indexOf("iac driver") >= 0 || low.equals("java sound synthesizer")) continue;
        String unique = label;
        int k = 2;
        while (out.contains(unique)) unique = label + " " + k++;
        out.add(unique);
      }
    } catch (Throwable t) {
      println("MIDI native list: " + t.getMessage());
    }
  }
  try {
    MidiDevice.Info[] infos = MidiSystem.getMidiDeviceInfo();
    for (int i = 0; i < infos.length; i++) {
      try {
        MidiDevice.Info info = infos[i];
        MidiDevice dev = MidiSystem.getMidiDevice(info);
        if (dev.getMaxTransmitters() == 0) continue;
        if (isSoftMidiDevice(dev, info)) continue;
        String label = midiDeviceLabel(info);
        if (label == null || label.length() == 0) continue;
        // Deduplicate against CoreMIDI names (fuzzy).
        boolean dup = false;
        for (int j = 0; j < out.size(); j++) {
          if (midiLabelMatches(out.get(j), label)) { dup = true; break; }
        }
        if (dup) continue;
        String unique = label;
        int n = 2;
        while (out.contains(unique)) unique = label + " " + n++;
        out.add(unique);
      } catch (Exception e) {
        println(e);
      }
    }
  } catch (Throwable t) {
    println("MIDI javax list: " + t.getMessage());
  }
  if (out.size() == 0 && midiNativeOn && MidiCtl.loaded) {
    try {
      int n = MidiCtl.sourceCount();
      if (n > 0) out.add(n == 1 ? "MIDI input" : (n + " MIDI inputs"));
    } catch (Throwable t) {}
  }
  return out.toArray(new String[0]);
}

boolean midiNameMatches(String wanted, String unique, MidiDevice.Info info) {
  if (wanted == null || wanted.length() == 0) return false;
  if (midiLabelMatches(wanted, unique)) return true;
  String name = info.getName();
  String desc = info.getDescription();
  if (name != null && midiLabelMatches(wanted, name)) return true;
  if (desc != null && midiLabelMatches(wanted, desc)) return true;
  if (name != null && name.length() > 0 && unique.endsWith(name) && wanted.equals(name)) return true;
  if (name != null && wanted.endsWith(name) && unique.indexOf(name) >= 0) return true;
  return false;
}

void openMidi(String name) {
  synchronized (midiOpenLock) {
    closeMidi();
    midiDeviceName = name == null ? "" : name;
    if (midiDeviceName.length() == 0) {
      midiStatus = "No input";
      return;
    }
    // Native CoreMIDI is the real input path on modern macOS.
    if (midiNativeOn && MidiCtl.loaded) {
      try { MidiCtl.refresh(); } catch (Throwable t) {}
      // Canonicalize to a listed CoreMIDI / javax name when possible.
      for (int i = 0; i < midiNames.length; i++) {
        if (midiLabelMatches(midiDeviceName, midiNames[i])) {
          midiDeviceName = midiNames[i];
          break;
        }
      }
      midiStatus = "Connected";
      markDirty();
    }
    try {
      MidiDevice.Info[] infos = MidiSystem.getMidiDeviceInfo();
      ArrayList<String> seen = new ArrayList<String>();
      for (int i = 0; i < infos.length; i++) {
        MidiDevice.Info info = infos[i];
        MidiDevice dev = MidiSystem.getMidiDevice(info);
        if (dev.getMaxTransmitters() == 0) continue;
        if (isSoftMidiDevice(dev, info)) continue;
        String label = midiDeviceLabel(info);
        String unique = label;
        int n = 2;
        while (seen.contains(unique)) unique = label + " " + n++;
        seen.add(unique);
        if (!midiNameMatches(midiDeviceName, unique, info)) continue;
        midiDeviceName = unique;
        // Best-effort javax open (often silent on macOS 15+/26 — native handles traffic).
        try {
          if (!dev.isOpen()) dev.open();
          midiTx = dev.getTransmitter();
          midiTx.setReceiver(midiReceiver);
          midiIn = dev;
        } catch (Exception je) {
          println("javax MIDI open skipped: " + je.getMessage());
        }
        midiStatus = "Connected";
        markDirty();
        return;
      }
      if (!midiNativeOn) midiStatus = "Not found";
    } catch (Exception e) {
      if (!midiNativeOn) midiStatus = "MIDI: " + e.getMessage();
      println(e);
    }
  }
}

/** Re-wire receiver without tearing down the native port. */
void ensureMidiReceiver() {
  if (midiNativeOn && MidiCtl.loaded) {
    try {
      MidiCtl.refresh();
      if (midiStatus == null || midiStatus.startsWith("No") || midiStatus.startsWith("Not") || midiStatus.startsWith("MIDI:")) {
        midiStatus = "Connected";
      }
    } catch (Throwable t) {
      println(t);
    }
  }
  synchronized (midiOpenLock) {
    if (midiDeviceName == null || midiDeviceName.length() == 0) return;
    try {
      if (midiIn == null || !midiIn.isOpen()) {
        openMidi(midiDeviceName);
        return;
      }
      if (midiTx == null) midiTx = midiIn.getTransmitter();
      midiTx.setReceiver(midiReceiver);
      if (midiStatus == null || midiStatus.startsWith("No") || midiStatus.startsWith("Not") || midiStatus.startsWith("MIDI:")) {
        midiStatus = "Connected";
      }
    } catch (Exception e) {
      openMidi(midiDeviceName);
    }
  }
}

void closeMidi() {
  Transmitter tx = midiTx;
  midiTx = null;
  if (tx != null) {
    try { tx.close(); } catch (Exception e) { println(e); }
  }
  MidiDevice dev = midiIn;
  midiIn = null;
  if (dev == null) return;
  try {
    if (dev.isOpen()) dev.close();
  } catch (Exception e) {
    println(e);
  }
}

void offerMidi(int type, int ch, int num, int val) {
  synchronized (midiLock) {
    int next = (midiQWrite + 1) % MIDI_Q;
    if (next == midiQRead) midiQRead = (midiQRead + 1) % MIDI_Q;
    int at = midiQWrite * 4;
    midiQ[at] = type;
    midiQ[at + 1] = ch;
    midiQ[at + 2] = num;
    midiQ[at + 3] = val;
    midiQWrite = next;
  }
}

void serviceMidi() {
  // Prefer native CoreMIDI — javax.sound.midi often gets zero packets on modern macOS.
  if (midiNativeOn && MidiCtl.loaded) {
    try {
      int n = MidiCtl.poll(midiNativeBuf);
      int cap = midiNativeBuf.length / 4;
      if (n > cap) n = cap;
      for (int i = 0; i < n; i++) {
        int at = i * 4;
        try {
          applyMidiEvent(midiNativeBuf[at], midiNativeBuf[at + 1], midiNativeBuf[at + 2], midiNativeBuf[at + 3]);
        } catch (Throwable ev) {
          println("MIDI event: " + ev.getMessage());
        }
      }
      // Hot-plug: only re-list, never during active map learn (avoids open/close races).
      if (!midiMapMode && millis() - midiHotplugAt > 2500) {
        midiHotplugAt = millis();
        int sc = MidiCtl.sourceCount();
        if (sc != midiLastSourceCount || (sc > 0 && midiNames.length == 0)) {
          midiLastSourceCount = sc;
          if (sc > 0) try { MidiCtl.refresh(); } catch (Throwable t) {}
          queueMidiScan();
        }
      }
    } catch (Throwable t) {
      midiNativeOn = false;
      println("MIDI native poll failed: " + t.getMessage());
    }
  }
  int[] batch = null;
  int count = 0;
  synchronized (midiLock) {
    int pending = midiQWrite - midiQRead;
    if (pending < 0) pending += MIDI_Q;
    if (pending > 0) {
      batch = new int[pending * 4];
      for (int i = 0; i < pending; i++) {
        int at = midiQRead * 4;
        batch[count++] = midiQ[at];
        batch[count++] = midiQ[at + 1];
        batch[count++] = midiQ[at + 2];
        batch[count++] = midiQ[at + 3];
        midiQRead = (midiQRead + 1) % MIDI_Q;
      }
    }
  }
  if (batch == null) return;
  for (int i = 0; i < count; i += 4) applyMidiEvent(batch[i], batch[i + 1], batch[i + 2], batch[i + 3]);
}

boolean midiConnected() {
  return midiNativeOn || midiIn != null;
}

void applyMidiEvent(int type, int ch, int num, int val) {
  boolean isNote = type == 1;
  midiLastCh = ch;
  midiLastCc = num;
  midiLastVal = val;
  midiLastSeen = millis();
  if (midiConnected()) {
    String act = midiLabel(isNote, ch, num) + " " + val;
    midiStatus = midiMapMode
      ? (midiPickId != null ? "Learning · " + act : "MAP · " + act)
      : ("Connected · " + act);
  }
  if (midiMapMode) {
    if (midiPickId == null) {
      if (!(isNote && val == 0) && millis() - midiNudgeAt > 1200) {
        midiNudgeAt = millis();
        note("Click a framed control first");
      }
      return;
    }
    if (!(isNote && val == 0)) {
      MidiBind b = findBind(midiPickId);
      if (b != null) {
        boolean first = b.cc != num || b.note != isNote || b.channel != ch || !midiPending;
        b.note = isNote;
        b.channel = ch;
        b.cc = num;
        midiPending = true;
        midiPendNote = isNote;
        midiPendCh = ch;
        midiPendNum = num;
        markDirty();
        if (first) note("MAPPED  " + b.label + "  →  " + midiLabel(b.note, b.channel, b.cc));
        // Live preview only for continuous sliders — toggles/steps would fire actions every CC and crash/hang.
        if (b.kind == MIDI_SLIDER) {
          try {
            applyBind(b, val / 127f, val);
          } catch (Throwable t) {
            println("MIDI map apply: " + t.getMessage());
          }
        }
      }
    }
    return;
  }
  if (isNote && val == 0) {
    for (int i = 0; i < midiBinds.size(); i++) {
      MidiBind b = midiBinds.get(i);
      if (!b.note || b.cc != num || b.kind != MIDI_TOGGLE) continue;
      if (!midiChannelMatches(b.channel, ch)) continue;
      try { applyBind(b, 0, 0); } catch (Throwable t) { println("MIDI bind: " + t.getMessage()); }
    }
    return;
  }
  float unit = val / 127f;
  int hit = 0;
  for (int i = 0; i < midiBinds.size(); i++) {
    MidiBind b = midiBinds.get(i);
    if (b.cc < 0 || b.note != isNote || b.cc != num) continue;
    if (!midiChannelMatches(b.channel, ch)) continue;
    if (dragSlider != null && (dragSlider.equals(b.id)
      || (b.id.equals("sl-opac") && dragSlider.equals("sl-mix-live"))
      || (b.id.equals("sl-loop-opac") && dragSlider.equals("sl-mix-loop")))) continue;
    try {
      applyBind(b, unit, val);
      hit++;
    } catch (Throwable t) {
      println("MIDI bind: " + t.getMessage());
    }
  }
  if (hit == 0 && midiIn != null && !midiMapMode && millis() - midiLastSeen < 50) {
    // keep Connected status; activity already written above
  }
}

/** Omni-friendly: channel 0 bindings accept any channel (common for nanoKONTROL). */
boolean midiChannelMatches(int bound, int incoming) {
  if (bound <= 0) return true;
  return bound == incoming;
}

void toggleMidiMap() {
  if (midiMapMode) {
    midiMapMode = false;
    midiPickId = null;
    midiPending = false;
    saveMidiMapFile();
    ensureMidiReceiver();
    note(projectOpen ? "MIDI map saved" : "MIDI map saved locally");
    return;
  }
  midiMapMode = true;
  midiPickId = null;
  midiPending = false;
  ensureMidiReceiver();
  note("MAP on  ·  click a framed control");
}

void selectMidiPick(String id) {
  if (id == null || findBind(id) == null) return;
  midiPending = false;
  midiPickId = id;
  ensureMidiReceiver();
  MidiBind b = findBind(id);
  String lab = b != null ? b.label : id;
  note("SELECTED  " + lab + "  ·  move controller");
}

void confirmMidiPick() {
  // Bindings apply on controller move; Enter is unused.
  midiPickId = null;
  midiPending = false;
}

void clearMidiPick() {
  if (midiPickId == null) return;
  MidiBind b = findBind(midiPickId);
  if (b != null && (b.cc >= 0 || midiPending)) {
    b.cc = -1;
    b.note = false;
    markDirty();
    note(b.label + " cleared");
  }
  midiPickId = null;
  midiPending = false;
}

/** True once when a momentary key goes down. Release is ignored. */
boolean midiTogglePress(MidiBind b, int val) {
  boolean high = val >= 64;
  boolean press = high && !b.gate;
  b.gate = high;
  return press;
}

void applyBind(MidiBind b, float unit, int val) {
  if (b.kind == MIDI_SLIDER) {
    if (b.id.startsWith("sl-fx#")) {
      applyFxMidiSlider(b.id, unit);
      return;
    }
    applySlider(b.id, b.minv + unit * (b.maxv - b.minv));
    return;
  }
  if (b.kind == MIDI_TOGGLE) {
    boolean on = val >= 64;
    if (b.id.equals("mirror")) {
      if (mirror != on) {
        mirror = on;
        liveFrameDirty = true;
        markDirty();
      }
    } else if (b.id.equals("invert")) {
      if (fxInvert != on) {
        fxSetInvert(on);
        markDirty();
      }
    } else if (b.id.equals("fx-affect-live")) {
      setFxAffectLive(on);
    } else if (b.id.equals("fx-affect-loop")) {
      setFxAffectLoop(on);
    } else if (b.id.equals("stop-shoot")) {
      if (on) animShoot();
    } else if (b.id.equals("stop-play")) {
      if (on && !stopPlaying) stopTogglePlay();
      else if (!on && stopPlaying) stopTogglePlay();
    } else if (b.id.equals("stop-onion")) {
      if (stopOnion != on) {
        stopOnion = on;
        markDirty();
      }
    } else if (b.id.equals("stop-onion-ext")) {
      if (stopOnionExternal != on) {
        stopOnionExternal = on;
        markDirty();
      }
    } else if (b.id.equals("draw-trackpad")) {
      if (drawTrackpadMode != on) setDrawTrackpadMode(on);
    } else if (b.id.equals("draw-live-bg")) {
      if (drawLiveUnderlay != on) setDrawLiveUnderlay(on);
    } else if (b.id.equals("stop-clear")) {
      if (on) {
        if (hasStop()) stopClear();
        else note("No stoptrick frames");
      }
    } else if (b.id.equals("k-space")) {
      if (on) onSpace();
    } else if (b.id.equals("k-undo")) {
      if (on) {
        if (drawModeOn() || topMode == TOP_DRAW) drawOrStopUndo();
        else if (stopModeOn()) stopPopLast();
        else undo();
      }
    } else if (b.id.equals("k-clear")) {
      if (on) requestClear();
    } else if (b.id.equals("k-live")) {
      setLiveInOutput(on);
    } else if (b.id.equals("k-black")) {
      setBlackout(on);
    } else if (b.id.equals("raw-pip")) {
      // Piano key: one flip per press. Note-off must not turn it back off.
      if (midiTogglePress(b, val)) setRawPipDesktop(!rawPipDesktop);
    } else if (b.id.equals("raw-pip-ext")) {
      if (midiTogglePress(b, val)) setRawPipExternal(!rawPipExternal);
    } else if (b.id.equals("k-play")) {
      if (on && !stopPlaying) stopTogglePlay();
      else if (!on && stopPlaying) stopTogglePlay();
    } else if (b.id.equals("k-step-back")) {
      if (on) {
        if (hasStop()) stopStep(-1);
        else nudgeLayerSelect(-1);
      }
    } else if (b.id.equals("k-step-fwd")) {
      if (on) {
        if (hasStop()) stopStep(1);
        else nudgeLayerSelect(1);
      }
    } else if (b.id.equals("k-dash")) {
      if (on) pressBakeDash();
    } else if (b.id.startsWith("tether-cam#")) {
      if (on) {
        int idx = int(b.id.substring(11));
        if (tetherLensEnabled(idx)) tetherSetCam(idx);
      }
    } else if (b.id.startsWith("fx-")) {
      fxMidiLatch(fxSlotForKey(int(b.id.substring(3))), on);
    }
    return;
  }
  int steps = max(1, b.steps);
  int idx = constrain((int) (val * steps / 128f), 0, steps - 1);
  if (b.id.equals("src")) {
    if (sourceMode != idx) selectSource(idx);
  } else if (b.id.equals("testpat")) {
    if (testPattern != idx) {
      testPattern = idx;
      markDirty();
    }
  } else if (b.id.equals("scale")) {
    if (camScale != idx) {
      camScale = idx;
      liveFrameDirty = true;
      markDirty();
    }
  } else if (b.id.equals("rot")) {
    int rot = idx * 90;
    if (camRotation != rot) {
      camRotation = rot;
      liveFrameDirty = true;
      markDirty();
    }
  } else if (b.id.equals("blend")) {
    if (shownBlend() != idx) setShownBlend(idx);
  }
}

String midiHint() {
  if (!midiMapMode) {
    if (midiDeviceName != null && midiDeviceName.length() > 0) return midiDeviceName;
    return "No device";
  }
  if (midiPickId == null) return "Click a framed control  ·  MIDI again saves";
  MidiBind b = findBind(midiPickId);
  String name = b == null ? "Parameter" : b.label;
  if (b != null && b.cc >= 0) return "SELECTED  " + name + "  =  " + midiLabel(b.note, b.channel, b.cc);
  return "SELECTED  " + name + "  ·  move controller";
}

String midiNoteName(int n) {
  String[] pcs = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
  int pc = n % 12;
  if (pc < 0) pc += 12;
  return pcs[pc] + (n / 12 - 2);
}

String midiLabel(boolean note, int ch, int num) {
  if (num < 0) return "";
  String body = note ? midiNoteName(num) : "CC" + num;
  if (ch <= 0) return body;
  return (ch + 1) + " " + body;
}

String midiPendingLabel() {
  return midiLabel(midiPendNote, midiPendCh, midiPendNum);
}

/** Map 0..1 MIDI unit through the focused FX param. Unused slots ignore the value. */
void applyFxMidiSlider(String id, float unit) {
  if (id == null || !id.startsWith("sl-fx#")) return;
  int param = int(id.substring(6));
  FxUnit u = fxFocusedUnit();
  if (u == null || !fxParamUsed(u.type, param)) return;
  float[] mm = new float[2];
  fxParamRange(u.type, param, mm);
  float v = mm[0] + constrain(unit, 0, 1) * (mm[1] - mm[0]);
  fxApplySlider(id, v);
}

String bindForHit(String id) {
  if (id == null) return null;
  if (findBind(id) != null) return id;
  // Preview mix chrome uses separate drag ids from the FX-panel sliders.
  if (id.equals("sl-mix-live") || id.equals("mix-live-tog")) return "sl-opac";
  if (id.equals("sl-mix-loop") || id.equals("mix-loop-tog")) return "sl-loop-opac";
  if (id.startsWith("sl-fx#")) return id;
  if (id.startsWith("scale-")) return "scale";
  if (id.startsWith("rot-")) return "rot";
  if (id.startsWith("src-")) return "src";
  if (id.startsWith("test#")) return "testpat";
  if (id.startsWith("blend-") || id.equals("k-blend") || id.equals("mix-blend")) return "blend";
  if (id.equals("fx-invert")) return "invert";
  if (id.equals("fx-affect-live") || id.equals("fx-affect-loop")) return id;
  if (id.equals("stop-shoot") || id.equals("stop-play") || id.equals("stop-onion") || id.equals("stop-onion-ext") || id.equals("draw-trackpad") || id.equals("draw-live-bg") || id.equals("stop-clear")) return id;
  if (id.equals("sl-stop-fps")) return id;
  if (id.equals("k-play")) return "stop-play";
  if (id.equals("k-frames")) return "stop-clear";
  if (id.equals("k-enter") || id.equals("k-shoot")) return "stop-shoot";
  if (id.startsWith("fx-kb#")) return "fx-" + id.substring(6);
  if (id.equals("raw-pip") || id.equals("raw-pip-ext")) return id;
  if (id.equals("k-space") || id.equals("k-undo") || id.equals("k-clear")
      || id.equals("k-live") || id.equals("k-black")
      || id.equals("k-step-back") || id.equals("k-step-fwd") || id.equals("k-dash")) return id;
  if (id.equals("sl-curve-black") || id.equals("sl-curve-white")) return id;
  if (id.startsWith("sl-") && findBind(id) != null) return id;
  return null;
}

/** Topmost map-frame under the cursor (bind id, not raw hit id). */
String mapFrameHit(float mx, float my) {
  if (mapFrames == null) return null;
  for (int i = mapFrames.size() - 1; i >= 0; i--) {
    MapFrame f = mapFrames.get(i);
    if (mx >= f.x && mx < f.x + f.w && my >= f.y && my < f.y + f.h) return f.id;
  }
  return null;
}

void clearMidiAssignments() {
  for (int i = 0; i < midiBinds.size(); i++) {
    MidiBind b = midiBinds.get(i);
    b.cc = -1;
    b.channel = 0;
    b.note = false;
  }
}

void loadMidi(JSONObject o) {
  String dev = o.getString("midiDevice", "");
  // Don't wipe a device name already restored from midi.xml with an empty settings field.
  if (dev != null && dev.length() > 0) midiDeviceName = dev;
  if (!o.hasKey("midi")) return;
  JSONArray arr = o.getJSONArray("midi");
  if (arr == null || arr.size() == 0) return;
  for (int i = 0; i < arr.size(); i++) {
    JSONObject m = arr.getJSONObject(i);
    MidiBind b = findBind(m.getString("id", ""));
    if (b == null) continue;
    b.cc = m.getInt("cc", -1);
    b.channel = constrain(m.getInt("ch", 0), 0, 15);
    b.note = m.getBoolean("note", false);
  }
}

void saveMidi(JSONObject o) {
  o.setString("midiDevice", midiDeviceName == null ? "" : midiDeviceName);
  // Bindings live in midi.xml; keep an empty array for older readers.
  o.setJSONArray("midi", new JSONArray());
}

String midiMapFilePath() {
  if (projectOpen && projectDir != null && projectDir.length() > 0) {
    return new File(projectDir, "midi.xml").getAbsolutePath();
  }
  return dataPath("midi.xml");
}

void saveMidiMapFile() {
  try {
    if (projectOpen) ensureProjectDirs();
    XML root = new XML("midi");
    root.setString("device", midiDeviceName == null ? "" : midiDeviceName);
    for (int i = 0; i < midiBinds.size(); i++) {
      MidiBind b = midiBinds.get(i);
      if (b.cc < 0) continue;
      XML node = root.addChild("bind");
      node.setString("id", b.id);
      node.setInt("ch", b.channel);
      node.setInt("cc", b.cc);
      node.setString("note", b.note ? "true" : "false");
    }
    saveXML(root, midiMapFilePath());
  } catch (Exception e) {
    println("MIDI map save failed: " + e.getMessage());
    note("MIDI map save failed");
  }
}

void loadMidiMapFile() {
  File f = new File(midiMapFilePath());
  if (!f.exists()) return;
  try {
    XML root = loadXML(f.getAbsolutePath());
    if (root == null) return;
    String device = root.getString("device", "");
    if (device != null) midiDeviceName = device;
    clearMidiAssignments();
    XML[] nodes = root.getChildren("bind");
    if (nodes != null) {
      for (int i = 0; i < nodes.length; i++) {
        XML node = nodes[i];
        String id = node.getString("id", "");
        // Old per-key slider maps become the shared focus sliders.
        if (id.startsWith("sl-fxa#")) id = "sl-fx#0";
        else if (id.startsWith("sl-fxb#")) id = "sl-fx#1";
        MidiBind b = findBind(id);
        if (b == null) continue;
        b.cc = node.getInt("cc", -1);
        b.channel = constrain(node.getInt("ch", 0), 0, 15);
        String noteAttr = node.getString("note", "false");
        b.note = noteAttr != null && (noteAttr.equals("true") || noteAttr.equals("1"));
      }
    }
    if (midiDeviceName != null && midiDeviceName.length() > 0 && midiIn == null) {
      openMidi(midiDeviceName);
    }
  } catch (Exception e) {
    println("MIDI map load failed: " + e.getMessage());
  }
}
