// Stackable FX for Live feed, Loop composite, and master Output.
// Resolume-style toolkit: color, stylize, transform, temporal.

// —— Color ——
static final int FX_HUE = 0;
static final int FX_SAT = 1;
static final int FX_CONTRAST = 2;
static final int FX_POST = 3;
static final int FX_THR = 4;
static final int FX_INV = 5;
static final int FX_SOLAR = 6;
static final int FX_COLORIZE = 7;
// —— Stylize ——
static final int FX_PIX = 8;
static final int FX_BLUR = 9;
static final int FX_EDGE = 10;
static final int FX_EMBOSS = 11;
// —— Transform ——
static final int FX_MIRROR = 12;   // legacy combo (H/V/Quad via amount2)
static final int FX_KALEIDO = 13;
static final int FX_TWIRL = 14;
static final int FX_RIPPLE = 15;
static final int FX_BULGE = 16; // was Tunnel — fisheye / pinch
static final int FX_SLICES = 17;
// —— Temporal ——
static final int FX_FB = 18;
static final int FX_TRAIL = 19;
static final int FX_STROBE = 20;
// —— Transform extras ——
static final int FX_FLIP_H = 21; // combined Flip (H / V / Both via amount2)
static final int FX_FLIP_V = 22; // legacy — migrated into FX_FLIP_H
static final int FX_FLIP = FX_FLIP_H;
static final int FX_ROTATE = 23;
static final int FX_MIRROR_H = 24;
static final int FX_MIRROR_V = 25;
static final int FX_QUAD = 26;
static final int FX_SLIDE = 27;
static final int FX_PUSH = 28;
static final int FX_ROT180 = 29; // fixed 180° toggle
static final int FX_GLITCH = 30;
static final int FX_SLIT = 31; // slit-scan (time on axis)
static final int FX_RGBDELAY = 32; // per-channel temporal delay

static final int FX_COUNT = 33;
/** Ring length for RGB Delay history (frames). Keep modest — each slot is a full frame. */
static final int RGB_DELAY_MAX = 12;

static final int FX_TGT_LIVE = 0;
static final int FX_TGT_LOOP = 1;
static final int FX_TGT_OUT = 2;

static final String[] FX_NAMES = {
  "Hue / Sat", "Saturation", "Contrast", "Posterize", "Threshold", "Invert", "Solarize", "Colorize",
  "Pixelate", "Blur", "Edge", "Emboss",
  "Mirror", "Kaleido", "Twirl", "Ripple", "Bulge", "Slices",
  "Echo", "Trail", "Strobe",
  "Flip", "Flip V", "Rotate", "Mirror H", "Mirror V", "Quad", "Slide", "Push", "Rot 180",
  "Glitch", "SlitScan", "RGB Delay"
};

/** Keyboard legend, indexed by FX type (not by key slot). */
static final String[] FX_SHORT = {
  "HSAT", "SAT", "CRT", "POST", "THR", "INV", "SOL", "COL",
  "PIX", "BLUR", "EDGE", "EMB",
  "MIR", "KAL", "TWI", "RIP", "BLG", "SLC",
  "ECHO", "TRL", "STR",
  "FLP", "FLV", "ROT", "MRH", "MRV", "QUAD", "SLD", "PSH", "180",
  "GLCH", "SLIT", "RGB"
};

static final String[] FX_GROUPS = {
  "COLOR", "COLOR", "COLOR", "COLOR", "COLOR", "COLOR", "COLOR", "COLOR",
  "STYLIZE", "STYLIZE", "STYLIZE", "STYLIZE",
  "TRANSFORM", "TRANSFORM", "TRANSFORM", "TRANSFORM", "TRANSFORM", "TRANSFORM",
  "TEMPORAL", "TEMPORAL", "TEMPORAL",
  "TRANSFORM", "TRANSFORM", "TRANSFORM", "TRANSFORM", "TRANSFORM", "TRANSFORM", "MOTION", "MOTION",
  "TRANSFORM", "STYLIZE", "TEMPORAL", "TEMPORAL"
};

/**
 * Full FX list (apply order). May be longer than FX_KEYS — extras are
 * list-only until the user maps them onto a key.
 * Default key rows (DE), except Echo / Trail which always run last:
 *   Q W E R T Z U I O P Ü +
 *   A S D F G H J K L Ö Ä #
 * Which physical key triggers which slot lives in fxKeySlot.
 */
static final int[] FX_RACK = {
  // Q-row — Mirror → Quad → SlitScan (signature tools first)
  FX_MIRROR, FX_QUAD, FX_SLIT, FX_GLITCH, FX_BLUR, FX_PIX,
  FX_POST, FX_TWIRL, FX_RIPPLE, FX_BULGE, FX_SLICES, FX_PUSH,
  // A-row — Flip combines H/V/Both; Emboss takes the old Flip-V slot
  FX_INV, FX_FLIP, FX_CONTRAST, FX_ROT180, FX_STROBE, FX_HUE,
  FX_SLIDE, FX_EDGE, FX_KALEIDO, FX_EMBOSS, FX_FB, FX_COLORIZE,
  // List-only by default (map onto a key yourself)
  FX_RGBDELAY
};
static final char[] FX_KEYS = {
  'q', 'w', 'e', 'r', 't', 'z', 'u', 'i', 'o', 'p', '\u00FC', '+',
  'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', '\u00F6', '\u00E4', '#'
};
static final float FX_FADE_MS = 280;
static final float FX_NUDGE_MS = 170;
/** Preview chase time for FX slider / nudge targets. */
static final float FX_PARAM_SMOOTH_SEC = 0.14f;

int fxTarget = FX_TGT_LIVE;
/** Where the edited FX rack (fxLive) is applied. Both can be on. */
boolean fxAffectLive = true;
boolean fxAffectLoop = false;
boolean fxPickerOpen = false;
int fxFocus = -1;
/** Rack slot waiting for a keyboard key. -1 = idle. */
int fxKeyMapFrom = -1;
/** Key that just finished a map, ignored until release so key-repeat doesn't toggle it. */
char fxMapIgnore = 0;
/** Physical FX key currently held — repeats must not count as a second tap. */
int fxKeyHeldSlot = -1;
int fxKeyTapSlot = -1;
int fxKeyTapAt = 0;
int fxKeyTapCount = 0;
static final int FX_TAP_MS = 420;
/** Physical FX key → rack slot index (0..FX_RACK.length-1). Not every slot needs a key. */
int[] fxKeySlot;
float fxScroll = 0;
float fxScrollMax = 0;
int fxLastTick = 0;
String fxFilter = "";
boolean fxFilterFocus = false;
static final float FX_FILTER_H = 28;

// Animated keyboard nudge → slides amount toward target
int fxNudgeIdx = -1;
int fxNudgeTarget = -1; // which stack target the nudge belongs to
boolean fxNudgeSecond = false;
float fxNudgeFrom = 0;
float fxNudgeTo = 0;
int fxNudgeStart = 0;

// Hold Ctrl/Opt → key-repeat nudge (accelerates)
int fxHoldDir = 0;       // -1 ctrl, +1 opt, 0 off
int fxHoldIdx = -1;      // -1 = focused FX
boolean fxHoldFine = false;
int fxHoldStartAt = 0;
int fxHoldLastAt = 0;
static final int FX_HOLD_DELAY_MS = 260;
static final int FX_HOLD_REPEAT_MS = 70;

ArrayList<FxUnit> fxLive = new ArrayList<FxUnit>();
ArrayList<FxUnit> fxLoop = new ArrayList<FxUnit>();
ArrayList<FxUnit> fxOut = new ArrayList<FxUnit>();

int[] fxFbLive;
int[] fxFbLoop;
int[] fxFbOut;
int[] fxTrailLive;
int[] fxTrailLoop;
int[] fxTrailOut;
int[] fxScratch;
int[] fxHold;
int[] fxScratch2;
int[] fxFadeScratch;
int[] fxSlitLive;
int[] fxSlitLoop;
int[] fxSlitOut;
float[] fxSlitPhase = new float[3];
int[] fxSlitOrient = new int[3]; // 0 = vertical slit →, 1 = horizontal slit ↓
int fxSlitApplyTarget = FX_TGT_LIVE;
/** RGB Delay ring history per target (live/loop/out). Lazy-allocated. */
int[][][] rgbDelayFrames = new int[3][][];
int[] rgbDelayHead = new int[3];
int[] rgbDelayCount = new int[3];
int[] rgbDelayN = new int[3];
int fxRgbDelayTarget = FX_TGT_LIVE;
PImage liveFxImg;
boolean liveFxReady = false;
int liveFxFrame = -1;

class FxUnit {
  int type;
  boolean on = true;
  float amount = 0;
  float amount2 = 0;
  float amount3 = 0;
  float amount4 = 0;
  /** Preview values — ease toward amount* so slider changes feel smooth. */
  float live0 = 0, live1 = 0, live2 = 0, live3 = 0;
  float fade = 1; // 0..1 soft mix toward applied effect

  FxUnit(int type) {
    this.type = type;
    amount = fxDefaultAmount(type);
    amount2 = fxDefaultAmount2(type);
    amount3 = fxDefaultAmount3(type);
    amount4 = fxDefaultAmount4(type);
    snapLive();
  }

  FxUnit(int type, boolean startOn) {
    this(type);
    on = startOn;
    fade = startOn ? 1 : 0;
  }

  void snapLive() {
    live0 = amount;
    live1 = amount2;
    live2 = amount3;
    live3 = amount4;
  }
}

float fxDefaultAmount(int type) {
  if (type == FX_HUE) return 0;         // hue degrees; 0 = no shift
  if (type == FX_SAT) return 0;         // 0 = B&W when active
  if (type == FX_CONTRAST) return 0.35f;
  if (type == FX_POST) return 4;
  if (type == FX_THR) return 0.5f;
  if (type == FX_SOLAR) return 0.5f;
  if (type == FX_COLORIZE) return 30;
  if (type == FX_PIX) return 8;
  if (type == FX_BLUR) return 0.35f;
  if (type == FX_EDGE) return 0.7f;
  if (type == FX_EMBOSS) return 0.6f;
  if (type == FX_SLIT) return 0.35f;    // scroll speed
  if (type == FX_GLITCH) return 0.45f;
  if (type == FX_MIRROR) return 1;       // strength
  if (type == FX_KALEIDO) return 6;      // segments
  if (type == FX_TWIRL) return 0.55f;
  if (type == FX_RIPPLE) return 0.4f;
  if (type == FX_BULGE) return 0.55f;   // strength (−pinch … +bulge)
  if (type == FX_SLICES) return 8;
  if (type == FX_FB) return 0.45f;      // echo strength
  if (type == FX_TRAIL) return 0.72f;   // legacy
  if (type == FX_RGBDELAY) return 0.4f; // delay depth
  if (type == FX_STROBE) return 0.35f;
  if (type == FX_FLIP || type == FX_FLIP_V || type == FX_ROT180) return 1;
  if (type == FX_ROTATE) return 90;      // degrees
  if (type == FX_MIRROR_H || type == FX_MIRROR_V || type == FX_QUAD) return 1;
  if (type == FX_SLIDE || type == FX_PUSH) return 0.35f; // speed
  return 1; // invert
}

/** Slider 2. Types that did not store a real amount2 keep the new default via the p4 load flag. */
float fxDefaultAmount2(int type) {
  if (type == FX_COLORIZE) return 0.55f; // mix
  if (type == FX_EDGE) return 1;         // mix with source
  if (type == FX_HUE) return 1;          // sat: 0 = B&W, 1 = full chroma
  if (type == FX_MIRROR) return 0;       // 0=H 1=V
  if (type == FX_TWIRL) return 0.55f;    // radius
  if (type == FX_RIPPLE) return 0.45f;   // frequency
  if (type == FX_BULGE) return 0.7f;     // radius
  if (type == FX_SLICES) return 0.35f;   // shift
  if (type == FX_STROBE) return 0.5f;    // duty
  if (type == FX_GLITCH) return 0.4f;    // chaos
  if (type == FX_FB) return 0;           // 0=Feedback … 1=Trail
  if (type == FX_RGBDELAY) return 0.65f; // channel spread
  if (type == FX_ROTATE) return 0;       // spin -1..1
  if (type == FX_SLIDE || type == FX_PUSH) return 0; // dir
  if (type == FX_SLIT) return 1;         // line count
  if (type == FX_FLIP || type == FX_FLIP_V) return 0; // mode: 0=H 1=V 2=Both
  if (type == FX_INV || type == FX_SAT || type == FX_CONTRAST || type == FX_POST
    || type == FX_PIX || type == FX_BLUR || type == FX_EMBOSS) return 1; // mix / channel
  return 0;
}

float fxDefaultAmount3(int type) {
  if (type == FX_HUE || type == FX_THR || type == FX_SOLAR || type == FX_KALEIDO) return 1;
  if (type == FX_CONTRAST) return 0.5f; // pivot
  if (type == FX_POST || type == FX_INV || type == FX_COLORIZE || type == FX_PIX || type == FX_BLUR) return 1;
  if (type == FX_EMBOSS) return 225; // light angle
  if (type == FX_MIRROR) return 0; // axis degrees (relative to H/V)
  if (type == FX_TWIRL || type == FX_BULGE) return 0.5f; // center x
  if (type == FX_RIPPLE || type == FX_TRAIL || type == FX_STROBE || type == FX_ROTATE) return 1;
  if (type == FX_SLIDE || type == FX_PUSH || type == FX_ROT180 || type == FX_GLITCH) return 1;
  if (type == FX_RGBDELAY) return 1; // mix
  return 0;
}

float fxDefaultAmount4(int type) {
  if (type == FX_THR || type == FX_INV || type == FX_SOLAR || type == FX_PIX || type == FX_BLUR) return 1;
  if (type == FX_EDGE || type == FX_EMBOSS || type == FX_KALEIDO || type == FX_RIPPLE) return 1;
  if (type == FX_SLICES || type == FX_TRAIL || type == FX_ROTATE) return 1;
  if (type == FX_FLIP || type == FX_FLIP_V || type == FX_SLIT || type == FX_GLITCH) return 1;
  if (type == FX_TWIRL || type == FX_BULGE) return 0.5f; // center y
  if (type == FX_RGBDELAY) return 0; // 0=RGB … 1=BGR
  return 0;
}

/** True when older saves already stored a meaningful amount2. */
boolean fxLegacySecond(int type) {
  return type == FX_COLORIZE || type == FX_EDGE || type == FX_HUE || type == FX_MIRROR || type == FX_TWIRL
    || type == FX_RIPPLE || type == FX_BULGE || type == FX_SLICES || type == FX_STROBE
    || type == FX_GLITCH || type == FX_FB || type == FX_ROTATE || type == FX_SLIDE || type == FX_PUSH
    || type == FX_SLIT || type == FX_RGBDELAY;
}

boolean fxHasSecond(int type) {
  return true;
}

/** All four focus sliders are live for every effect. */
boolean fxParamUsed(int type, int param) {
  return param >= 0 && param <= 3;
}

/** Typed number is the real param, not a 0–100 percent. */
boolean fxSliderRaw(int type) {
  return type == FX_HUE || type == FX_COLORIZE || type == FX_POST || type == FX_PIX
    || type == FX_KALEIDO || type == FX_SLICES || type == FX_MIRROR || type == FX_ROTATE
    || type == FX_SLIDE || type == FX_PUSH || type == FX_SLIT;
}

/** Per-slider: degrees, counts, and scales type in as the real number. */
boolean fxParamRaw(int type, int param) {
  if (param == 0 && fxSliderRaw(type)) return true;
  if (param == 1 && (fxSliderRaw(type) || type == FX_ROT180)) return true;
  if (type == FX_SAT && param == 3) return true;
  if (type == FX_EMBOSS && param == 2) return true;
  if (type == FX_KALEIDO && param == 2) return true;
  if (type == FX_SLICES && param == 2) return true;
  if (type == FX_PIX && (param == 2 || param == 3)) return true;
  if (type == FX_BLUR && (param == 2 || param == 3)) return true;
  if (type == FX_GLITCH && (param == 2 || param == 3)) return true;
  if (type == FX_RIPPLE && param == 2) return true;
  if (type == FX_FB && (param == 2 || param == 3)) return true;
  if (type == FX_EDGE && param == 3) return true;
  if (type == FX_ROTATE && param == 2) return true;
  if (type == FX_ROT180 && param == 2) return true;
  if (type == FX_MIRROR && param == 2) return true;
  if ((type == FX_FLIP || type == FX_FLIP_V) && param == 3) return true;
  return false;
}

boolean fxParamFine(int type, int param) {
  if (type == FX_ROTATE && (param == 1 || param == 2)) return true;
  if (type == FX_ROT180 && param == 2) return true;
  if (type == FX_MIRROR && param == 2) return true;
  if (type == FX_KALEIDO && param == 2) return true;
  if (type == FX_PIX && (param == 2 || param == 3)) return true;
  if (type == FX_BLUR && (param == 2 || param == 3)) return true;
  if (type == FX_GLITCH && (param == 2 || param == 3)) return true;
  if (type == FX_RIPPLE && param == 2) return true;
  if (type == FX_FB && param == 2) return true;
  if ((type == FX_FLIP || type == FX_FLIP_V) && param == 3) return true;
  return false;
}

float fxParamGet(FxUnit u, int param) {
  if (u == null) return 0;
  if (param == 1) return u.amount2;
  if (param == 2) return u.amount3;
  if (param == 3) return u.amount4;
  return u.amount;
}

void fxParamSet(FxUnit u, int param, float v) {
  if (u == null) return;
  if (fxParamRound(u.type, param)) v = round(v);
  if (param == 1) u.amount2 = v;
  else if (param == 2) u.amount3 = v;
  else if (param == 3) u.amount4 = v;
  else u.amount = v;
  if (u.type == FX_SLIT && param <= 2) fxClearSlit(fxTarget);
}

boolean fxParamRound(int type, int param) {
  if (param == 0 && (type == FX_POST || type == FX_PIX || type == FX_KALEIDO || type == FX_SLICES)) return true;
  if (param == 1 && (type == FX_MIRROR || type == FX_FLIP || type == FX_SLIDE || type == FX_PUSH || type == FX_SLIT || type == FX_KALEIDO)) return true;
  if (type == FX_EDGE && param == 3) return true;
  if (type == FX_SLICES && param == 2) return true;
  if (type == FX_EMBOSS && param == 2) return true;
  if (type == FX_FB && param == 3) return true;
  if (type == FX_ROT180 && param == 1) return true;
  if (type == FX_SAT && param == 3) return true;
  return false;
}

String fxName(int type) {
  if (type < 0 || type >= FX_NAMES.length) return "FX";
  return FX_NAMES[type];
}

ArrayList<FxUnit> fxStackFor(int target) {
  if (target == FX_TGT_LOOP) return fxLoop;
  if (target == FX_TGT_OUT) return fxOut;
  return fxLive;
}

ArrayList<FxUnit> fxActiveStack() {
  fxTarget = FX_TGT_LIVE;
  return fxLive;
}

String fxTargetLabel(int target) {
  if (target == FX_TGT_LOOP) return "Loop";
  if (target == FX_TGT_OUT) return "Output";
  return "Live";
}

boolean fxStackActive(ArrayList<FxUnit> stack) {
  if (stack == null) return false;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u != null && u.fade > 0.01f) return true;
  }
  return false;
}

/** Rack slot lit on a given stack (on or fading). */
boolean fxSlotLit(ArrayList<FxUnit> stack, int idx) {
  if (stack == null || idx < 0 || idx >= stack.size()) return false;
  FxUnit u = stack.get(idx);
  return u != null && (u.on || u.fade > 0.08f);
}

String fxKeyLabel(int index) {
  if (index < 0 || index >= FX_KEYS.length) return "";
  char c = FX_KEYS[index];
  if (c == '\u00FC') return "Ü";
  if (c == '\u00F6') return "Ö";
  if (c == '\u00E4') return "Ä";
  if (c == '+') return "+";
  return str(Character.toUpperCase(c));
}

String fxShortName(int type) {
  if (type < 0 || type >= FX_SHORT.length) return "FX";
  return FX_SHORT[type];
}

void initFxKeySlots() {
  boolean ok = fxKeySlot != null && fxKeySlot.length == FX_KEYS.length;
  if (ok) {
    for (int i = 0; i < fxKeySlot.length; i++) {
      if (fxKeySlot[i] < 0 || fxKeySlot[i] >= FX_RACK.length) { ok = false; break; }
    }
  }
  if (ok) return;
  // Default: first keys.length rack slots get keys; extras stay list-only.
  fxKeySlot = new int[FX_KEYS.length];
  for (int i = 0; i < fxKeySlot.length; i++) fxKeySlot[i] = i;
}

/** Rack slot triggered by this physical FX key, or -1. */
int fxSlotForKey(int keyIndex) {
  initFxKeySlots();
  if (keyIndex < 0 || keyIndex >= fxKeySlot.length) return -1;
  return fxKeySlot[keyIndex];
}

/** Physical key currently bound to this rack slot, or -1. */
int fxKeyForSlot(int slot) {
  initFxKeySlots();
  for (int i = 0; i < fxKeySlot.length; i++) {
    if (fxKeySlot[i] == slot) return i;
  }
  return -1;
}

String fxSlotKeyLabel(int slot) {
  int key = fxKeyForSlot(slot);
  return key < 0 ? "" : fxKeyLabel(key);
}

void fxCancelKeyMap() {
  if (fxKeyMapFrom < 0) return;
  fxKeyMapFrom = -1;
}

/** Arm (or cancel) key capture for the effect on this rack slot. */
void fxArmKeyMap(int slot) {
  if (slot < 0 || slot >= FX_RACK.length) {
    fxCancelKeyMap();
    return;
  }
  if (fxKeyMapFrom == slot) {
    fxCancelKeyMap();
    note("Map cancelled");
    return;
  }
  fxKeyMapFrom = slot;
  fxFocus = slot;
  note("MAP  " + fxName(FX_RACK[slot]).toUpperCase() + "  ·  press a key");
}

/**
 * Bind the armed effect to this physical key.
 * If the effect already had a key, swap with whatever was on toKey.
 * If it was list-only, toKey's previous effect becomes list-only.
 */
void fxCommitKeyMap(int toKey) {
  int slot = fxKeyMapFrom;
  fxKeyMapFrom = -1;
  initFxKeySlots();
  if (slot < 0 || slot >= FX_RACK.length || toKey < 0 || toKey >= fxKeySlot.length) return;
  int oldKey = fxKeyForSlot(slot);
  if (oldKey == toKey) {
    fxFocus = slot;
    return;
  }
  int other = fxKeySlot[toKey];
  fxKeySlot[toKey] = slot;
  if (oldKey >= 0 && oldKey < fxKeySlot.length) fxKeySlot[oldKey] = other;
  markDirty();
  fxFocus = slot;
  fxRevealPanel();
  note(fxKeyLabel(toKey) + "  " + fxName(FX_RACK[slot]).toUpperCase());
}

void saveFxRack(JSONObject o) {
  if (o == null) return;
  initFxKeySlots();
  JSONArray arr = new JSONArray();
  for (int i = 0; i < fxKeySlot.length; i++) arr.setInt(i, fxKeySlot[i]);
  o.setJSONArray("fxKeys", arr);
}

/** Restore a saved key assignment. Missing or invalid data leaves the current map. */
void loadFxRack(JSONObject o) {
  initFxKeySlots();
  if (o == null || !o.hasKey("fxKeys")) return;
  JSONArray arr = o.getJSONArray("fxKeys");
  if (arr == null || arr.size() != fxKeySlot.length) return;
  int n = fxKeySlot.length;
  int[] next = new int[n];
  boolean[] seen = new boolean[FX_RACK.length];
  for (int i = 0; i < n; i++) {
    int s = arr.getInt(i, -1);
    if (s < 0 || s >= FX_RACK.length || seen[s]) return;
    seen[s] = true;
    next[i] = s;
  }
  arrayCopy(next, fxKeySlot);
}

int fxKeyIndex(char k) {
  char low = Character.toLowerCase(k);
  // Mac sometimes delivers uppercase umlauts
  if (k == '\u00DC') low = '\u00FC'; // Ü
  if (k == '\u00D6') low = '\u00F6';
  if (k == '\u00C4') low = '\u00E4';
  for (int i = 0; i < FX_KEYS.length; i++) {
    if (FX_KEYS[i] == low || FX_KEYS[i] == k) return i;
  }
  return -1;
}

/**
 * Shared 1 / 2 / 3 gesture for FX shortcut keys (physical + GUI).
 * Returns 1=select, 2=toggle, 3=reset. Clears streak after a triple.
 */
int fxKeyGesture(int slot) {
  int now = millis();
  if (slot == fxKeyTapSlot && now - fxKeyTapAt < FX_TAP_MS) fxKeyTapCount++;
  else fxKeyTapCount = 1;
  fxKeyTapAt = now;
  fxKeyTapSlot = slot;
  int n = fxKeyTapCount;
  if (n >= 3) {
    fxKeyTapCount = 0;
    fxKeyTapSlot = -1;
  }
  return n;
}

boolean fxHandleKey(char k) {
  int slot = fxSlotForKey(fxKeyIndex(k));
  if (slot < 0) return false;
  // Hold/repeat stays a single press. Multi-tap: select / toggle / reset.
  if (fxKeyHeldSlot == slot) return true;
  fxKeyHeldSlot = slot;
  int n = fxKeyGesture(slot);
  if (n >= 3) fxResetUnit(slot);
  else if (n == 2) fxToggle(slot);
  else {
    fxSelectSlot(slot);
    note(fxSlotKeyLabel(slot) + "  " + fxName(FX_RACK[slot]).toUpperCase());
  }
  return true;
}

void fxReleaseKey(char k) {
  int slot = fxSlotForKey(fxKeyIndex(k));
  if (slot >= 0 && slot == fxKeyHeldSlot) fxKeyHeldSlot = -1;
}

/** Select a rack slot and open its controls. Does not change on/off. */
void fxSelectSlot(int slot) {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (slot < 0 || slot >= stack.size()) return;
  fxFocus = slot;
  fxScroll = 0;
  fxRevealPanel();
  markDirty();
}

FxUnit fxFocusedUnit() {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (fxFocus < 0 || fxFocus >= stack.size()) return null;
  return stack.get(fxFocus);
}

/** Discrete mode/dir second-params that Cmd can step through. */
boolean fxHasModeCycle(int type) {
  return type == FX_MIRROR || type == FX_FLIP || type == FX_SLIDE || type == FX_PUSH || type == FX_SLIT;
}

void fxCycleMode(int index, int dir) {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (index < 0 || index >= stack.size()) return;
  FxUnit u = stack.get(index);
  if (!fxHasModeCycle(u.type)) return;
  fxFocus = index;
  // Slit: Cmd toggles Vert ↔ Horz (line count stays on amount2).
  if (u.type == FX_SLIT) {
    int t = constrain(fxTarget, 0, 2);
    fxSlitOrient[t] = fxSlitOrient[t] == 0 ? 1 : 0;
    fxClearSlit(fxTarget);
    fxBump();
    note(fxSlotKeyLabel(index) + "  SLIT  " + (fxSlitOrient[t] == 0 ? "Vert →" : "Horz ↓"));
    return;
  }
  float[] mm = new float[2];
  fxParamRange(u.type, 1, mm);
  int lo = round(mm[0]);
  int hi = round(mm[1]);
  int cur = constrain(round(u.amount2), lo, hi);
  int step = dir < 0 ? -1 : 1;
  int next = cur + step;
  if (next > hi) next = lo;
  if (next < lo) next = hi;
  u.amount2 = next;
  fxBump();
  note(fxSlotKeyLabel(index) + "  " + fxName(u.type).toUpperCase() + "  " + fxAmount2Label(u));
}

/** Cmd alone / Cmd+FX: step Mode/Dir on focused (or first active) cycleable FX. */
boolean fxCycleFocusedMode(int dir) {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (fxFocus >= 0 && fxFocus < stack.size() && fxHasModeCycle(stack.get(fxFocus).type)) {
    fxCycleMode(fxFocus, dir);
    return true;
  }
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u != null && u.on && fxHasModeCycle(u.type)) {
      fxCycleMode(i, dir);
      return true;
    }
  }
  return false;
}

float fxNudgeStep(int type, boolean fine) {
  if (type == FX_POST || type == FX_PIX || type == FX_KALEIDO || type == FX_SLICES) return 1;
  if (type == FX_HUE || type == FX_COLORIZE || type == FX_ROTATE) return fine ? 1 : 5;
  return fine ? 0.01f : 0.05f;
}

float fxNudgeStep2(int type, boolean fine) {
  if (type == FX_MIRROR || type == FX_FLIP || type == FX_SLIDE || type == FX_PUSH || type == FX_SLIT) return 1;
  if (type == FX_ROTATE) return fine ? 0.02f : 0.05f;
  return fine ? 0.01f : 0.05f;
}

/** Nudge param1 (amount) or param2 (amount2). Shift = fine. Animates to next value. */
void fxNudgeAmount(int index, int dir, boolean fine) {
  fxNudgeParam(index, false, dir, fine);
}

void tickFxNudge() {
  tickFxNudgeHold();
}

void fxStartNudgeHold(int dir, int idx, boolean fine) {
  fxHoldDir = dir < 0 ? -1 : 1;
  fxHoldIdx = idx;
  fxHoldFine = fine;
  fxHoldStartAt = millis();
  fxHoldLastAt = fxHoldStartAt;
}

void fxStopNudgeHold() {
  fxHoldDir = 0;
  fxHoldIdx = -1;
}

void fxStopNudgeHoldDir(int dir) {
  if (fxHoldDir == (dir < 0 ? -1 : 1)) fxStopNudgeHold();
}

void tickFxNudgeHold() {
  if (fxHoldDir == 0) return;
  // Stoptrick selected: Opt/Ctrl are FPS, not FX amounts.
  if (stopSelected()) {
    fxStopNudgeHold();
    return;
  }
  int now = millis();
  int held = now - fxHoldStartAt;
  if (held < FX_HOLD_DELAY_MS) return;
  // Accelerate: shorter interval the longer it's held.
  int interval = max(22, FX_HOLD_REPEAT_MS - held / 35);
  if (now - fxHoldLastAt < interval) return;
  fxHoldLastAt = now;
  boolean fine = fxHoldFine;
  if (keyEvent != null) fine = keyEvent.isShiftDown();
  if (fxHoldIdx >= 0) fxNudgeAmount(fxHoldIdx, fxHoldDir, fine);
  else fxNudgeFocusedAmount(fxHoldDir, fine);
}

/** Drop hold + in-flight anim so bake/record can't keep walking Hue etc. */
void fxCancelNudge() {
  fxStopNudgeHold();
  fxNudgeIdx = -1;
}

void fxNudgeParam(int index, boolean second, int dir, boolean fine) {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (index < 0 || index >= stack.size()) return;
  FxUnit u = stack.get(index);
  if (second && !fxHasSecond(u.type)) return;
  // Discrete style/mode/dir → cycle. Slit amount2 is line count (nudged below).
  if (second && fxHasModeCycle(u.type) && u.type != FX_SLIT) {
    float[] mm = new float[2];
    fxParamRange(u.type, 1, mm);
    int lo = round(mm[0]);
    int hi = round(mm[1]);
    int c = constrain(round(u.amount2), lo, hi);
    int step = dir < 0 ? -1 : 1;
    int next = c + step;
    if (next > hi) next = lo;
    if (next < lo) next = hi;
    fxFocus = index;
    u.amount2 = next;
    fxBump();
    note(fxSlotKeyLabel(index) + "  " + fxName(u.type).toUpperCase() + "  " + fxAmount2Label(u));
    return;
  }
  float[] mm = new float[2];
  fxParamRange(u.type, second ? 1 : 0, mm);
  float lo = mm[0], hi = mm[1];
  float cur = second ? u.amount2 : u.amount;
  float step = (second ? fxNudgeStep2(u.type, fine) : fxNudgeStep(u.type, fine)) * (dir < 0 ? -1 : 1);
  float next = cur + step;
  boolean wrap = !second && (u.type == FX_HUE || u.type == FX_COLORIZE);
  if (wrap) {
    float span = hi - lo;
    if (span > 0) next = lo + ((next - lo) % span + span) % span;
  } else {
    next = constrain(next, lo, hi);
  }
  if (!second && (u.type == FX_POST || u.type == FX_PIX || u.type == FX_KALEIDO || u.type == FX_SLICES)) {
    next = round(next);
  }
  if (second && (u.type == FX_MIRROR || u.type == FX_FLIP || u.type == FX_SLIDE || u.type == FX_PUSH || u.type == FX_SLIT)) next = round(next);
  if (abs(next - cur) < 0.0001f) return;
  fxFocus = index;
  if (u.type == FX_SLIT && second) fxClearSlit(fxTarget);
  if (second) u.amount2 = next;
  else u.amount = next;
  fxBump();
  note(fxSlotKeyLabel(index) + "  " + fxName(u.type).toUpperCase() + "  "
    + (second ? fxAmount2Label(u) : fxAmountLabel(u)));
}

boolean fxNudgeFocusedAmount(int dir, boolean fine) {
  return fxNudgeFocusedParam(false, dir, fine);
}

boolean fxNudgeFocusedParam(boolean second, int dir, boolean fine) {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (fxFocus >= 0 && fxFocus < stack.size()) {
    if (second && !fxHasSecond(stack.get(fxFocus).type)) return false;
    fxNudgeParam(fxFocus, second, dir, fine);
    return true;
  }
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u != null && u.on) {
      if (second && !fxHasSecond(u.type)) continue;
      fxNudgeParam(i, second, dir, fine);
      return true;
    }
  }
  return false;
}

/** Arrow keys navigate the 2×12 FX keyboard GUI (Q-row / A-row). */
boolean fxNavArrow(int code) {
  ensureFxRack(fxActiveStack());
  initFxKeySlots();
  int cols = 12;
  int rows = 2;
  int n = cols * rows;
  if (fxKeySlot.length < n) n = fxKeySlot.length;
  if (n < 1) return false;
  int pos = fxKeyForSlot(fxFocus);
  if (pos < 0 || pos >= n) pos = 0;
  int row = pos / cols;
  int col = pos % cols;
  if (code == LEFT) col = (col + cols - 1) % cols;
  else if (code == RIGHT) col = (col + 1) % cols;
  else if (code == UP) row = (row + rows - 1) % rows;
  else if (code == DOWN) row = (row + 1) % rows;
  else return false;
  int next = row * cols + col;
  if (next >= n) next = n - 1;
  int slot = fxSlotForKey(next);
  if (slot < 0) return false;
  fxSelectSlot(slot);
  return true;
}

// Double-tap Cmd → toggle; single Cmd (after short delay) → cycle mode.
int fxCmdTapAt = 0;
boolean fxCmdPending = false;
int fxCmdCycleDir = 1;
static final int FX_CMD_DOUBLE_MS = 280;

void fxCmdAlone(boolean shift) {
  int now = millis();
  if (fxCmdPending && now - fxCmdTapAt <= FX_CMD_DOUBLE_MS) {
    fxCmdPending = false;
    fxCmdTapAt = 0;
    if (fxFocus < 0) fxFocus = 0;
    fxToggle(fxFocus);
    return;
  }
  fxCmdPending = true;
  fxCmdTapAt = now;
  fxCmdCycleDir = shift ? -1 : 1;
}

void tickFxCmdTap() {
  if (!fxCmdPending) return;
  if (millis() - fxCmdTapAt <= FX_CMD_DOUBLE_MS) return;
  fxCmdPending = false;
  fxCmdTapAt = 0;
  fxCycleFocusedMode(fxCmdCycleDir);
}

void ensureFxRack(ArrayList<FxUnit> stack) {
  if (stack == null) return;
  boolean match = stack.size() == FX_RACK.length;
  if (match) {
    for (int i = 0; i < FX_RACK.length; i++) {
      if (stack.get(i).type != FX_RACK[i]) { match = false; break; }
    }
  }
  if (match) return;

  // Preserve on/amount by type from previous stack.
  ArrayList<FxUnit> old = new ArrayList<FxUnit>(stack);
  FxUnit oldFlipH = null, oldFlipV = null;
  for (int j = 0; j < old.size(); j++) {
    FxUnit u = old.get(j);
    if (u == null) continue;
    if (u.type == FX_FLIP_H) oldFlipH = u;
    else if (u.type == FX_FLIP_V) oldFlipV = u;
  }
  stack.clear();
  for (int i = 0; i < FX_RACK.length; i++) {
    int type = FX_RACK[i];
    FxUnit src = null;
    for (int j = 0; j < old.size(); j++) {
      if (old.get(j).type == type) { src = old.get(j); break; }
    }
    if (src != null) {
      stack.add(src);
    } else {
      stack.add(new FxUnit(type, false));
    }
  }
  // Fold legacy Flip V into Flip (mode H/V/Both).
  fxMergeLegacyFlip(stack, oldFlipH, oldFlipV);
}

/** Merge separate Flip H + Flip V units into the combined Flip slot. */
void fxMergeLegacyFlip(ArrayList<FxUnit> stack, FxUnit oldH, FxUnit oldV) {
  if (stack == null || oldV == null) return;
  FxUnit flip = null;
  for (int i = 0; i < stack.size(); i++) {
    if (stack.get(i).type == FX_FLIP) { flip = stack.get(i); break; }
  }
  if (flip == null) return;
  boolean hOn = oldH != null && (oldH.on || oldH.fade > 0.05f);
  boolean vOn = oldV.on || oldV.fade > 0.05f;
  if (!vOn) {
    // Still migrate Flip H amount2 from legacy shift → mode 0.
    if (oldH != null && !oldH.on) { /* keep */ }
    return;
  }
  if (hOn && vOn) {
    flip.on = true;
    flip.fade = max(oldH.fade, oldV.fade);
    flip.amount2 = 2; // Both
  } else if (vOn) {
    flip.on = true;
    flip.fade = oldV.fade;
    flip.amount = oldV.amount;
    flip.amount2 = 1; // V
    flip.amount3 = oldV.amount3;
    flip.amount4 = oldV.amount4;
  }
  flip.snapLive();
}

boolean fxEdgeMixBootstrapped = false;
boolean fxHueSatBootstrapped = false;
boolean fxSlitLinesBootstrapped = false;
boolean fxMirrorAxisBootstrapped = false;

void ensureAllFxRacks() {
  ensureFxRack(fxLive);
  ensureFxRack(fxLoop);
  ensureFxRack(fxOut);
  // One-shot: Edge Mix is new; unused amount2 was 0 — keep previous full-edge look.
  if (!fxEdgeMixBootstrapped) {
    fxEdgeMixBootstrapped = true;
    fxBootstrapEdgeMix(fxLive);
    fxBootstrapEdgeMix(fxLoop);
    fxBootstrapEdgeMix(fxOut);
  }
  // One-shot: Hue/Sat combined — old Hue left amount2=0 (unused) which now means B&W.
  if (!fxHueSatBootstrapped) {
    fxHueSatBootstrapped = true;
    fxBootstrapHueSat(fxLive);
    fxBootstrapHueSat(fxLoop);
    fxBootstrapHueSat(fxOut);
  }
  if (!fxSlitLinesBootstrapped) {
    fxSlitLinesBootstrapped = true;
    fxBootstrapSlitLines(fxLive);
    fxBootstrapSlitLines(fxLoop);
    fxBootstrapSlitLines(fxOut);
  }
  // Seam (0.05…0.95) became Axis degrees — snap legacy fractions back to 0°.
  if (!fxMirrorAxisBootstrapped) {
    fxMirrorAxisBootstrapped = true;
    fxBootstrapMirrorAxis(fxLive);
    fxBootstrapMirrorAxis(fxLoop);
    fxBootstrapMirrorAxis(fxOut);
  }
  if (fxFocus < 0 || fxFocus >= fxActiveStack().size()) fxFocus = 0;
}

void fxBootstrapEdgeMix(ArrayList<FxUnit> stack) {
  if (stack == null) return;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u != null && u.type == FX_EDGE && u.amount2 <= 0) {
      u.amount2 = 1;
      u.snapLive();
    }
  }
}

/** Pre-combine Hue saves had unused amount2=0; treat as full chroma, not B&W. */
void fxBootstrapHueSat(ArrayList<FxUnit> stack) {
  if (stack == null) return;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u != null && u.type == FX_HUE && u.amount2 <= 0.001f) {
      u.amount2 = 1;
      u.snapLive();
    }
  }
}

/** Slit amount2 is line count now; clamp legacy 0 / out-of-range. */
void fxBootstrapSlitLines(ArrayList<FxUnit> stack) {
  if (stack == null) return;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null || u.type != FX_SLIT) continue;
    if (u.amount2 < 1) u.amount2 = 1;
    else u.amount2 = constrain(round(u.amount2), 1, 5);
    u.snapLive();
  }
}

/** Old Mirror amount3 was seam 0.05…0.95; Axis wants degrees. */
void fxBootstrapMirrorAxis(ArrayList<FxUnit> stack) {
  if (stack == null) return;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null || u.type != FX_MIRROR) continue;
    if (u.amount3 > 0f && u.amount3 < 1f) {
      u.amount3 = 0;
      u.snapLive();
    }
  }
}

void tickFxFades() {
  int now = millis();
  if (fxLastTick <= 0) fxLastTick = now;
  float dtMs = now - fxLastTick;
  fxLastTick = now;
  float dt = constrain(dtMs / FX_FADE_MS, 0, 1);
  tickFxFadeStack(fxLive, dt);
  tickFxFadeStack(fxLoop, dt);
  tickFxFadeStack(fxOut, dt);
  float dtSec = constrain(dtMs / 1000f, 0, 0.1f);
  boolean chasing = tickFxParamLiveStack(fxLive, dtSec)
    | tickFxParamLiveStack(fxLoop, dtSec)
    | tickFxParamLiveStack(fxOut, dtSec);
  if (chasing) {
    liveFxReady = false;
    if (fxAffectLoop) loopImgHead = -1;
    syncFlatFxFromLive();
    markDirty();
  }
}

/** Discrete mode/dir/count params snap; continuous ones ease in the preview. */
boolean fxParamSmoothable(int type, int param) {
  if (type == FX_MIRROR && param == 1) return false;
  if (type == FX_FLIP && param == 1) return false;
  if ((type == FX_SLIDE || type == FX_PUSH) && param == 1) return false;
  if (type == FX_SLIT && param == 1) return false;
  return true;
}

boolean tickFxParamLiveStack(ArrayList<FxUnit> stack, float dtSec) {
  if (stack == null || dtSec <= 0) return false;
  float k = 1f - exp(-dtSec / FX_PARAM_SMOOTH_SEC);
  k = constrain(k, 0, 1);
  boolean dirty = false;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null) continue;
    dirty |= fxApproachLive(u, 0, u.amount, k);
    dirty |= fxApproachLive(u, 1, u.amount2, k);
    dirty |= fxApproachLive(u, 2, u.amount3, k);
    dirty |= fxApproachLive(u, 3, u.amount4, k);
  }
  return dirty;
}

boolean fxApproachLive(FxUnit u, int param, float target, float k) {
  float live = param == 1 ? u.live1 : param == 2 ? u.live2 : param == 3 ? u.live3 : u.live0;
  if (!fxParamSmoothable(u.type, param)) {
    if (live == target) return false;
    if (param == 1) u.live1 = target;
    else if (param == 2) u.live2 = target;
    else if (param == 3) u.live3 = target;
    else u.live0 = target;
    return true;
  }
  float diff = abs(live - target);
  if (diff < 1e-5f) {
    if (live != target) {
      if (param == 1) u.live1 = target;
      else if (param == 2) u.live2 = target;
      else if (param == 3) u.live3 = target;
      else u.live0 = target;
      return true;
    }
    return false;
  }
  boolean hue = param == 0 && (u.type == FX_HUE || u.type == FX_COLORIZE);
  float next;
  if (hue) {
    float d = target - live;
    while (d > 180) d -= 360;
    while (d < -180) d += 360;
    next = live + d * k;
    if (next < 0) next += 360;
    else if (next >= 360) next -= 360;
    if (abs(d) < 0.08f) next = target;
  } else {
    next = lerp(live, target, k);
    if (abs(next - target) < 0.00025f * (1f + abs(target))) next = target;
  }
  if (param == 1) u.live1 = next;
  else if (param == 2) u.live2 = next;
  else if (param == 3) u.live3 = next;
  else u.live0 = next;
  return true;
}

void tickFxFadeStack(ArrayList<FxUnit> stack, float dt) {
  if (stack == null) return;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null) continue;
    float target = u.on ? 1 : 0;
    if (abs(u.fade - target) < 0.001f) {
      u.fade = target;
      continue;
    }
    if (u.fade < target) u.fade = min(1, u.fade + dt);
    else u.fade = max(0, u.fade - dt);
  }
}

void lerpFxPixels(int[] from, int[] to, float t) {
  t = constrain(t, 0, 1);
  float inv = 1 - t;
  for (int i = 0; i < to.length; i++) {
    int a = from[i], b = to[i];
    int r = (int) (((a >> 16) & 255) * inv + ((b >> 16) & 255) * t);
    int g = (int) (((a >> 8) & 255) * inv + ((b >> 8) & 255) * t);
    int bl = (int) ((a & 255) * inv + (b & 255) * t);
    to[i] = 0xFF000000 | (r << 16) | (g << 8) | bl;
  }
}

/** Active Live FX names for the preview HUD. */
String fxHudLine() {
  StringBuilder sb = new StringBuilder();
  appendFxHud(sb, fxLive, null);
  return sb.toString();
}

void appendFxHud(StringBuilder sb, ArrayList<FxUnit> stack, String prefix) {
  if (stack == null) return;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null || u.fade < 0.08f) continue;
    if (sb.length() > 0) sb.append("  ·  ");
    if (prefix != null) sb.append(prefix).append(" ");
    sb.append(fxName(u.type).toUpperCase());
  }
}

FxUnit fxFirst(ArrayList<FxUnit> stack, int type) {
  for (int i = 0; i < stack.size(); i++) {
    if (stack.get(i).type == type) return stack.get(i);
  }
  return null;
}

FxUnit fxEnsure(ArrayList<FxUnit> stack, int type) {
  FxUnit u = fxFirst(stack, type);
  if (u != null) return u;
  u = new FxUnit(type);
  stack.add(u);
  fxFocus = stack.size() - 1;
  return u;
}

void fxBump() {
  if (fxAffectLoop) loopImgHead = -1;
  liveFxReady = false;
  syncFlatFxFromLive();
  markDirty();
}

void fxAdd(int type) {
  // Rack is fixed — toggle existing type instead of growing the stack.
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  for (int i = 0; i < stack.size(); i++) {
    if (stack.get(i).type == type) {
      fxToggle(i);
      return;
    }
  }
}

void fxRemove(int index) {
  // Soft-clear: turn off with fade, keep rack slot.
  ArrayList<FxUnit> stack = fxActiveStack();
  if (index < 0 || index >= stack.size()) return;
  FxUnit u = stack.get(index);
  if (u.on || u.fade > 0.01f) {
    u.on = false;
    fxBump();
  }
}

void fxToggle(int index) {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (index < 0 || index >= stack.size()) return;
  fxMidiLatch(index, !stack.get(index).on);
}

/** Set FX slot on/off from MIDI without flip races. */
void fxMidiLatch(int index, boolean on) {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (index < 0 || index >= stack.size()) return;
  FxUnit u = stack.get(index);
  if (u.on == on) return;
  u.on = on;
  fxFocus = index;
  fxScroll = 0;
  // Hue/Sat: never enable into accidental B&W (sat default used to be 0).
  if (u.on && u.type == FX_HUE && u.amount2 < 0.02f) u.amount2 = 1;
  // Soft edges: leave fade to tickFxFades — kick slightly so off→on isn't stuck.
  if (u.on && u.fade < 0.02f) u.fade = 0.02f;
  if (!u.on && u.fade > 0.98f) u.fade = 0.98f;
  if (u.on) fxRevealPanel();
  fxBump();
  note(fxSlotKeyLabel(index) + "  " + fxName(u.type).toUpperCase() + (u.on ? " ON" : " OFF"));
}

/** Jump side panel to FX when an effect is turned on. */
void fxRevealPanel() {
  if (inspectorTab == 3) inspectorTab = lastWorkTab;
  setTopMode(TOP_FX);
}

void fxMove(int index, int dir) {
  ArrayList<FxUnit> stack = fxActiveStack();
  int j = index + dir;
  if (index < 0 || j < 0 || index >= stack.size() || j >= stack.size()) return;
  FxUnit a = stack.get(index);
  stack.set(index, stack.get(j));
  stack.set(j, a);
  fxFocus = j;
  fxBump();
}

void fxSetTarget(int target) {
  fxTarget = FX_TGT_LIVE;
}

void setFxAffectLive(boolean on) {
  if (fxAffectLive == on) return;
  fxAffectLive = on;
  liveFxReady = false;
  liveFxFrame = -1;
  if (!fxAffectLive) {
    fxFbLive = null;
    fxTrailLive = null;
    fxClearSlit(FX_TGT_LIVE);
    fxClearRgbDelay(FX_TGT_LIVE);
  }
  syncFlatFxFromLive();
  markDirty();
  note(fxAffectNote());
}

void setFxAffectLoop(boolean on) {
  if (fxAffectLoop == on) return;
  fxAffectLoop = on;
  loopImgHead = -1;
  if (!fxAffectLoop) {
    fxFbLoop = null;
    fxTrailLoop = null;
    fxClearSlit(FX_TGT_LOOP);
    fxClearRgbDelay(FX_TGT_LOOP);
  }
  markDirty();
  note(fxAffectNote());
}

void toggleFxAffectLive() {
  setFxAffectLive(!fxAffectLive);
}

void toggleFxAffectLoop() {
  setFxAffectLoop(!fxAffectLoop);
}

String fxAffectNote() {
  if (fxAffectLive && fxAffectLoop) return "FX  →  LIVE + LOOP";
  if (fxAffectLive) return "FX  →  LIVE";
  if (fxAffectLoop) return "FX  →  LOOP";
  return "FX  →  OFF";
}

void fxClearStack(ArrayList<FxUnit> stack) {
  stack.clear();
}

/** Params → defaults; leaves on/off alone. */
void fxResetUnit(int index) {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  if (index < 0 || index >= stack.size()) return;
  FxUnit u = stack.get(index);
  u.amount = fxDefaultAmount(u.type);
  u.amount2 = fxDefaultAmount2(u.type);
  u.amount3 = fxDefaultAmount3(u.type);
  u.amount4 = fxDefaultAmount4(u.type);
  fxFocus = index;
  fxBump();
  note(fxSlotKeyLabel(index) + "  " + fxName(u.type).toUpperCase() + "  reset");
}

/** Kill switch: every rack off (keeps amounts). */
void fxAllOff() {
  fxAllOffStack(fxLive);
  fxAllOffStack(fxLoop);
  fxAllOffStack(fxOut);
  fxClearFxRuntime();
  syncFlatFxFromLive();
  markDirty();
}

void fxAllOffStack(ArrayList<FxUnit> stack) {
  if (stack == null) return;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null) continue;
    u.on = false;
    u.fade = 0;
  }
}

/** Params → defaults for every unit in a stack (on/off unchanged). */
void fxResetStackAmounts(ArrayList<FxUnit> stack) {
  if (stack == null) return;
  ensureFxRack(stack);
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null) continue;
    u.amount = fxDefaultAmount(u.type);
    u.amount2 = fxDefaultAmount2(u.type);
    u.amount3 = fxDefaultAmount3(u.type);
    u.amount4 = fxDefaultAmount4(u.type);
  }
}

void fxClearFxRuntime() {
  fxFbLive = fxFbLoop = fxFbOut = null;
  fxTrailLive = fxTrailLoop = fxTrailOut = null;
  fxSlitLive = fxSlitLoop = fxSlitOut = null;
  fxSlitPhase[0] = fxSlitPhase[1] = fxSlitPhase[2] = 0;
  fxClearRgbDelay(-1);
  feedbackBuf = null;
  liveFxReady = false;
  liveFxFrame = -1;
  loopImgHead = -1;
}

/** All racks: off + defaults + clear runtime / curve banks. Affect → Live only. */
void fxResetAll() {
  ensureAllFxRacks();
  fxAllOffStack(fxLive);
  fxAllOffStack(fxLoop);
  fxAllOffStack(fxOut);
  fxResetStackAmounts(fxLive);
  fxResetStackAmounts(fxLoop);
  fxResetStackAmounts(fxOut);
  fxAffectLive = true;
  fxAffectLoop = false;
  fxClearFxRuntime();
  resetCurveBankAll(1);
  resetCurveBankAll(2);
  resetCurveBankAll(3);
  fxPickerOpen = false;
  syncFlatFxFromLive();
  markDirty();
}

/** Active target rack: all off + defaults. */
void fxResetActiveStack() {
  ArrayList<FxUnit> stack = fxActiveStack();
  ensureFxRack(stack);
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    u.on = false;
    u.fade = 0;
    u.amount = fxDefaultAmount(u.type);
    u.amount2 = fxDefaultAmount2(u.type);
    u.amount3 = fxDefaultAmount3(u.type);
    u.amount4 = fxDefaultAmount4(u.type);
  }
  if (fxTarget == FX_TGT_LIVE) {
    fxFbLive = null;
    fxTrailLive = null;
    feedbackBuf = null;
    liveFxReady = false;
    fxClearSlit(FX_TGT_LIVE);
    syncFlatFxFromLive();
    resetCurveBankAll(2);
  } else if (fxTarget == FX_TGT_LOOP) {
    fxFbLoop = null;
    fxTrailLoop = null;
    loopImgHead = -1;
    fxClearSlit(FX_TGT_LOOP);
    resetCurveBankAll(3);
  } else {
    fxFbOut = null;
    fxTrailOut = null;
    fxClearSlit(FX_TGT_OUT);
    resetCurveBankAll(1);
  }
  fxFocus = 0;
  fxPickerOpen = false;
  fxBump();
  note("FX  " + fxTargetLabel(fxTarget).toUpperCase() + "  reset");
}

void resetEffects() {
  liveOpacity = 1;
  loopOpacity = 1;
  fxClearStack(fxLive);
  fxClearStack(fxLoop);
  fxClearStack(fxOut);
  ensureAllFxRacks();
  fxFeedback = 0;
  fxHue = 0;
  fxPosterize = 0;
  fxThreshold = 0;
  fxPixel = 1;
  fxInvert = false;
  fxFbLive = fxFbLoop = fxFbOut = null;
  fxTrailLive = fxTrailLoop = fxTrailOut = null;
  fxSlitLive = fxSlitLoop = fxSlitOut = null;
  fxSlitPhase[0] = fxSlitPhase[1] = fxSlitPhase[2] = 0;
  fxFadeScratch = null;
  feedbackBuf = null;
  liveFxReady = false;
  liveFxFrame = -1;
  fxFocus = 0;
  fxPickerOpen = false;
  loopImgHead = -1;
  if (curves != null) {
    for (int b = 1; b <= 3; b++) {
      for (int i = 0; i < 4; i++) resetCurveBank(b, i);
    }
  }
  markDirty();
}

void syncFlatFxFromLive() {
  FxUnit hue = fxFirst(fxLive, FX_HUE);
  FxUnit post = fxFirst(fxLive, FX_POST);
  FxUnit thr = fxFirst(fxLive, FX_THR);
  FxUnit pix = fxFirst(fxLive, FX_PIX);
  FxUnit inv = fxFirst(fxLive, FX_INV);
  FxUnit fb = fxFirst(fxLive, FX_FB);
  fxHue = (hue != null && hue.on) ? hue.amount : 0;
  fxPosterize = (post != null && post.on) ? max(2, round(post.amount)) : 0;
  fxThreshold = (thr != null && thr.on) ? thr.amount : 0;
  fxPixel = (pix != null && pix.on) ? max(2, round(pix.amount)) : 1;
  fxInvert = inv != null && inv.on;
  fxFeedback = (fb != null && fb.on) ? constrain(fb.amount, 0, 1) : 0;
}

void migrateFlatFxToLive() {
  if (fxLive.size() > 0) return;
  if (fxHue > 0.5) {
    FxUnit u = new FxUnit(FX_HUE);
    u.amount = fxHue;
    fxLive.add(u);
  }
  if (fxPosterize >= 2) {
    FxUnit u = new FxUnit(FX_POST);
    u.amount = fxPosterize;
    fxLive.add(u);
  }
  if (fxThreshold > 0.02) {
    FxUnit u = new FxUnit(FX_THR);
    u.amount = fxThreshold;
    fxLive.add(u);
  }
  if (fxPixel > 1) {
    FxUnit u = new FxUnit(FX_PIX);
    u.amount = fxPixel;
    fxLive.add(u);
  }
  if (fxInvert) fxLive.add(new FxUnit(FX_INV));
  if (fxFeedback > 0.004) {
    FxUnit u = new FxUnit(FX_FB);
    u.amount = fxFeedback;
    fxLive.add(u);
  }
}

void fxSetAmountFromSlider(String id, float v) {
  int type = -1;
  if (id.equals("sl-fb")) type = FX_FB;
  else if (id.equals("sl-hue")) type = FX_HUE;
  else if (id.equals("sl-post")) type = FX_POST;
  else if (id.equals("sl-thr")) type = FX_THR;
  else if (id.equals("sl-pix")) type = FX_PIX;
  else return;
  FxUnit u = fxEnsure(fxLive, type);
  if (type == FX_POST) u.amount = round(v) < 2 ? 0 : round(v);
  else if (type == FX_PIX) u.amount = round(v) < 2 ? 1 : round(v);
  else if (type == FX_THR) u.amount = v < 0.03 ? 0 : v;
  else u.amount = v;
  u.on = true;
  if (type == FX_POST && u.amount < 2) u.on = false;
  if (type == FX_PIX && u.amount < 2) u.on = false;
  if (type == FX_THR && u.amount <= 0.02) u.on = false;
  if (type == FX_FB && u.amount <= 0.004) u.on = false;
  syncFlatFxFromLive();
}

void fxSetInvert(boolean on) {
  FxUnit u = fxEnsure(fxLive, FX_INV);
  u.on = on;
  u.amount = on ? 1 : 0;
  syncFlatFxFromLive();
}

boolean fxApplySlider(String id, float v) {
  if (id == null || !id.startsWith("sl-fx#")) return false;
  int param = int(id.substring(6));
  FxUnit u = fxFocusedUnit();
  if (u == null || !fxParamUsed(u.type, param)) return true;
  fxParamSet(u, param, v);
  fxBump();
  return true;
}

int[] fxFeedbackBuf(int target) {
  if (target == FX_TGT_LOOP) return fxFbLoop;
  if (target == FX_TGT_OUT) return fxFbOut;
  return fxFbLive != null ? fxFbLive : feedbackBuf;
}

int[] fxTrailBuf(int target) {
  if (target == FX_TGT_LOOP) return fxTrailLoop;
  if (target == FX_TGT_OUT) return fxTrailOut;
  return fxTrailLive;
}

void fxStoreFeedback(int target, int[] px) {
  if (px == null) return;
  int n = px.length;
  if (target == FX_TGT_LOOP) {
    if (fxFbLoop == null || fxFbLoop.length != n) fxFbLoop = new int[n];
    arrayCopy(px, fxFbLoop);
  } else if (target == FX_TGT_OUT) {
    if (fxFbOut == null || fxFbOut.length != n) fxFbOut = new int[n];
    arrayCopy(px, fxFbOut);
  } else {
    if (fxFbLive == null || fxFbLive.length != n) fxFbLive = new int[n];
    arrayCopy(px, fxFbLive);
    feedbackBuf = fxFbLive;
  }
}

void fxStoreTrail(int target, int[] px) {
  if (px == null) return;
  int n = px.length;
  if (target == FX_TGT_LOOP) {
    if (fxTrailLoop == null || fxTrailLoop.length != n) fxTrailLoop = new int[n];
    arrayCopy(px, fxTrailLoop);
  } else if (target == FX_TGT_OUT) {
    if (fxTrailOut == null || fxTrailOut.length != n) fxTrailOut = new int[n];
    arrayCopy(px, fxTrailOut);
  } else {
    if (fxTrailLive == null || fxTrailLive.length != n) fxTrailLive = new int[n];
    arrayCopy(px, fxTrailLive);
  }
}

void applyFxStack(ArrayList<FxUnit> stack, int[] px, int w, int h, int target) {
  if (!fxStackActive(stack) || px == null || w < 2 || h < 2) return;
  if (px.length < w * h) return;
  try {
    fxSlitApplyTarget = target;
    fxRgbDelayTarget = target;
    int[] fb = fxFeedbackBuf(target);
    int[] trail = fxTrailBuf(target);
    int n = w * h;
    // Everything else first, then Echo. Effects stay inside the feedback loop
    // instead of reprocessing the already mixed trail.
    applyFxStackPass(stack, px, w, h, fb, trail, n, false);
    boolean usedEcho = applyFxStackPass(stack, px, w, h, fb, trail, n, true);
    if (usedEcho) {
      fxStoreFeedback(target, px);
      fxStoreTrail(target, px);
    }
  } catch (Throwable t) {
    println("FX stack error: " + t.getMessage());
  }
}

/** Copy of active units for off-thread overdub bake (live values frozen). */
ArrayList<FxUnit> fxSnapshotActive(ArrayList<FxUnit> stack) {
  ArrayList<FxUnit> out = new ArrayList<FxUnit>();
  if (stack == null) return out;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null || u.fade < 0.01f) continue;
    FxUnit c = new FxUnit(u.type, false);
    c.on = u.on;
    c.fade = u.fade;
    c.amount = u.amount;
    c.amount2 = u.amount2;
    c.amount3 = u.amount3;
    c.amount4 = u.amount4;
    c.live0 = u.live0;
    c.live1 = u.live1;
    c.live2 = u.live2;
    c.live3 = u.live3;
    out.add(c);
  }
  return out;
}

/**
 * Apply a snapped stack during overdub bake on the worker thread.
 * Uses the Output FX buffers so Live/Loop playback is undisturbed.
 */
void applyFxStackForBake(ArrayList<FxUnit> stack, int[] px, int w, int h) {
  if (stack == null || stack.isEmpty() || px == null || w < 2 || h < 2) return;
  if (px.length < w * h) return;
  try {
    applyFxStack(stack, px, w, h, FX_TGT_OUT);
  } catch (Throwable t) {
    println("FX bake error: " + t.getMessage());
  }
}

void fxClearOutRuntime() {
  fxFbOut = null;
  fxTrailOut = null;
  fxClearSlit(FX_TGT_OUT);
  fxClearRgbDelay(FX_TGT_OUT);
}

boolean applyFxStackPass(ArrayList<FxUnit> stack, int[] px, int w, int h, int[] fb, int[] trail, int n, boolean echoPass) {
  boolean usedEcho = false;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (u == null || u.fade < 0.01f) continue;
    boolean echo = u.type == FX_FB || u.type == FX_TRAIL;
    if (echo != echoPass) continue;
    if (echo) usedEcho = true;
    if (u.fade >= 0.995f) {
      applyFxUnit(u, px, w, h, fb, trail);
    } else {
      if (fxFadeScratch == null || fxFadeScratch.length != n) fxFadeScratch = new int[n];
      arrayCopy(px, 0, fxFadeScratch, 0, n);
      applyFxUnit(u, px, w, h, fb, trail);
      lerpFxPixels(fxFadeScratch, px, u.fade);
    }
  }
  return usedEcho;
}

void fxHoldSource(int[] px) {
  int n = px.length;
  if (fxHold == null || fxHold.length != n) fxHold = new int[n];
  arrayCopy(px, fxHold);
}

void fxMixHeld(int[] px, float mix) {
  if (fxHold == null || fxHold.length != px.length) return;
  mix = constrain(mix, 0, 1);
  if (mix >= 0.995f) return;
  if (mix <= 0.005f) {
    arrayCopy(fxHold, px);
    return;
  }
  lerpFxPixels(fxHold, px, mix);
}

/** Extra mix-with-source. 1 = the effect fully replaces the frame (today's look). */
float fxPostMix(FxUnit u) {
  int t = u.type;
  if (t == FX_HUE || t == FX_THR || t == FX_SOLAR || t == FX_SLIDE || t == FX_PUSH) return u.live2;
  if (t == FX_SAT || t == FX_CONTRAST || t == FX_POST || t == FX_PIX || t == FX_BLUR || t == FX_EMBOSS) return u.live1;
  if (t == FX_KALEIDO || t == FX_RIPPLE || t == FX_SLICES || t == FX_TRAIL
    || t == FX_ROTATE || t == FX_SLIT || t == FX_RGBDELAY) return u.live2;
  if (t == FX_ROT180) return u.live0;
  return 1;
}

void applyFxUnit(FxUnit u, int[] px, int w, int h, int[] fb, int[] trail) {
  int t = u.type;
  float a0 = u.live0, a1 = u.live1, a2 = u.live2, a3 = u.live3;
  float post = fxPostMix(u);
  boolean hold = post < 0.995f;
  if (hold) fxHoldSource(px);
  if (t == FX_PIX) pixelateBuffer(px, w, h, max(2, round(a0)), a2, a3);
  else if (t == FX_INV) invertBuffer(px, a0, a1, a2, a3);
  else if (t == FX_BLUR) blurBuffer(px, w, h, constrain(round(a0 * 8), 1, 40), a2, a3);
  else if (t == FX_EDGE) edgeBuffer(px, w, h, a0, a1, a2, a3);
  else if (t == FX_EMBOSS) embossBuffer(px, w, h, a0, a2, a3);
  else if (t == FX_SLIT) slitScanBuffer(px, w, h, a0, a1, a2);
  else if (t == FX_GLITCH) glitchBuffer(px, w, h, a0, a1, a2, a3);
  else if (t == FX_MIRROR) {
    int mode = constrain(round(a1), 0, 1);
    mirrorAxisBuffer(px, w, h, constrain(a0, 0, 1), mode, a2, a3);
  } else if (t == FX_MIRROR_H) {
    mirrorBuffer(px, w, h, constrain(a0, 0, 1), 0, constrain(0.5f + a1, 0.05f, 0.95f), 0.5f, a2, a3);
  } else if (t == FX_MIRROR_V) {
    mirrorBuffer(px, w, h, constrain(a0, 0, 1), 1, 0.5f, constrain(0.5f + a1, 0.05f, 0.95f), a2, a3);
  } else if (t == FX_QUAD) {
    mirrorBuffer(px, w, h, constrain(a0, 0, 1), 2,
      constrain(0.5f + a1, 0.05f, 0.95f), constrain(0.5f + a2, 0.05f, 0.95f), a3, 0);
  } else if (t == FX_FLIP || t == FX_FLIP_V) {
    int mode = t == FX_FLIP_V ? 1 : constrain(round(a1), 0, 2);
    float mix = constrain(a0, 0, 1);
    float soft = a2;
    float zoom = a3;
    if (mode == 0) flipBuffer(px, w, h, true, mix, 0, soft, zoom);
    else if (mode == 1) flipBuffer(px, w, h, false, mix, 0, soft, zoom);
    else {
      flipBuffer(px, w, h, true, mix, 0, soft, zoom);
      flipBuffer(px, w, h, false, 1, 0, 0, 1);
    }
  }
  else if (t == FX_ROT180) {
    float ang = 180 + a1;
    if (abs(a3) > 0.001f) ang += a3 * millis() * 0.09f;
    rotateBuffer(px, w, h, ang, a2);
  } else if (t == FX_ROTATE) {
    float spin = constrain(a1, -1, 1);
    rotateBuffer(px, w, h, a0 + spin * millis() * 0.09f, a2);
  } else if (t == FX_SLIDE) slideBuffer(px, w, h, a0, constrain(round(a1), 0, 3), false, a3);
  else if (t == FX_PUSH) slideBuffer(px, w, h, a0, constrain(round(a1), 0, 3), true, a3);
  else if (t == FX_KALEIDO) kaleidoBuffer(px, w, h, max(2, round(a0)), a1, a2);
  else if (t == FX_TWIRL) twirlBuffer(px, w, h, a0 * 4f, constrain(a1, 0.05f, 1), a2, a3);
  else if (t == FX_RIPPLE) rippleBuffer(px, w, h, a0 * 28f, 2 + a1 * 18f, a2);
  else if (t == FX_BULGE) bulgeBuffer(px, w, h, a0, a1, a2, a3);
  else if (t == FX_SLICES) slicesBuffer(px, w, h, max(2, round(a0)), a1, a2);
  else if (t == FX_TRAIL) echoBuffer(px, trail != null ? trail : fb, a0, 1, w, h, 0, 0, a1, a2);
  else if (t == FX_FB) echoBuffer(px, fb != null ? fb : trail, a0, a1, w, h, a2, a3, 0, 1);
  else if (t == FX_RGBDELAY) rgbDelayBuffer(px, w, h, a0, a1, a3);
  else if (t == FX_STROBE) strobeBuffer(px, a0, a1, a2, a3);
  else if (t == FX_SAT) {
    hueSatBuffer(px, a3, a0);
    if (abs(a2) > 0.004f) contrastBuffer(px, a2);
  } else if (t == FX_CONTRAST) contrastBuffer(px, a0, a2, a3);
  else if (t == FX_SOLAR) {
    solarBuffer(px, a0, a1);
    if (abs(a3 - 1) > 0.01f) hueSatBuffer(px, 0, a3);
  } else if (t == FX_COLORIZE) colorizeBuffer(px, a0, a1, a2, a3);
  else if (t == FX_HUE) {
    hueSatBuffer(px, a0, a1);
    fxLiftBuffer(px, a3);
  } else if (t == FX_POST) {
    posterizeBuffer(px, round(a0));
    if (abs(a2 - 1) > 0.01f) hueSatBuffer(px, 0, a2);
    if (abs(a3) > 0.004f) contrastBuffer(px, a3);
  } else if (t == FX_THR) thresholdBuffer(px, a0, a1, a3);
  if (hold) fxMixHeld(px, post);
}

void fxLiftBuffer(int[] px, float light) {
  if (abs(light) < 0.004f) return;
  float d = light * 255f;
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    px[i] = packRgb(((c >> 16) & 255) + d, ((c >> 8) & 255) + d, (c & 255) + d);
  }
}

void fxClearRgbDelay(int target) {
  if (target < 0) {
    for (int t = 0; t < 3; t++) fxClearRgbDelay(t);
    return;
  }
  int t = constrain(target, 0, 2);
  rgbDelayFrames[t] = null;
  rgbDelayHead[t] = 0;
  rgbDelayCount[t] = 0;
  rgbDelayN[t] = 0;
}

void rgbDelayEnsure(int target, int n) {
  int t = constrain(target, 0, 2);
  if (rgbDelayFrames[t] != null && rgbDelayN[t] == n) return;
  rgbDelayFrames[t] = new int[RGB_DELAY_MAX][];
  rgbDelayHead[t] = 0;
  rgbDelayCount[t] = 0;
  rgbDelayN[t] = n;
}

/** History slot framesAgo ago (0 = newest). Null if empty. */
int[] rgbDelayFrameAt(int target, int framesAgo) {
  int[][] frames = rgbDelayFrames[target];
  int count = rgbDelayCount[target];
  if (frames == null || count <= 0) return null;
  int ago = constrain(framesAgo, 0, count - 1);
  int head = rgbDelayHead[target];
  int slot = (head - 1 - ago + RGB_DELAY_MAX * 4) % RGB_DELAY_MAX;
  return frames[slot];
}

/**
 * RGB Delay: R / G / B from different points in a short frame history.
 * delay 0..1 → depth, spread 0..1 → channel separation, order 0=RGB 1=BGR.
 * Mix is handled by fxPostMix (amount3).
 * Hot path: resolve three frame pointers once, nearest-neighbor (no per-pixel lerp).
 */
void rgbDelayBuffer(int[] px, int w, int h, float delay, float spread, float order) {
  if (px == null || w < 2 || h < 2) return;
  int n = w * h;
  if (px.length < n) return;
  int target = constrain(fxRgbDelayTarget, 0, 2);
  rgbDelayEnsure(target, n);
  int[][] frames = rgbDelayFrames[target];
  int head = rgbDelayHead[target];
  // Push current frame into the ring first.
  if (frames[head] == null || frames[head].length != n) frames[head] = new int[n];
  arrayCopy(px, 0, frames[head], 0, n);
  rgbDelayHead[target] = (head + 1) % RGB_DELAY_MAX;
  if (rgbDelayCount[target] < RGB_DELAY_MAX) rgbDelayCount[target]++;

  float maxD = (RGB_DELAY_MAX - 1) * constrain(delay, 0, 1);
  float sp = constrain(spread, 0, 1);
  float o = constrain(order, 0, 1);
  float fR = maxD * o;
  float fB = maxD * (1f - o);
  float fG = (fR + fB) * 0.5f;
  float mean = (fR + fG + fB) / 3f;
  fR = lerp(mean, fR, sp);
  fG = lerp(mean, fG, sp);
  fB = lerp(mean, fB, sp);

  int[] srcR = rgbDelayFrameAt(target, round(fR));
  int[] srcG = rgbDelayFrameAt(target, round(fG));
  int[] srcB = rgbDelayFrameAt(target, round(fB));
  if (srcR == null) srcR = px;
  if (srcG == null) srcG = px;
  if (srcB == null) srcB = px;

  for (int i = 0; i < n; i++) {
    px[i] = 0xFF000000
      | (((srcR[i] >> 16) & 255) << 16)
      | (((srcG[i] >> 8) & 255) << 8)
      | (srcB[i] & 255);
  }
}

void hueBuffer(int[] px, float deg) {
  hueSatBuffer(px, deg, 1);
}

/** Hue rotate + saturation. sat 0 = B&W, 1 = full chroma (optional >1 boost). */
void hueSatBuffer(int[] px, float deg, float sat) {
  boolean doHue = deg > 0.5f;
  float s = max(0, sat);
  if (!doHue && abs(s - 1) < 0.001f) return;
  float cosA = 1, sinA = 0;
  if (doHue) {
    float a = radians(deg);
    cosA = cos(a);
    sinA = sin(a);
  }
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    float r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    if (doHue) {
      float nr = r * (0.213f + cosA * 0.787f - sinA * 0.213f)
        + g * (0.715f - cosA * 0.715f - sinA * 0.715f)
        + b * (0.072f - cosA * 0.072f + sinA * 0.928f);
      float ng = r * (0.213f - cosA * 0.213f + sinA * 0.143f)
        + g * (0.715f + cosA * 0.285f + sinA * 0.140f)
        + b * (0.072f - cosA * 0.072f - sinA * 0.283f);
      float nb = r * (0.213f - cosA * 0.213f - sinA * 0.787f)
        + g * (0.715f - cosA * 0.715f + sinA * 0.715f)
        + b * (0.072f + cosA * 0.928f + sinA * 0.072f);
      r = nr; g = ng; b = nb;
    }
    if (abs(s - 1) > 0.001f) {
      float l = r * 0.299f + g * 0.587f + b * 0.114f;
      r = l + (r - l) * s;
      g = l + (g - l) * s;
      b = l + (b - l) * s;
    }
    px[i] = packRgb(r, g, b);
  }
}

void posterizeBuffer(int[] px, int post) {
  if (post < 2) return;
  int postStep = max(1, 255 / (post - 1));
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    int r = ((c >> 16) & 255) / postStep * postStep;
    int g = ((c >> 8) & 255) / postStep * postStep;
    int b = (c & 255) / postStep * postStep;
    px[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
  }
}

void thresholdBuffer(int[] px, float thrN) {
  thresholdBuffer(px, thrN, 0, 1);
}

void thresholdBuffer(int[] px, float thrN, float soft, float gain) {
  if (thrN <= 0.02f && soft < 0.01f) return;
  int thr = (int) (thrN * 255);
  boolean plain = soft < 0.01f && abs(gain - 1) < 0.01f;
  float knee = max(1, soft * 90f);
  float g = constrain(gain, 0, 2);
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    int l = (((c >> 16) & 255) * 299 + ((c >> 8) & 255) * 587 + (c & 255) * 114) / 1000;
    float t;
    if (plain) t = l >= thr ? 1 : 0;
    else t = constrain((l - thr) / knee + 0.5f, 0, 1);
    int v = constrain(round(t * 255f * g), 0, 255);
    px[i] = 0xFF000000 | (v << 16) | (v << 8) | v;
  }
}

void feedbackMixBuffer(int[] px, int[] fb, float amt) {
  echoBuffer(px, fb, amt, 0);
}

/**
 * Combined Feedback ↔ Trail.
 * style 0 = classic feedback mix, 1 = light-trail.
 * At max amount (+ trail style): light-painting — nothing decays, everything stays.
 */
void echoBuffer(int[] px, int[] buf, float amt, float style) {
  echoBuffer(px, buf, amt, style, 0, 0, 0, 0, 0, 1);
}

void echoBuffer(int[] px, int[] buf, float amt, float style, int w, int h, float zoom, float rotDeg, float thr, float sat) {
  if (amt <= 0.004f || buf == null || buf.length != px.length) return;
  boolean plain = abs(zoom) < 0.001f && abs(rotDeg) < 0.5f && thr < 0.01f && abs(sat - 1) < 0.01f;
  if (!plain && w > 1 && h > 1) {
    echoBufferShaped(px, buf, amt, style, w, h, zoom, rotDeg, thr, sat);
    return;
  }
  float a = constrain(amt, 0, 1);
  float s = constrain(style, 0, 1);
  // Full hold once the slider is effectively max — true light paint, no fade.
  boolean paint = a >= 0.995f;
  float decay = paint ? 1f : a;
  // Feedback never quite 1.0 (would freeze the frame); paint mode leans on trail.
  float fbk = paint ? 0.92f : a;
  float inv = 1 - fbk;
  for (int i = 0; i < px.length; i++) {
    int c = px[i], f = buf[i];
    int cr = (c >> 16) & 255, cg = (c >> 8) & 255, cb = c & 255;
    int fr = (f >> 16) & 255, fg = (f >> 8) & 255, fblu = f & 255;
    // Feedback: lerp current with previous frame
    float fbr = cr * inv + fr * fbk;
    float fbg = cg * inv + fg * fbk;
    float fbb = cb * inv + fblu * fbk;
    // Trail / light-paint: keep max of current and (held) previous
    float trr = max(cr, fr * decay);
    float trg = max(cg, fg * decay);
    float trb = max(cb, fblu * decay);
    // At full paint, lock to trail so every bright pixel persists.
    float mix = paint ? max(s, 0.85f) : s;
    float r = fbr + (trr - fbr) * mix;
    float g = fbg + (trg - fbg) * mix;
    float b = fbb + (trb - fbb) * mix;
    px[i] = packRgb(r, g, b);
  }
}

/** Feedback buffer scaled/rotated before the mix. zoom 0 and rot 0 match echoBuffer. */
void echoBufferShaped(int[] px, int[] buf, float amt, float style, int w, int h, float zoom, float rotDeg, float thr, float sat) {
  float a = constrain(amt, 0, 1);
  float s = constrain(style, 0, 1);
  boolean paint = a >= 0.995f;
  float decay = paint ? 1f : a;
  float fbk = paint ? 0.92f : a;
  float inv = 1 - fbk;
  float mix = paint ? max(s, 0.85f) : s;
  float z = max(0.2f, 1 + zoom * 0.45f);
  float ang = radians(rotDeg);
  float ca = cos(ang), sa = sin(ang);
  float cx = (w - 1) * 0.5f, cy = (h - 1) * 0.5f;
  int cut = (int) (constrain(thr, 0, 1) * 255);
  float chroma = max(0, sat);
  for (int y = 0; y < h; y++) {
    int row = y * w;
    for (int x = 0; x < w; x++) {
      int i = row + x;
      int c = px[i];
      float dx = (x - cx) / z;
      float dy = (y - cy) / z;
      float sx = cx + dx * ca + dy * sa;
      float sy = cy - dx * sa + dy * ca;
      int f = sampleNearest(buf, w, h, sx, sy);
      int cr = (c >> 16) & 255, cg = (c >> 8) & 255, cb = c & 255;
      if (cut > 0) {
        int l = (cr * 299 + cg * 587 + cb * 114) / 1000;
        if (l < cut) { cr = 0; cg = 0; cb = 0; }
      }
      int fr = (f >> 16) & 255, fg = (f >> 8) & 255, fblu = f & 255;
      float fbr = cr * inv + fr * fbk;
      float fbg = cg * inv + fg * fbk;
      float fbb = cb * inv + fblu * fbk;
      float trr = max(cr, fr * decay);
      float trg = max(cg, fg * decay);
      float trb = max(cb, fblu * decay);
      float r = fbr + (trr - fbr) * mix;
      float g = fbg + (trg - fbg) * mix;
      float b = fbb + (trb - fbb) * mix;
      if (abs(chroma - 1) > 0.01f) {
        float l = r * 0.299f + g * 0.587f + b * 0.114f;
        r = l + (r - l) * chroma;
        g = l + (g - l) * chroma;
        b = l + (b - l) * chroma;
      }
      px[i] = packRgb(r, g, b);
    }
  }
}

void invertBuffer(int[] px) {
  invertBuffer(px, 1, 1, 1, 1);
}

void invertBuffer(int[] px, float mix, float rAmt, float gAmt, float bAmt) {
  float m = constrain(mix, 0, 1);
  if (m <= 0.005f) return;
  float ar = constrain(rAmt, 0, 1), ag = constrain(gAmt, 0, 1), ab = constrain(bAmt, 0, 1);
  if (m >= 0.995f && ar >= 0.995f && ag >= 0.995f && ab >= 0.995f) {
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    px[i] = 0xFF000000
      | ((255 - ((c >> 16) & 255)) << 16)
      | ((255 - ((c >> 8) & 255)) << 8)
      | (255 - (c & 255));
  }
    return;
  }
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    float r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    float ir = r + (255 - 2 * r) * ar;
    float ig = g + (255 - 2 * g) * ag;
    float ib = b + (255 - 2 * b) * ab;
    px[i] = packRgb(r + (ir - r) * m, g + (ig - g) * m, b + (ib - b) * m);
  }
}

void satBuffer(int[] px, float amt) {
  // 0 = B&W, 1 = full chroma (legacy picker FX_SAT)
  hueSatBuffer(px, 0, constrain(amt, 0, 1.5f));
}

void contrastBuffer(int[] px, float amt) {
  contrastBuffer(px, amt, 0.5f, 0);
}

void contrastBuffer(int[] px, float amt, float pivot, float bright) {
  float ct = 1 + amt * 1.4f;
  boolean plain = abs(pivot - 0.5f) < 0.01f && abs(bright) < 0.004f;
  float piv = plain ? 128 : constrain(pivot, 0, 1) * 255f;
  float br = plain ? 0 : bright * 128f;
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    float r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    px[i] = packRgb((r - piv) * ct + piv + br, (g - piv) * ct + piv + br, (b - piv) * ct + piv + br);
  }
}

void solarBuffer(int[] px, float thrN) {
  solarBuffer(px, thrN, 0);
}

void solarBuffer(int[] px, float thrN, float soft) {
  int thr = (int) (constrain(thrN, 0, 1) * 255);
  float knee = soft * 80f;
  boolean plain = soft < 0.01f;
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    float r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    int l = (int) (r * 0.299f + g * 0.587f + b * 0.114f);
    float k = plain ? (l >= thr ? 1 : 0) : constrain((l - thr) / max(1, knee) + 0.5f, 0, 1);
    if (k > 0) {
      r = r + (255 - 2 * r) * k;
      g = g + (255 - 2 * g) * k;
      b = b + (255 - 2 * b) * k;
    }
    px[i] = packRgb(r, g, b);
  }
}

void colorizeBuffer(int[] px, float hueDeg, float mix) {
  colorizeBuffer(px, hueDeg, mix, 1, 0);
}

void colorizeBuffer(int[] px, float hueDeg, float mix, float sat, float light) {
  mix = constrain(mix, 0, 1);
  float chroma = max(0, sat);
  float lift = light * 255f;
  boolean plain = abs(chroma - 1) < 0.01f && abs(light) < 0.004f;
  float h = (hueDeg % 360 + 360) % 360 / 60f;
  int sector = (int) h;
  float f = h - sector;
  float tr, tg, tb;
  if (sector == 0) { tr = 1; tg = f; tb = 0; }
  else if (sector == 1) { tr = 1 - f; tg = 1; tb = 0; }
  else if (sector == 2) { tr = 0; tg = 1; tb = f; }
  else if (sector == 3) { tr = 0; tg = 1 - f; tb = 1; }
  else if (sector == 4) { tr = f; tg = 0; tb = 1; }
  else { tr = 1; tg = 0; tb = 1 - f; }
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    float r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    float l = (r * 0.299f + g * 0.587f + b * 0.114f) / 255f;
    float gray = l * 255f;
    float cr = plain ? l * tr * 255 : gray + (l * tr * 255 - gray) * chroma;
    float cg = plain ? l * tg * 255 : gray + (l * tg * 255 - gray) * chroma;
    float cb = plain ? l * tb * 255 : gray + (l * tb * 255 - gray) * chroma;
    float or = r + (cr - r) * mix;
    float og = g + (cg - g) * mix;
    float ob = b + (cb - b) * mix;
    if (!plain) { or += lift; og += lift; ob += lift; }
    px[i] = packRgb(or, og, ob);
  }
}

void pixelateBuffer(int[] px, int w, int h, int block) {
  pixelateBuffer(px, w, h, block, 1, 1);
}

void pixelateBuffer(int[] px, int w, int h, int block, float xScale, float yScale) {
  int bw = block;
  int bh = block;
  if (abs(xScale - 1) > 0.02f) bw = max(1, round(block * xScale));
  if (abs(yScale - 1) > 0.02f) bh = max(1, round(block * yScale));
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  for (int y = 0; y < h; y += bh) {
    int by = min(h - 1, y + bh / 2);
    int y2 = min(h, y + bh);
    for (int x = 0; x < w; x += bw) {
      int bx = min(w - 1, x + bw / 2);
      int c = fxScratch[by * w + bx];
      int x2 = min(w, x + bw);
      for (int yy = y; yy < y2; yy++) {
        int row = yy * w;
        for (int xx = x; xx < x2; xx++) px[row + xx] = c;
      }
    }
  }
}

void blurBuffer(int[] px, int w, int h, int rad) {
  blurBuffer(px, w, h, rad, 1, 1);
}

void blurBuffer(int[] px, int w, int h, int rad, float horiz, float vert) {
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  if (abs(horiz - 1) < 0.02f && abs(vert - 1) < 0.02f) {
    blurBox(px, fxScratch, w, h, rad);
  } else {
    int rh = constrain(round(rad * horiz), 0, 80);
    int rv = constrain(round(rad * vert), 0, 80);
    blurBoxAxes(px, fxScratch, w, h, rh, rv);
  }
  arrayCopy(fxScratch, px);
}

void edgeBuffer(int[] px, int w, int h, float amt, float mixAmt) {
  edgeBuffer(px, w, h, amt, mixAmt, 0, 1);
}

void edgeBuffer(int[] px, int w, int h, float amt, float mixAmt, float thresh, float thick) {
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  float k = constrain(amt, 0, 1) * 2.2f;
  float mix = constrain(mixAmt, 0, 1);
  int d = constrain(round(thick), 1, 5);
  int thr = (int) (constrain(thresh, 0, 1) * 200);
  // step 2 — 4× cheaper, still reads as edge
  for (int y = d; y < h - d; y += 2) {
    for (int x = d; x < w - d; x += 2) {
      int i = y * w + x;
      int gx = lum8(fxScratch[i - d]) - lum8(fxScratch[i + d]);
      int gy = lum8(fxScratch[i - d * w]) - lum8(fxScratch[i + d * w]);
      int e = constrain((int) (sqrt(gx * gx + gy * gy) * k), 0, 255);
      if (thr > 0 && e < thr) e = 0;
      edgeWrite(px, fxScratch, i, e, mix);
      if (x + 1 < w) edgeWrite(px, fxScratch, i + 1, e, mix);
      if (y + 1 < h) edgeWrite(px, fxScratch, i + w, e, mix);
      if (x + 1 < w && y + 1 < h) edgeWrite(px, fxScratch, i + w + 1, e, mix);
    }
  }
}

void edgeWrite(int[] px, int[] src, int i, int e, float mix) {
  if (mix >= 0.995f) {
    px[i] = 0xFF000000 | (e << 16) | (e << 8) | e;
    return;
  }
  int s = src[i];
  if (mix <= 0.005f) {
    px[i] = s;
    return;
  }
  float sr = (s >> 16) & 255, sg = (s >> 8) & 255, sb = s & 255;
  px[i] = packRgb(sr + (e - sr) * mix, sg + (e - sg) * mix, sb + (e - sb) * mix);
}

void embossBuffer(int[] px, int w, int h, float amt) {
  embossBuffer(px, w, h, amt, 225, 1);
}

void embossBuffer(int[] px, int w, int h, float amt, float angleDeg, float relief) {
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  float k = constrain(amt, 0, 1) * constrain(relief, 0, 2);
  int dx = -1, dy = -1;
  if (abs(angleDeg - 225) > 0.5f) {
    float rad = radians(angleDeg);
    dx = round(cos(rad));
    dy = round(sin(rad));
    if (dx == 0 && dy == 0) dx = 1;
  }
  for (int y = 1; y < h - 1; y += 2) {
    for (int x = 1; x < w - 1; x += 2) {
      int i = y * w + x;
      int a = lum8(fxScratch[i - dy * w - dx]);
      int b = lum8(fxScratch[i + dy * w + dx]);
      int v = constrain((int) (128 + (a - b) * k * 1.6f), 0, 255);
      int c = 0xFF000000 | (v << 16) | (v << 8) | v;
      px[i] = c;
      if (x + 1 < w) px[i + 1] = c;
      if (y + 1 < h) px[i + w] = c;
      if (x + 1 < w && y + 1 < h) px[i + w + 1] = c;
    }
  }
}

int[] fxSlitBuf(int target) {
  if (target == FX_TGT_LOOP) return fxSlitLoop;
  if (target == FX_TGT_OUT) return fxSlitOut;
  return fxSlitLive;
}

void fxSlitSetBuf(int target, int[] buf) {
  if (target == FX_TGT_LOOP) fxSlitLoop = buf;
  else if (target == FX_TGT_OUT) fxSlitOut = buf;
  else fxSlitLive = buf;
}

void fxClearSlit(int target) {
  if (target == FX_TGT_LOOP) fxSlitLoop = null;
  else if (target == FX_TGT_OUT) fxSlitOut = null;
  else fxSlitLive = null;
  fxSlitPhase[constrain(target, 0, 2)] = 0;
}

/**
 * Classic photographic slit-scan (not a push/scroll).
 * One or more thin slits walk across the frame; each column/row freezes
 * when a slit passes — movers shear, still subjects stay coherent.
 * amount = scan speed (0..2, high end is fast), amount2 = line count 1..5.
 * Orientation (Vert/Horz) is per-target via fxSlitOrient / Cmd.
 */
void slitScanBuffer(int[] px, int w, int h, float speedAmt, float linesAmt) {
  slitScanBuffer(px, w, h, speedAmt, linesAmt, 0);
}

void slitScanBuffer(int[] px, int w, int h, float speedAmt, float linesAmt, float widthAmt) {
  int n = w * h;
  if (px == null || px.length < n) return;
  int target = constrain(fxSlitApplyTarget, 0, 2);
  int[] buf = fxSlitBuf(target);
  if (buf == null || buf.length != n) {
    buf = new int[n];
    arrayCopy(px, buf);
    fxSlitSetBuf(target, buf);
    fxSlitPhase[target] = 0;
    arrayCopy(buf, px);
    return;
  }

  boolean vertSlit = fxSlitOrient[target] == 0;
  int span = vertSlit ? w : h;
  if (span < 2) {
    arrayCopy(buf, px);
    return;
  }
  int lines = constrain(round(linesAmt), 1, 5);
  // 0 → crawl (~0.3 px/f), 1 → brisk, 2 → very fast (~100 px/f).
  float t = constrain(speedAmt, 0, 2) / 2f;
  float speed = 0.3f + t * 12f + t * t * 90f;
  int slitW = speedAmt > 1.2f ? 2 : 1;
  if (widthAmt > 0.02f) slitW = constrain(slitW + round(widthAmt * 10), 1, 16);

  float prev = fxSlitPhase[target];
  if (prev < 0 || Float.isNaN(prev)) prev = 0;
  float next = prev + speed;

  // Full revolutions this frame → refresh whole buffer once.
  if (next - prev >= span) {
    arrayCopy(px, buf);
  } else {
    for (int L = 0; L < lines; L++) {
      float off = (span * L) / (float) lines;
      slitSweep(px, buf, w, h, prev + off, next + off, span, slitW, vertSlit);
    }
  }

  fxSlitPhase[target] = next;
  while (fxSlitPhase[target] >= span) fxSlitPhase[target] -= span;
  arrayCopy(buf, px);
}

/** Stamp every slit position from prev→next (with wrap). */
void slitSweep(int[] px, int[] buf, int w, int h, float prev, float next, int span, int slitW, boolean vertSlit) {
  if (span < 2) return;
  // Normalize into a forward interval; stamp modular positions.
  float p0 = prev;
  float p1 = next;
  while (p0 < 0) { p0 += span; p1 += span; }
  int i0 = (int) p0;
  int i1 = (int) p1;
  if (i1 < i0) return;
  // Cap runaway (shouldn't hit after full-rev short-circuit).
  if (i1 - i0 > span) i1 = i0 + span;
  for (int i = i0; i <= i1; i++) {
    int pos = i % span;
    if (pos < 0) pos += span;
    slitStamp(px, buf, w, h, pos, slitW, vertSlit);
  }
}

/** Write a thin slit from live `px` into frozen `buf` at position p. */
void slitStamp(int[] px, int[] buf, int w, int h, int p, int slitW, boolean vertSlit) {
  if (vertSlit) {
    for (int s = 0; s < slitW; s++) {
      int x = p + s;
      if (x < 0 || x >= w) continue;
      for (int y = 0; y < h; y++) {
        int i = y * w + x;
        buf[i] = px[i];
      }
    }
  } else {
    for (int s = 0; s < slitW; s++) {
      int y = p + s;
      if (y < 0 || y >= h) continue;
      int row = y * w;
      arrayCopy(px, row, buf, row, w);
    }
  }
}

/** Digital glitch: slice shifts + RGB split. amount=intensity, amount2=chaos. */
void glitchBuffer(int[] px, int w, int h, float amt, float chaos) {
  glitchBuffer(px, w, h, amt, chaos, 1, 1);
}

void glitchBuffer(int[] px, int w, int h, float amt, float chaos, float sizeN, float rgbN) {
  amt = constrain(amt, 0, 1);
  chaos = constrain(chaos, 0, 1);
  if (amt < 0.01f) return;
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);

  int tick = millis() / max(1, round(48 - chaos * 36));
  int slices = 3 + round(amt * (8 + chaos * 16));
  int sliceH = max(2, h / max(1, slices));
  if (abs(sizeN - 1) > 0.02f) sliceH = max(2, round(sliceH * constrain(sizeN, 0.25f, 3)));
  for (int s = 0; s < slices; s++) {
    int rnd = (tick * 1103515245 + s * 12345) & 0x7fffffff;
    float gate = (rnd % 1000) / 1000f;
    if (gate > amt * 0.9f + 0.1f) continue;
    int shift = round((((rnd >> 3) % 1000) / 1000f - 0.5f) * 2f * amt * w * (0.06f + chaos * 0.4f));
    int y0 = s * sliceH;
    int y1 = min(h, y0 + sliceH + ((rnd >> 7) % max(1, sliceH / 2)));
    for (int y = y0; y < y1; y++) {
      int row = y * w;
      for (int x = 0; x < w; x++) {
        int sx = x + shift;
        if (sx < 0) sx = 0;
        else if (sx >= w) sx = w - 1;
        px[row + x] = fxScratch[row + sx];
      }
    }
  }

  if (amt > 0.2f && rgbN > 0.02f) {
    int ch = max(1, round(amt * (2 + chaos * 14) * constrain(rgbN, 0, 2)));
    arrayCopy(px, fxScratch);
    for (int y = 0; y < h; y++) {
      int row = y * w;
      for (int x = 0; x < w; x++) {
        int i = row + x;
        int g = (fxScratch[i] >> 8) & 255;
        int rx = x + ch;
        if (rx >= w) rx = w - 1;
        int bx = x - ch;
        if (bx < 0) bx = 0;
        int r = (fxScratch[row + rx] >> 16) & 255;
        int b = fxScratch[row + bx] & 255;
        px[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
      }
    }
  }
}

int lum8(int c) {
  return (((c >> 16) & 255) * 299 + ((c >> 8) & 255) * 587 + (c & 255) * 114) / 1000;
}

void mirrorBuffer(int[] px, int w, int h, float strength, int mode) {
  mirrorBuffer(px, w, h, strength, mode, 0.5f, 0.5f, 0, 0);
}

/** Reflect a sample coordinate back into [0, span) instead of clamping (avoids edge smear). */
int mirrorReflectIndex(int v, int span) {
  if (span <= 1) return 0;
  int s = span - 1;
  // Fold into one period of a mirrored saw (period 2*s).
  int p = 2 * max(1, s);
  int t = v % p;
  if (t < 0) t += p;
  if (t > s) t = p - t;
  return t;
}

/**
 * Mirror across a fold through frame center.
 * mode 0 = H base (mirror +X), 1 = V base (mirror +Y).
 * axisDeg rotates the fold normal from that base (−90…90).
 * Soft is only applied on the axis-aligned fast path (angled uses a cheap seam fade).
 */
void mirrorAxisBuffer(int[] px, int w, int h, float strength, int mode, float axisDeg, float soft) {
  strength = constrain(strength, 0, 1);
  if (strength <= 0.001f) return;

  // Classic H/V at center — same cost as before Axis existed.
  if (abs(axisDeg) <= 0.5f) {
    if (mode == 0) mirrorBuffer(px, w, h, strength, 0, 0.5f, 0.5f, soft, 0);
    else mirrorBuffer(px, w, h, strength, 1, 0.5f, 0.5f, soft, 0);
    return;
  }

  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);

  float ang = radians((mode == 0 ? 0 : 90) + axisDeg);
  float nx = cos(ang);
  float ny = sin(ang);
  float cx = (w - 1) * 0.5f;
  float cy = (h - 1) * 0.5f;
  float dOrigin = -cx * nx - cy * ny;
  boolean full = strength >= 0.999f;
  int strQ = full ? 256 : constrain(round(strength * 256f), 1, 255);
  // Soft → narrow fade band at the fold (no per-pixel box blur).
  float softBand = soft > 0.02f ? soft * min(w, h) * 0.05f : 0;
  boolean seamFade = softBand > 0.5f;
  int wm = w - 1, hm = h - 1;

  for (int y = 0; y < h; y++) {
    float d0 = dOrigin + y * ny; // d at x = 0
    // Only walk the mirrored half of this row.
    int x0 = 0, x1 = w;
    if (abs(nx) < 1e-5f) {
      if (d0 < 0) continue;
    } else if (nx > 0) {
      x0 = max(0, (int) ceil(-d0 / nx));
    } else {
      x1 = min(w, (int) floor(-d0 / nx) + 1);
    }
    if (x0 >= x1) continue;

    float d = d0 + x0 * nx;
    int row = y * w;
    for (int x = x0; x < x1; x++) {
      float sx = x - 2f * d * nx;
      float sy = y - 2f * d * ny;
      int isx = (int) (sx + 0.5f);
      int isy = (int) (sy + 0.5f);
      if (isx < 0) isx = 0; else if (isx > wm) isx = wm;
      if (isy < 0) isy = 0; else if (isy > hm) isy = hm;
      int src = fxScratch[isy * w + isx];

      int outQ = strQ;
      if (seamFade && d < softBand) {
        outQ = constrain(round(strQ * (d / softBand)), 0, strQ);
      }

      if (outQ >= 256) {
        px[row + x] = src;
      } else if (outQ > 0) {
        int c = fxScratch[row + x];
        int inv = 256 - outQ;
        int r = ((((c >> 16) & 255) * inv) + (((src >> 16) & 255) * outQ)) >> 8;
        int g = ((((c >> 8) & 255) * inv) + (((src >> 8) & 255) * outQ)) >> 8;
        int b = (((c & 255) * inv) + ((src & 255) * outQ)) >> 8;
        px[row + x] = 0xFF000000 | (r << 16) | (g << 8) | b;
      }
      d += nx;
    }
  }
}

/**
 * Mirror fold. mode 0 = H (right←left), 1 = V (bottom←top), 2 = Quad.
 * soft = mild seam blur width (does NOT punch a hole at the fold — that was the glitch).
 * shift = slides the mirrored half along the fold axis.
 */
void mirrorBuffer(int[] px, int w, int h, float strength, int mode, float seamX, float seamY, float soft, float shift) {
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  strength = constrain(strength, 0, 1);
  if (strength <= 0.001f) return;

  float foldX = constrain(seamX, 0.05f, 0.95f) * (w - 1);
  float foldY = constrain(seamY, 0.05f, 0.95f) * (h - 1);
  int blurR = soft > 0.02f ? constrain(round(soft * min(w, h) * 0.04f), 1, 12) : 0;
  float sh = shift * (mode == 1 ? h : w) * 0.5f;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float sx = x;
      float sy = y;
      boolean foldH = false, foldV = false;

      if (mode == 0 || mode == 2) {
        if (x + 0.5f >= foldX) {
          sx = foldX - (x - foldX);
          foldH = true;
        }
        if (foldH && mode == 0) sx += sh; // shift only mirrored half
      }
      if (mode == 1 || mode == 2) {
        if (y + 0.5f >= foldY) {
          sy = foldY - (y - foldY);
          foldV = true;
        }
        if (foldV && mode == 1) sy += sh;
      }

      int isx = mirrorReflectIndex(round(sx), w);
      int isy = mirrorReflectIndex(round(sy), h);
      int src = fxScratch[isy * w + isx];

      // Soft = small box blur of the mirrored sample along the fold normal (seam AA).
      if (blurR > 0 && (foldH || foldV)) {
        int accR = 0, accG = 0, accB = 0, cnt = 0;
        int span = blurR;
        for (int k = -span; k <= span; k++) {
          int qx = isx, qy = isy;
          if (foldH && !foldV) qx = mirrorReflectIndex(isx + k, w);
          else if (foldV && !foldH) qy = mirrorReflectIndex(isy + k, h);
          else {
            qx = mirrorReflectIndex(isx + k, w);
            qy = mirrorReflectIndex(isy + k, h);
          }
          int s = fxScratch[qy * w + qx];
          accR += (s >> 16) & 255;
          accG += (s >> 8) & 255;
          accB += s & 255;
          cnt++;
        }
        if (cnt > 0) src = packRgb(accR / (float) cnt, accG / (float) cnt, accB / (float) cnt);
      }

      if (strength >= 0.999f) {
        px[y * w + x] = src;
      } else {
        int c = fxScratch[y * w + x];
        float r = ((c >> 16) & 255) + ((((src >> 16) & 255) - ((c >> 16) & 255)) * strength);
        float g = ((c >> 8) & 255) + ((((src >> 8) & 255) - ((c >> 8) & 255)) * strength);
        float b = (c & 255) + (((src & 255) - (c & 255)) * strength);
        px[y * w + x] = packRgb(r, g, b);
      }
    }
  }
}

void flipBuffer(int[] px, int w, int h, boolean horizontal, float strength) {
  flipBuffer(px, w, h, horizontal, strength, 0, 0, 1);
}

void flipBuffer(int[] px, int w, int h, boolean horizontal, float strength, float shift, float soft, float zoom) {
  boolean plain = abs(shift) < 0.001f && soft < 0.01f && abs(zoom - 1) < 0.02f;
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  strength = constrain(strength, 0, 1);
  float z = max(0.2f, zoom);
  float shx = shift * w;
  float shy = shift * h;
  float feather = soft * (horizontal ? w : h) * 0.45f;
  float cx = (w - 1) * 0.5f;
  float cy = (h - 1) * 0.5f;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int sx, sy;
      if (plain) {
        sx = horizontal ? (w - 1 - x) : x;
        sy = horizontal ? y : (h - 1 - y);
      } else if (horizontal) {
        float dx = (x - cx) / z;
        sx = constrain(round(cx - dx + shx), 0, w - 1);
        sy = y;
      } else {
        float dy = (y - cy) / z;
        sx = x;
        sy = constrain(round(cy - dy + shy), 0, h - 1);
      }
      int src = fxScratch[sy * w + sx];
      float m = strength;
      if (!plain && feather > 1) {
        float d = horizontal ? min(x, w - 1 - x) : min(y, h - 1 - y);
        if (d < feather) m *= d / feather;
      }
      if (m >= 0.999f) px[y * w + x] = src;
      else {
        int c = fxScratch[y * w + x];
        float r = ((c >> 16) & 255) + ((((src >> 16) & 255) - ((c >> 16) & 255)) * m);
        float g = ((c >> 8) & 255) + ((((src >> 8) & 255) - ((c >> 8) & 255)) * m);
        float b = (c & 255) + (((src & 255) - (c & 255)) * m);
        px[y * w + x] = packRgb(r, g, b);
      }
    }
  }
}

void rotateBuffer(int[] px, int w, int h, float deg) {
  rotateBuffer(px, w, h, deg, 1);
}

void rotateBuffer(int[] px, int w, int h, float deg, float zoom) {
  if (abs(zoom - 1) > 0.02f) {
    rotateBufferZoom(px, w, h, deg, zoom);
    return;
  }
  // Normalize; fast path for exact quarter turns on square frames.
  float a = deg % 360f;
  if (a < 0) a += 360f;
  if (abs(a) < 0.5f || abs(a - 360f) < 0.5f) return;
  if (w == h) {
    if (abs(a - 90f) < 0.5f) { rotate90Buffer(px, w, h, 1); return; }
    if (abs(a - 180f) < 0.5f) { flipBuffer(px, w, h, true, 1); flipBuffer(px, w, h, false, 1); return; }
    if (abs(a - 270f) < 0.5f) { rotate90Buffer(px, w, h, 3); return; }
  }
  if (abs(a - 180f) < 0.5f) { flipBuffer(px, w, h, true, 1); flipBuffer(px, w, h, false, 1); return; }

  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  float rad = radians(a);
  float ca = cos(rad), sa = sin(rad);
  float cx = (w - 1) * 0.5f;
  float cy = (h - 1) * 0.5f;
  // step-2 on large frames
  int step = (w * h > 640 * 480) ? 2 : 1;
  for (int y = 0; y < h; y += step) {
    for (int x = 0; x < w; x += step) {
      float dx = x - cx;
      float dy = y - cy;
      // inverse rotate: sample where this dest came from
      float sx = cx + dx * ca + dy * sa;
      float sy = cy - dx * sa + dy * ca;
      int c;
      if (sx < 0 || sy < 0 || sx > w - 1 || sy > h - 1) c = 0xFF000000;
      else c = sampleNearest(fxScratch, w, h, sx, sy);
      px[y * w + x] = c;
      if (step > 1) {
        if (x + 1 < w) px[y * w + x + 1] = c;
        if (y + 1 < h) px[(y + 1) * w + x] = c;
        if (x + 1 < w && y + 1 < h) px[(y + 1) * w + x + 1] = c;
      }
    }
  }
}

void rotateBufferZoom(int[] px, int w, int h, float deg, float zoom) {
  float a = deg % 360f;
  if (a < 0) a += 360f;
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  float rad = radians(a);
  float ca = cos(rad), sa = sin(rad);
  float cx = (w - 1) * 0.5f;
  float cy = (h - 1) * 0.5f;
  float z = max(0.2f, zoom);
  int step = (w * h > 640 * 480) ? 2 : 1;
  for (int y = 0; y < h; y += step) {
    for (int x = 0; x < w; x += step) {
      float dx = (x - cx) / z;
      float dy = (y - cy) / z;
      float sx = cx + dx * ca + dy * sa;
      float sy = cy - dx * sa + dy * ca;
      int c = (sx < 0 || sy < 0 || sx > w - 1 || sy > h - 1) ? 0xFF000000 : sampleNearest(fxScratch, w, h, sx, sy);
      px[y * w + x] = c;
      if (step > 1) {
        if (x + 1 < w) px[y * w + x + 1] = c;
        if (y + 1 < h) px[(y + 1) * w + x] = c;
        if (x + 1 < w && y + 1 < h) px[(y + 1) * w + x + 1] = c;
      }
    }
  }
}

void rotate90Buffer(int[] px, int w, int h, int turns) {
  if (w != h) return; // caller must use continuous path
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  turns = ((turns % 4) + 4) % 4;
  if (turns == 0) return;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int sx, sy;
      if (turns == 1) { sx = y; sy = w - 1 - x; }
      else if (turns == 2) { sx = w - 1 - x; sy = h - 1 - y; }
      else { sx = h - 1 - y; sy = x; }
      px[y * w + x] = fxScratch[sy * w + sx];
    }
  }
}

/**
 * Endless wrap scroll.
 * dir: 0=L 1=R 2=U 3=D
 * push=true → eased periodic shove instead of constant crawl.
 */
void slideBuffer(int[] px, int w, int h, float speedN, int dir, boolean push) {
  slideBuffer(px, w, h, speedN, dir, push, 0);
}

void slideBuffer(int[] px, int w, int h, float speedN, int dir, boolean push, float soft) {
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  float speed = constrain(speedN, 0, 1);
  if (speed < 0.001f) return;
  float span = (dir <= 1) ? w : h;
  float off;
  if (push) {
    // One full push per cycle; ease in/out so it reads as a shove.
    float hz = 0.15f + speed * 1.6f;
    float phase = fract(millis() * 0.001f * hz);
    float eased = phase * phase * (3f - 2f * phase);
    off = eased * span;
  } else {
    float pxPerSec = (0.05f + speed * 0.95f) * span * 0.85f;
    off = (millis() * 0.001f * pxPerSec);
  }
  // Direction sign
  if (dir == 0 || dir == 2) off = -off; // left / up
  int ioff = floor(off);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int sx = x, sy = y;
      if (dir <= 1) {
        sx = x - ioff;
        sx %= w;
        if (sx < 0) sx += w;
      } else {
        sy = y - ioff;
        sy %= h;
        if (sy < 0) sy += h;
      }
      if (soft > 0.02f) {
        int blur = max(1, round(soft * (dir <= 1 ? w : h) * 0.04f));
        int sx2 = sx, sy2 = sy;
        if (dir <= 1) {
          sx2 = sx + (ioff >= 0 ? blur : -blur);
          sx2 %= w;
          if (sx2 < 0) sx2 += w;
        } else {
          sy2 = sy + (ioff >= 0 ? blur : -blur);
          sy2 %= h;
          if (sy2 < 0) sy2 += h;
        }
        int a = fxScratch[sy * w + sx];
        int b = fxScratch[sy2 * w + sx2];
        float m = constrain(soft, 0, 1) * 0.65f;
        px[y * w + x] = packRgb(
          ((a >> 16) & 255) + ((((b >> 16) & 255) - ((a >> 16) & 255)) * m),
          ((a >> 8) & 255) + ((((b >> 8) & 255) - ((a >> 8) & 255)) * m),
          (a & 255) + (((b & 255) - (a & 255)) * m));
      } else {
        px[y * w + x] = fxScratch[sy * w + sx];
      }
    }
  }
}

/** Run heavy warp FX at half-res then nearest-up — keeps 1080p realtime. */
void fxWarpHalf(int[] px, int w, int h, int kind, float a, float b, float c, float d) {
  int hw = max(2, w / 2);
  int hh = max(2, h / 2);
  int sn = hw * hh;
  if (fxScratch == null || fxScratch.length < w * h) fxScratch = new int[w * h];
  if (fxScratch2 == null || fxScratch2.length < sn) fxScratch2 = new int[sn];
  // downscale
  for (int y = 0; y < hh; y++) {
    int sy = min(h - 1, y * 2);
    for (int x = 0; x < hw; x++) {
      int sx = min(w - 1, x * 2);
      fxScratch2[y * hw + x] = px[sy * w + sx];
    }
  }
  arrayCopy(fxScratch2, 0, fxScratch, 0, sn);
  if (kind == FX_KALEIDO) kaleidoBufferFull(fxScratch2, hw, hh, max(2, round(a)), b, c, fxScratch);
  else if (kind == FX_TWIRL) twirlBufferFull(fxScratch2, hw, hh, a, b, c, d, fxScratch);
  else if (kind == FX_RIPPLE) rippleBufferFull(fxScratch2, hw, hh, a, b, c, fxScratch);
  else if (kind == FX_BULGE) bulgeBufferFull(fxScratch2, hw, hh, a, b, c, d, fxScratch);
  // upscale nearest
  for (int y = 0; y < h; y++) {
    int sy = min(hh - 1, y / 2);
    for (int x = 0; x < w; x++) {
      int sx = min(hw - 1, x / 2);
      px[y * w + x] = fxScratch2[sy * hw + sx];
    }
  }
}

void kaleidoBuffer(int[] px, int w, int h, int segments, float angleDeg, float zoom) {
  if (w * h > 640 * 480) {
    fxWarpHalf(px, w, h, FX_KALEIDO, segments, angleDeg, zoom, 0);
    return;
  }
  if (fxScratch == null || fxScratch.length < px.length) fxScratch = new int[px.length];
  arrayCopy(px, fxScratch);
  kaleidoBufferFull(px, w, h, segments, angleDeg, zoom, fxScratch);
}

void kaleidoBufferFull(int[] px, int w, int h, int segments, float angleDeg, float zoom, int[] src) {
  float cx = (w - 1) * 0.5f;
  float cy = (h - 1) * 0.5f;
  float wedge = TWO_PI / max(2, segments);
  float rot = radians(angleDeg);
  float z = max(0.05f, zoom);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float dx = x - cx;
      float dy = y - cy;
      float ang = atan2(dy, dx) - rot;
      float rad = sqrt(dx * dx + dy * dy) / z;
      ang = ang - floor(ang / wedge) * wedge;
      if (ang > wedge * 0.5f) ang = wedge - ang;
      px[y * w + x] = sampleNearest(src, w, h, cx + cos(ang) * rad, cy + sin(ang) * rad);
    }
  }
}

void twirlBuffer(int[] px, int w, int h, float strength, float radiusN, float cxN, float cyN) {
  if (w * h > 640 * 480) {
    fxWarpHalf(px, w, h, FX_TWIRL, strength, radiusN, cxN, cyN);
    return;
  }
  if (fxScratch == null || fxScratch.length < px.length) fxScratch = new int[px.length];
  arrayCopy(px, fxScratch);
  twirlBufferFull(px, w, h, strength, radiusN, cxN, cyN, fxScratch);
}

void twirlBufferFull(int[] px, int w, int h, float strength, float radiusN, float cxN, float cyN, int[] src) {
  float cx = (w - 1) * constrain(cxN, 0, 1);
  float cy = (h - 1) * constrain(cyN, 0, 1);
  float maxR = min((w - 1) * 0.5f, (h - 1) * 0.5f) * radiusN;
  float invR = maxR > 1 ? 1f / maxR : 1;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float dx = x - cx;
      float dy = y - cy;
      float rad = sqrt(dx * dx + dy * dy);
      if (rad >= maxR) {
        px[y * w + x] = src[y * w + x];
        continue;
      }
      float t = 1 - rad * invR;
      float a = strength * t * t;
      float ca = cos(a), sa = sin(a);
      px[y * w + x] = sampleNearest(src, w, h, cx + dx * ca - dy * sa, cy + dx * sa + dy * ca);
    }
  }
}

void rippleBuffer(int[] px, int w, int h, float amp, float freq, float speed) {
  if (w * h > 640 * 480) {
    fxWarpHalf(px, w, h, FX_RIPPLE, amp, freq, speed, 0);
    return;
  }
  if (fxScratch == null || fxScratch.length < px.length) fxScratch = new int[px.length];
  arrayCopy(px, fxScratch);
  rippleBufferFull(px, w, h, amp, freq, speed, fxScratch);
}

void rippleBufferFull(int[] px, int w, int h, float amp, float freq, float speed, int[] src) {
  float cx = (w - 1) * 0.5f;
  float cy = (h - 1) * 0.5f;
  float t = millis() * 0.004f * constrain(speed, 0, 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float dx = x - cx;
      float dy = y - cy;
      float rad = sqrt(dx * dx + dy * dy);
      float off = sin(rad * 0.04f * freq - t) * amp;
      float sx = x + (rad > 1 ? dx / rad * off : 0);
      float sy = y + (rad > 1 ? dy / rad * off : 0);
      px[y * w + x] = sampleNearest(src, w, h, sx, sy);
    }
  }
}

/** Fisheye bulge (+) / pinch (−) around a center. */
void bulgeBuffer(int[] px, int w, int h, float strength, float radiusN, float cxN, float cyN) {
  if (w * h > 640 * 480) {
    fxWarpHalf(px, w, h, FX_BULGE, strength, radiusN, cxN, cyN);
    return;
  }
  if (fxScratch == null || fxScratch.length < px.length) fxScratch = new int[px.length];
  arrayCopy(px, fxScratch);
  bulgeBufferFull(px, w, h, strength, radiusN, cxN, cyN, fxScratch);
}

void bulgeBufferFull(int[] px, int w, int h, float strength, float radiusN, float cxN, float cyN, int[] src) {
  float cx = (w - 1) * constrain(cxN, 0, 1);
  float cy = (h - 1) * constrain(cyN, 0, 1);
  float maxR = min(w - 1, h - 1) * 0.5f * constrain(radiusN, 0.08f, 1.4f);
  if (maxR < 2) {
    arrayCopy(src, px);
    return;
  }
  float s = constrain(strength, -1, 1);
  // power < 1 → bulge out, > 1 → pinch in
  float power = s >= 0 ? 1f / (1f + s * 3.2f) : 1f - s * 3.2f;
  float invR = 1f / maxR;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float dx = x - cx;
      float dy = y - cy;
      float rad = sqrt(dx * dx + dy * dy);
      if (rad >= maxR || rad < 0.001f) {
        px[y * w + x] = src[y * w + x];
        continue;
      }
      float t = rad * invR;
      // Soft edge so the seam doesn't ring.
      float edge = t * t * (3f - 2f * t);
      float nt = pow(t, power);
      float warped = lerp(t, nt, 0.65f + 0.35f * abs(s));
      float f = lerp(1f, warped / t, edge);
      px[y * w + x] = sampleNearest(src, w, h, cx + dx * f, cy + dy * f);
    }
  }
}

void slicesBuffer(int[] px, int w, int h, int slices, float shiftN, float angleDeg) {
  int n = px.length;
  if (fxScratch == null || fxScratch.length != n) fxScratch = new int[n];
  arrayCopy(px, fxScratch);
  float shift = shiftN * h * 0.45f;
  if (abs(angleDeg) < 0.5f) {
    int sw = max(1, w / max(2, slices));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int col = x / sw;
        float sy = y + ((col & 1) == 0 ? -shift : shift);
        px[y * w + x] = sampleNearest(fxScratch, w, h, x, sy);
      }
    }
    return;
  }
  float ang = radians(constrain(angleDeg, 0, 90));
  float nx = cos(ang), ny = sin(ang);
  float span = abs(nx) * w + abs(ny) * h;
  int sw = max(1, round(span / max(2, slices)));
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int col = (int) ((x * nx + y * ny) / sw);
      if (col < 0) col = -col;
      float sh = (col & 1) == 0 ? -shift : shift;
      px[y * w + x] = sampleNearest(fxScratch, w, h, x - ny * sh, y + nx * sh);
    }
  }
}

void trailBuffer(int[] px, int[] trail, float decay) {
  echoBuffer(px, trail, decay, 1);
}

void strobeBuffer(int[] px, float rate, float duty) {
  strobeBuffer(px, rate, duty, 1, 0);
}

void strobeBuffer(int[] px, float rate, float duty, float depth, float soft) {
  float speed = 2 + constrain(rate, 0, 1) * 14f;
  float phase = fract(millis() * 0.001f * speed);
  float d = constrain(duty, 0.05f, 0.95f);
  if (soft < 0.01f && depth > 0.995f) {
    if (phase > d) java.util.Arrays.fill(px, 0xFF000000);
    return;
  }
  float edge = max(0.001f, soft * 0.25f);
  float dark = phase <= d ? 0 : (phase >= d + edge ? depth : depth * (phase - d) / edge);
  dark = constrain(dark, 0, 1);
  if (dark <= 0.001f) return;
  float keep = 1 - dark;
  for (int i = 0; i < px.length; i++) {
    int c = px[i];
    px[i] = packRgb(((c >> 16) & 255) * keep, ((c >> 8) & 255) * keep, (c & 255) * keep);
  }
}

float fract(float v) {
  return v - floor(v);
}

int sampleNearest(int[] src, int w, int h, float x, float y) {
  int ix = constrain(round(x), 0, w - 1);
  int iy = constrain(round(y), 0, h - 1);
  return src[iy * w + ix];
}

/**
 * After camera grade: apply Live FX + Live curve onto livePixels / liveFxImg.
 * While the frame stack is playing it owns this same bus (live picture is hidden).
 */
void prepareLiveFx() {
  // Idempotent within a frame — stopCapture may call again after draw.
  if (liveFxReady && liveFxFrame == frameCount) return;
  liveFxReady = false;
  liveFxFrame = frameCount;
  boolean fx = fxAffectLive && fxStackActive(fxLive);
  boolean curve = liveFxCurvesOn();
  if (!fx && !curve) return;

  // Frame-stack play (Stoptrick + Draw) → same Live FX bus as the camera.
  if (stopPlaying && hasStop()) {
    int[] base = stopFramedPixelsRaw();
    if (base == null) return;
    ensureStopImg();
    if (stopScratch == null || stopScratch.length != base.length) {
      stopScratch = new int[base.length];
    }
    arrayCopy(base, stopScratch);
    // Draw ink is sparse ARGB — flatten over black so FX see an opaque plate like Live.
    if (stopHeadIsInkPlate()) stopFlattenInkOpaque(stopScratch);
    if (fx) applyFxStack(fxLive, stopScratch, capW, capH, FX_TGT_LIVE);
    if (curve) applyLiveFxCurves(stopScratch);
    if (liveFxImg == null || liveFxImg.width != capW || liveFxImg.height != capH) {
      liveFxImg = createImage(capW, capH, ARGB);
    }
    liveFxImg.loadPixels();
    arrayCopy(stopScratch, liveFxImg.pixels);
    liveFxImg.updatePixels();
    liveFxReady = true;
    return;
  }

  if (!liveValid || livePixels == null) return;
  if (gpuGradeActive && gradedView != null) {
    ensureRecordPixels();
  }
  if (fx) applyFxStack(fxLive, livePixels, capW, capH, FX_TGT_LIVE);
  if (curve) applyLiveFxCurves(livePixels);

  if (liveFxImg == null || liveFxImg.width != capW || liveFxImg.height != capH) {
    liveFxImg = createImage(capW, capH, ARGB);
  }
  liveFxImg.loadPixels();
  arrayCopy(livePixels, liveFxImg.pixels);
  liveFxImg.updatePixels();
  liveFxReady = true;
}

PImage liveFxSource() {
  PImage faded = inputLiveSource();
  if (faded != null) return faded;
  if (liveFxReady && liveFxImg != null) return liveFxImg;
  return gradedView;
}

void applyFxToOutputPixels(int[] px) {
  if (px == null) return;
  applyFxStack(fxOut, px, capW, capH, FX_TGT_OUT);
}

JSONArray saveFxStack(ArrayList<FxUnit> stack) {
  JSONArray arr = new JSONArray();
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    JSONObject o = new JSONObject();
    o.setInt("type", u.type);
    o.setBoolean("on", u.on);
    o.setFloat("amount", u.amount);
    o.setFloat("amount2", u.amount2);
    o.setFloat("amount3", u.amount3);
    o.setFloat("amount4", u.amount4);
    o.setBoolean("p4", true);
    if (u.type == FX_EDGE || u.type == FX_HUE || u.type == FX_SLIT) o.setBoolean("a2", true);
    if (u.type == FX_FLIP) o.setBoolean("flipMode", true);
    arr.setJSONObject(i, o);
  }
  return arr;
}

void loadFxStack(JSONArray arr, ArrayList<FxUnit> stack) {
  stack.clear();
  if (arr == null) return;
  for (int i = 0; i < arr.size(); i++) {
    JSONObject o = arr.getJSONObject(i);
    if (o == null) continue;
    int type = constrain(o.getInt("type", 0), 0, FX_COUNT - 1);
    FxUnit u = new FxUnit(type);
    u.on = o.getBoolean("on", true);
    u.amount = o.getFloat("amount", fxDefaultAmount(type));
    u.amount2 = o.getFloat("amount2", fxDefaultAmount2(type));
    u.amount3 = o.getFloat("amount3", fxDefaultAmount3(type));
    u.amount4 = o.getFloat("amount4", fxDefaultAmount4(type));
    // Edge Mix / Hue Sat are new second params — older saves wrote unused amount2=0.
    if (type == FX_EDGE && !o.getBoolean("a2", false)) u.amount2 = fxDefaultAmount2(type);
    if (type == FX_HUE && !o.getBoolean("a2", false)) u.amount2 = fxDefaultAmount2(type);
    // Slider 2 used to be unused on many FX and was stored as 0.
    if (!o.getBoolean("p4", false) && !fxLegacySecond(type)) u.amount2 = fxDefaultAmount2(type);
    // Slit: amount2 was Vert/Horz (0/1); now it's line count 1..5.
    if (type == FX_SLIT && !o.getBoolean("a2", false)) {
      int oldOrient = constrain(round(u.amount2), 0, 1);
      u.amount2 = 1;
      // Orient applied after stacks load (same for all targets until Cmd toggles).
      fxSlitOrient[0] = fxSlitOrient[1] = fxSlitOrient[2] = oldOrient;
    } else if (type == FX_SLIT) {
      u.amount2 = constrain(round(u.amount2), 1, 5);
    }
    // Flip: amount2 was Shift; now Mode 0=H 1=V 2=Both.
    if (type == FX_FLIP && !o.getBoolean("flipMode", false)) {
      u.amount2 = 0;
    } else if (type == FX_FLIP) {
      u.amount2 = constrain(round(u.amount2), 0, 2);
    }
    u.snapLive();
    stack.add(u);
  }
}

void saveFxStacks(JSONObject o) {
  saveFxRack(o);
  o.setJSONArray("fxLive", saveFxStack(fxLive));
  o.setJSONArray("fxLoop", saveFxStack(fxLoop));
  o.setJSONArray("fxOut", saveFxStack(fxOut));
  o.setInt("fxTarget", fxTarget);
  o.setBoolean("fxAffectLive", fxAffectLive);
  o.setBoolean("fxAffectLoop", fxAffectLoop);
  o.setInt("slitOrientLive", fxSlitOrient[0]);
  o.setInt("slitOrientLoop", fxSlitOrient[1]);
  o.setInt("slitOrientOut", fxSlitOrient[2]);
}

void loadFxStacks(JSONObject o) {
  loadFxRack(o);
  fxKeyMapFrom = -1;
  fxMapIgnore = 0;
  boolean hasStacks = o.hasKey("fxLive") || o.hasKey("fxLoop") || o.hasKey("fxOut");
  if (hasStacks) {
    loadFxStack(o.getJSONArray("fxLive"), fxLive);
    loadFxStack(o.getJSONArray("fxLoop"), fxLoop);
    loadFxStack(o.getJSONArray("fxOut"), fxOut);
    fxTarget = constrain(o.getInt("fxTarget", FX_TGT_LIVE), FX_TGT_LIVE, FX_TGT_OUT);
  } else {
    migrateFlatFxToLive();
  }
  fxAffectLive = o.getBoolean("fxAffectLive", true);
  fxAffectLoop = o.getBoolean("fxAffectLoop", false);
  // Prefer explicit orient saves; migration in loadFxStack may have set defaults.
  if (o.hasKey("slitOrientLive")) fxSlitOrient[0] = constrain(o.getInt("slitOrientLive", 0), 0, 1);
  if (o.hasKey("slitOrientLoop")) fxSlitOrient[1] = constrain(o.getInt("slitOrientLoop", 0), 0, 1);
  if (o.hasKey("slitOrientOut")) fxSlitOrient[2] = constrain(o.getInt("slitOrientOut", 0), 0, 1);
  // Normalize amounts fade for loaded units, then pin to fixed rack.
  for (int i = 0; i < fxLive.size(); i++) {
    FxUnit u = fxLive.get(i);
    if (u != null) u.fade = u.on ? 1 : 0;
  }
  for (int i = 0; i < fxLoop.size(); i++) {
    FxUnit u = fxLoop.get(i);
    if (u != null) u.fade = u.on ? 1 : 0;
  }
  for (int i = 0; i < fxOut.size(); i++) {
    FxUnit u = fxOut.get(i);
    if (u != null) u.fade = u.on ? 1 : 0;
  }
  ensureAllFxRacks();
  syncFlatFxFromLive();
}

String fxDirLabel(int dir) {
  dir = constrain(dir, 0, 3);
  if (dir == 0) return "←";
  if (dir == 1) return "→";
  if (dir == 2) return "↑";
  return "↓";
}

String fxAmountLabel(FxUnit u) {
  if (u.type == FX_HUE) {
    String sat = u.amount2 < 0.02f ? "B&W" : round(u.amount2 * 100) + "%";
    return round(u.amount) + "° · " + sat;
  }
  if (u.type == FX_COLORIZE || u.type == FX_ROTATE) return round(u.amount) + "°";
  if (u.type == FX_POST) return u.amount < 2 ? "Off" : str(round(u.amount));
  if (u.type == FX_THR || u.type == FX_SOLAR) return round(u.amount * 100) + "%";
  if (u.type == FX_PIX) return round(u.amount) + " px";
  if (u.type == FX_KALEIDO) return round(u.amount) + " seg";
  if (u.type == FX_SLICES) return round(u.amount) + "×";
  if (u.type == FX_MIRROR) {
    return constrain(round(u.amount2), 0, 1) == 0 ? "H" : "V";
  }
  if (u.type == FX_QUAD) return "Quad";
  if (u.type == FX_SLIDE || u.type == FX_PUSH) return fxDirLabel(round(u.amount2)) + " " + round(u.amount * 100) + "%";
  if (u.type == FX_ROT180) return "180°";
  if (u.type == FX_FLIP || u.type == FX_FLIP_V) {
    int m = u.type == FX_FLIP_V ? 1 : constrain(round(u.amount2), 0, 2);
    return m == 0 ? "H" : m == 1 ? "V" : "HV";
  }
  if (u.type == FX_MIRROR_H || u.type == FX_MIRROR_V || u.type == FX_QUAD)
    return round(u.amount * 100) + "%";
  if (u.type == FX_INV) return u.on ? "On" : "Off";
  if (u.type == FX_SLIT) return round(constrain(u.amount, 0, 2) / 2f * 100) + "%";
  if (u.type == FX_BULGE) {
    if (abs(u.amount) < 0.03f) return "Flat";
    return (u.amount > 0 ? "B " : "P ") + round(abs(u.amount) * 100) + "%";
  }
  if (u.type == FX_FB || u.type == FX_TRAIL || u.type == FX_STROBE || u.type == FX_GLITCH
    || u.type == FX_SAT || u.type == FX_CONTRAST || u.type == FX_BLUR
    || u.type == FX_EDGE || u.type == FX_EMBOSS || u.type == FX_TWIRL
    || u.type == FX_RIPPLE || u.type == FX_RGBDELAY) return round(u.amount * 100) + "%";
  return round(u.amount * 100) + "%";
}

String fxAmount2Label(FxUnit u) {
  return fxParamLabel(u, 1);
}

String fxParamName(int type, int param) {
  if (param == 0) {
    if (type == FX_HUE || type == FX_COLORIZE) return "Hue";
    if (type == FX_ROTATE) return "Angle";
    if (type == FX_ROT180 || type == FX_INV) return "Mix";
    if (type == FX_MIRROR || type == FX_MIRROR_H || type == FX_MIRROR_V || type == FX_QUAD
      || type == FX_FLIP || type == FX_FLIP_V) return "Mix";
    if (type == FX_SLIDE || type == FX_PUSH || type == FX_SLIT) return "Speed";
    if (type == FX_KALEIDO) return "Segments";
    if (type == FX_SLICES) return "Slices";
    if (type == FX_STROBE) return "Rate";
    if (type == FX_TRAIL) return "Decay";
    if (type == FX_FB) return "Amount";
    if (type == FX_RGBDELAY) return "Delay";
    if (type == FX_PIX) return "Size";
    if (type == FX_POST) return "Levels";
    if (type == FX_SAT) return "Sat";
    if (type == FX_THR || type == FX_SOLAR) return "Level";
    if (type == FX_BULGE) return "Strength";
    return "Amount";
  }
  if (param == 1) {
    if (type == FX_HUE) return "Sat";
    if (type == FX_SAT || type == FX_CONTRAST || type == FX_POST || type == FX_PIX || type == FX_BLUR || type == FX_EMBOSS) return "Mix";
    if (type == FX_INV) return "Red";
    if (type == FX_THR || type == FX_SOLAR) return "Soft";
    if (type == FX_COLORIZE || type == FX_EDGE) return "Mix";
    if (type == FX_MIRROR || type == FX_FLIP) return "Mode";
    if (type == FX_MIRROR_H || type == FX_MIRROR_V) return "Seam";
    if (type == FX_QUAD) return "Center X";
    if (type == FX_KALEIDO) return "Angle";
    if (type == FX_TWIRL || type == FX_BULGE) return "Radius";
    if (type == FX_RIPPLE) return "Freq";
    if (type == FX_SLICES) return "Shift";
    if (type == FX_FB) return "Style";
    if (type == FX_TRAIL) return "Threshold";
    if (type == FX_RGBDELAY) return "Spread";
    if (type == FX_STROBE) return "Duty";
    if (type == FX_FLIP_V) return "Shift";
    if (type == FX_ROTATE) return "Spin";
    if (type == FX_SLIDE || type == FX_PUSH) return "Dir";
    if (type == FX_ROT180) return "Angle";
    if (type == FX_GLITCH) return "Chaos";
    if (type == FX_SLIT) return "Lines";
    return "Mix";
  }
  if (param == 2) {
    if (type == FX_HUE || type == FX_THR || type == FX_SOLAR || type == FX_SLIDE || type == FX_PUSH) return "Mix";
    if (type == FX_SAT || type == FX_POST) return type == FX_SAT ? "Contrast" : "Sat";
    if (type == FX_CONTRAST) return "Pivot";
    if (type == FX_INV) return "Green";
    if (type == FX_COLORIZE) return "Sat";
    if (type == FX_PIX) return "Width";
    if (type == FX_BLUR) return "Horiz";
    if (type == FX_EDGE) return "Threshold";
    if (type == FX_EMBOSS) return "Angle";
    if (type == FX_MIRROR) return "Axis";
    if (type == FX_MIRROR_H || type == FX_MIRROR_V || type == FX_FLIP || type == FX_FLIP_V) return "Soft";
    if (type == FX_STROBE) return "Depth";
    if (type == FX_QUAD) return "Center Y";
    if (type == FX_KALEIDO || type == FX_ROTATE || type == FX_ROT180) return "Zoom";
    if (type == FX_TWIRL || type == FX_BULGE) return "Center X";
    if (type == FX_RIPPLE) return "Speed";
    if (type == FX_ROT180) return "Spin";
    if (type == FX_SLICES) return "Angle";
    if (type == FX_FB) return "Zoom";
    if (type == FX_TRAIL) return "Sat";
    if (type == FX_RGBDELAY) return "Mix";
    if (type == FX_GLITCH) return "Size";
    if (type == FX_SLIT) return "Width";
    return "Mix";
  }
  if (type == FX_RGBDELAY) return "Order";
  if (type == FX_HUE || type == FX_COLORIZE) return "Light";
  if (type == FX_SAT) return "Hue";
  if (type == FX_CONTRAST || type == FX_POST) return type == FX_CONTRAST ? "Bright" : "Contrast";
  if (type == FX_THR) return "Gain";
  if (type == FX_INV) return "Blue";
  if (type == FX_SOLAR || type == FX_TRAIL) return type == FX_SOLAR ? "Sat" : "Mix";
  if (type == FX_PIX) return "Height";
  if (type == FX_BLUR) return "Vert";
  if (type == FX_EDGE) return "Thick";
  if (type == FX_EMBOSS) return "Relief";
  if (type == FX_MIRROR || type == FX_QUAD || type == FX_SLIDE || type == FX_PUSH || type == FX_STROBE) return "Soft";
  if (type == FX_MIRROR_H || type == FX_MIRROR_V) return "Shift";
  if (type == FX_KALEIDO || type == FX_RIPPLE || type == FX_SLICES || type == FX_ROTATE || type == FX_SLIT) return "Mix";
  if (type == FX_TWIRL || type == FX_BULGE) return "Center Y";
  if (type == FX_FB) return "Rotate";
  if (type == FX_FLIP || type == FX_FLIP_V) return "Zoom";
  if (type == FX_ROT180) return "Spin";
  if (type == FX_GLITCH) return "RGB";
  if (type == FX_QUAD) return "Soft";
  return "Level";
}

void fxParamRange(int type, int param, float[] outMinMax) {
  outMinMax[0] = 0;
  outMinMax[1] = 1;
  if (param == 0) {
    if (type == FX_SLIT) { outMinMax[1] = 2; return; }
    if (type == FX_HUE || type == FX_COLORIZE || type == FX_ROTATE) { outMinMax[1] = 360; return; }
    if (type == FX_POST) { outMinMax[1] = 8; return; }
    if (type == FX_PIX) { outMinMax[0] = 1; outMinMax[1] = 48; return; }
    if (type == FX_KALEIDO) { outMinMax[0] = 2; outMinMax[1] = 16; return; }
    if (type == FX_SLICES) { outMinMax[0] = 2; outMinMax[1] = 24; return; }
    if (type == FX_SAT) { outMinMax[1] = 1.5f; return; }
    if (type == FX_BLUR) { outMinMax[1] = 5; return; }
    if (type == FX_BULGE) { outMinMax[0] = -1; outMinMax[1] = 1; return; }
    return;
  }
  if (param == 1) {
    if (type == FX_HUE) { outMinMax[1] = 1.5f; return; }
    if (type == FX_SLIT) { outMinMax[0] = 1; outMinMax[1] = 5; return; }
    if (type == FX_MIRROR) { outMinMax[1] = 1; return; }
    if (type == FX_FLIP) { outMinMax[1] = 2; return; }
    if (type == FX_ROTATE) { outMinMax[0] = -1; outMinMax[1] = 1; return; }
    if (type == FX_BULGE) { outMinMax[0] = 0.08f; outMinMax[1] = 1.4f; return; }
    if (type == FX_SLIDE || type == FX_PUSH) { outMinMax[1] = 3; return; }
    if (type == FX_KALEIDO) { outMinMax[1] = 360; return; }
    if (type == FX_ROT180) { outMinMax[0] = -180; outMinMax[1] = 180; return; }
    if (type == FX_MIRROR_H || type == FX_MIRROR_V || type == FX_QUAD) { outMinMax[0] = -0.45f; outMinMax[1] = 0.45f; return; }
    if (type == FX_FLIP_V) { outMinMax[0] = -1; outMinMax[1] = 1; return; }
    return;
  }
  if (param == 2) {
    if (type == FX_CONTRAST) { outMinMax[1] = 1; return; } // pivot 0..1, default 0.5
    if (type == FX_EMBOSS || type == FX_KALEIDO) { outMinMax[0] = type == FX_EMBOSS ? 0 : 0.25f; outMinMax[1] = type == FX_EMBOSS ? 360 : 4; return; }
    if (type == FX_PIX) { outMinMax[0] = 0.25f; outMinMax[1] = 4; return; }
    if (type == FX_BLUR || type == FX_GLITCH) { outMinMax[0] = type == FX_BLUR ? 0 : 0.25f; outMinMax[1] = type == FX_BLUR ? 2 : 3; return; }
    if (type == FX_MIRROR) { outMinMax[0] = -90; outMinMax[1] = 90; return; }
    if (type == FX_TWIRL || type == FX_BULGE) { outMinMax[1] = 1; return; }
    if (type == FX_RIPPLE) { outMinMax[1] = 3; return; }
    if (type == FX_ROT180) { outMinMax[0] = 0.25f; outMinMax[1] = 4; return; }
    if (type == FX_SLICES) { outMinMax[1] = 90; return; }
    if (type == FX_FB) { outMinMax[0] = -1; outMinMax[1] = 1; return; }
    if (type == FX_ROTATE) { outMinMax[0] = 0.25f; outMinMax[1] = 4; return; }
    if (type == FX_QUAD) { outMinMax[0] = -0.45f; outMinMax[1] = 0.45f; return; }
    if (type == FX_POST || type == FX_COLORIZE || type == FX_TRAIL) { outMinMax[1] = 1.5f; return; }
    if (type == FX_SAT) { outMinMax[1] = 1; return; }
    return;
  }
  if (type == FX_HUE || type == FX_COLORIZE || type == FX_CONTRAST) { outMinMax[0] = -1; outMinMax[1] = 1; return; }
  if (type == FX_SAT) { outMinMax[1] = 360; return; }
  if (type == FX_THR || type == FX_EMBOSS || type == FX_GLITCH) { outMinMax[1] = 2; return; }
  if (type == FX_SOLAR) { outMinMax[1] = 1.5f; return; }
  if (type == FX_POST) { outMinMax[1] = 1; return; }
  if (type == FX_PIX) { outMinMax[0] = 0.25f; outMinMax[1] = 4; return; }
  if (type == FX_BLUR) { outMinMax[1] = 2; return; }
  if (type == FX_EDGE) { outMinMax[0] = 1; outMinMax[1] = 5; return; }
  if (type == FX_FB || type == FX_ROT180) { outMinMax[0] = type == FX_FB ? -180 : -1; outMinMax[1] = type == FX_FB ? 180 : 1; return; }
  if (type == FX_FLIP || type == FX_FLIP_V) { outMinMax[0] = 0.25f; outMinMax[1] = 4; return; }
  if (type == FX_MIRROR_H || type == FX_MIRROR_V) { outMinMax[0] = -1; outMinMax[1] = 1; return; }
}

String fxParamLabel(FxUnit u, int param) {
  if (u == null) return "—";
  int t = u.type;
  float v = fxParamGet(u, param);
  if (t == FX_MIRROR && param == 1) return round(v) == 0 ? "Horizontal" : "Vertical";
  if (t == FX_FLIP && param == 1) {
    int m = constrain(round(v), 0, 2);
    return m == 0 ? "Horizontal" : m == 1 ? "Vertical" : "Both";
  }
  if (t == FX_BULGE && param == 0) {
    if (abs(v) < 0.03f) return "Flat";
    if (v > 0) return "Bulge " + round(v * 100) + "%";
    return "Pinch " + round(-v * 100) + "%";
  }
  if ((t == FX_SLIDE || t == FX_PUSH) && param == 1) {
    int d = constrain(round(v), 0, 3);
    return d == 0 ? "Left" : d == 1 ? "Right" : d == 2 ? "Up" : "Down";
  }
  if (t == FX_FB && param == 1) {
    if (u.amount >= 0.995f) return "Light paint";
    if (v < 0.08f) return "Feedback";
    if (v > 0.92f) return "Trail";
    return round(v * 100) + "% Trail";
  }
  if (t == FX_RGBDELAY && param == 3) {
    if (v < 0.08f) return "RGB";
    if (v > 0.92f) return "BGR";
    return round(v * 100) + "% BGR";
  }
  if (t == FX_SLIT && param == 1) {
    int n = constrain(round(v), 1, 5);
    int ori = fxSlitOrient[constrain(fxTarget, 0, 2)];
    return n + (n == 1 ? " line" : " lines") + (ori == 0 ? " · →" : " · ↓");
  }
  if (t == FX_HUE && param == 1) return v < 0.02f ? "B&W" : round(v * 100) + "%";
  if (t == FX_ROTATE && param == 1) {
    if (abs(v) < 0.02f) return "Stop";
    return (v > 0 ? "+" : "") + nf(v, 1, 2);
  }
  if (t == FX_POST && param == 0) return v < 2 ? "Off" : str(round(v));
  if (t == FX_PIX && param == 0) return round(v) + " px";
  if (t == FX_KALEIDO && param == 0) return round(v) + " seg";
  if (t == FX_SLICES && param == 0) return round(v) + "×";
  if (t == FX_SLIT && param == 0) return round(constrain(v, 0, 2) / 2f * 100) + "%";
  if (t == FX_EDGE && param == 3) return round(v) + " px";
  if (fxParamFine(t, param)) return nf(v, 1, 2);
  if (fxParamRaw(t, param)) return round(v) + (fxParamIsDegrees(t, param) ? "°" : "");
  return round(v * 100) + "%";
}

boolean fxParamIsDegrees(int type, int param) {
  if (param == 0 && (type == FX_HUE || type == FX_COLORIZE || type == FX_ROTATE)) return true;
  if (param == 1 && (type == FX_KALEIDO || type == FX_ROT180)) return true;
  if (param == 2 && (type == FX_EMBOSS || type == FX_SLICES || type == FX_MIRROR)) return true;
  if (param == 3 && (type == FX_SAT || type == FX_FB)) return true;
  return false;
}

String fxFilterKey(String s) {
  if (s == null) return "";
  String out = "";
  String low = s.toLowerCase();
  for (int i = 0; i < low.length(); i++) {
    char c = low.charAt(i);
    if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) out += c;
  }
  return out;
}

boolean fxMatchesFilter(FxUnit u) {
  if (u == null) return false;
  String q = fxFilterKey(fxFilter);
  if (q.length() == 0) return true;
  String name = fxFilterKey(fxName(u.type));
  String shortn = fxFilterKey(fxShortName(u.type));
  String group = (u.type >= 0 && u.type < FX_GROUPS.length) ? fxFilterKey(FX_GROUPS[u.type]) : "";
  return name.indexOf(q) >= 0 || shortn.indexOf(q) >= 0 || group.indexOf(q) >= 0;
}

void drawFxFilterField(float x, float y, float w) {
  float h = FX_FILTER_H;
  boolean hot = fxFilterFocus
    || (mouseX >= x && mouseX < x + w && mouseY >= y && mouseY < y + h);
  noStroke();
  fill(WELL);
  rect(x, y, w, h);
  stroke(fxFilterFocus ? PLAY : (hot ? LINE : color(red(LINE), green(LINE), blue(LINE), 120)));
  strokeWeight(1);
  noFill();
  rect(x + 0.5f, y + 0.5f, w - 1, h - 1);
  noStroke();

  boolean hasText = fxFilter != null && fxFilter.length() > 0;
  float clearW = hasText ? 18 : 0;
  float textW = w - 16 - clearW;
  ui(11);
  textAlign(LEFT, CENTER);
  String shown = hasText ? fxFilter : "Search";
  fill(hasText ? (fxFilterFocus ? INK : MUTED) : DIM);
  text(fitText(shown, textW), x + 8, y + h * 0.5f);

  if (fxFilterFocus && (millis() / 530) % 2 == 0) {
    float cx = x + 8 + textWidth(fitText(hasText ? fxFilter : "", textW));
    stroke(INK);
    strokeWeight(1);
    line(cx, y + 7, cx, y + h - 7);
    noStroke();
  }

  if (hasText) {
    float cx = x + w - 14;
    boolean clearHot = mouseX >= cx - 8 && mouseX < cx + 8 && mouseY >= y && mouseY < y + h;
    fill(clearHot ? INK : DIM);
    textAlign(CENTER, CENTER);
    ui(12);
    text("×", cx, y + h * 0.5f - 1);
    hit("fx-filter-clear", cx - 10, y, 20, h);
  }
  hit("fx-filter", x, y, w, h);
}

void fxFilterType(char k, int code) {
  if (code == ENTER || code == RETURN || k == '\n' || k == '\r') {
    fxFilterFocus = false;
    return;
  }
  if (k == BACKSPACE || code == BACKSPACE) {
    if (fxFilter.length() > 0) fxFilter = fxFilter.substring(0, fxFilter.length() - 1);
    return;
  }
  if (k == CODED || k == DELETE || k == ESC) return;
  if (k < 32) return;
  if (fxFilter.length() >= 24) return;
  fxFilter += k;
  fxScroll = 0;
}

float drawFxPanel(float x, float y, float w, float bottom) {
  ensureFxRack(fxActiveStack());
  float listBot = bottom - FX_FILTER_H - 8;
  clipTop = y;
  clipBot = listBot;
  clip(x - 20, y, w + 40, max(1, listBot - y));
  float cy = y - fxScroll;

  fill(DIM);
  textAlign(LEFT, BASELINE);
  ui(10);
  text("FX", x, cy);
  resetLink("rst-FX", x + textWidth("FX") + 14, cy);
  cy += 16;

  ArrayList<FxUnit> stack = fxActiveStack();
  ui(10);
  textAlign(LEFT, BASELINE);
  if (fxKeyMapFrom >= 0 && fxKeyMapFrom < FX_RACK.length) {
    fill(MAP);
    String hint = "MAP  " + fxName(FX_RACK[fxKeyMapFrom]).toUpperCase()
      + "  ·  press a key  ·  esc";
    text(fitText(hint, w), x, cy);
  } else {
    fill(DIM);
    text("QWERTZUIOPÜ+  ·  ASDFGHJKLÖÄ#", x, cy);
  }
  cy += 10;
  cy = drawFxFocusBlock(stack, x, cy, w);

  int shown = 0;
  for (int i = 0; i < stack.size(); i++) {
    FxUnit u = stack.get(i);
    if (!fxMatchesFilter(u)) continue;
    cy = drawFxRackRow(u, i, x, cy, w);
    shown++;
  }
  if (shown == 0 && fxFilter.trim().length() > 0) {
    fill(DIM);
    textAlign(LEFT, BASELINE);
    ui(11);
    text("No matches", x, cy + 14);
    cy += 28;
  }

  float contentH = cy - (y - fxScroll) + 8;
  fxScrollMax = max(0, contentH - (listBot - y) + 4);
  if (fxScroll > fxScrollMax) fxScroll = fxScrollMax;
  noClip();
  clipTop = -100000;
  clipBot = 100000;
  if (fxScrollMax > 1) {
    float trackH = listBot - y;
    float thumb = max(24, trackH * trackH / (trackH + fxScrollMax));
    float ty = y + (trackH - thumb) * (fxScroll / fxScrollMax);
    noStroke();
    fill(GRAIN, 90);
    rect(x + w + 8, ty, 4, thumb, 2);
  }
  drawFxFilterField(x, bottom - FX_FILTER_H, w);
  return cy;
}

/** Selected FX at the top of the list: name plus four shared sliders. */
float drawFxFocusBlock(ArrayList<FxUnit> stack, float x, float y, float w) {
  if (stack == null || fxFocus < 0 || fxFocus >= stack.size()) return y;
  FxUnit u = stack.get(fxFocus);
  String focusLab = fxName(u.type).toUpperCase();
  String keyLab = fxSlotKeyLabel(fxFocus);
  if (keyLab.length() > 0) focusLab = keyLab + "  " + focusLab;
  float barH = 32;
  noStroke();
  fill(PLAY);
  rect(x - 4, y, w + 8, barH);
  fill(PAPER);
  textAlign(LEFT, CENTER);
  ui(11);
  text(fitText(focusLab, w - 64), x + 8, y + barH * 0.5f);
  ui(10);
  String rst = "Reset";
  float rw = textWidth(rst);
  float rx = x + w - rw - 4;
  boolean hot = mouseX >= rx && mouseX < rx + rw && mouseY >= y && mouseY < y + barH;
  fill(hot ? INK : PAPER);
  textAlign(LEFT, CENTER);
  text(rst, rx, y + barH * 0.5f);
  if (inClip(y, barH)) hit("fx-rst#" + fxFocus, rx - 2, y, rw + 6, barH);
  y += barH + 10;
  for (int p = 0; p < 4; p++) y = drawFxFocusSlider(u, p, x, y, w);
  y += 4;
  stroke(LINE);
  strokeWeight(1);
  line(x, y, x + w, y);
  noStroke();
  return y + 12;
}

float drawFxFocusSlider(FxUnit u, int param, float x, float y, float w) {
  String id = "sl-fx#" + param;
  if (u == null || !fxParamUsed(u.type, param)) return drawFxIdleSlider(id, param, x, y, w);
  float[] mm = new float[2];
  fxParamRange(u.type, param, mm);
  float v = fxParamGet(u, param);
  String name = (param + 1) + "  " + fxParamName(u.type, param);
  return hSlide(id, name, fxParamLabel(u, param), x, y, w, v, mm[0], mm[1]);
}

/** Empty slot. Still a MIDI target, so one mapping follows whichever FX is selected. */
float drawFxIdleSlider(String id, int param, float x, float y, float w) {
  fill(DIM);
  textAlign(LEFT, BASELINE);
  ui(11);
  text(str(param + 1), x, y + 10);
  noStroke();
  fill(WELL);
  rect(x, y + 16, w, 2);
  if (inClip(y, 28)) mapTarget(id, x, y, w, 28);
  return y + 34;
}

String fxParamValueLabel(FxUnit u) {
  if (u == null) return "—";
  if (u.type == FX_HUE || u.type == FX_COLORIZE || u.type == FX_ROTATE) return round(u.amount) + "°";
  if (u.type == FX_POST) return u.amount < 2 ? "Off" : str(round(u.amount));
  if (u.type == FX_PIX) return round(u.amount) + " px";
  if (u.type == FX_KALEIDO) return round(u.amount) + " seg";
  if (u.type == FX_SLICES) return round(u.amount) + "×";
  if (u.type == FX_SLIT) return round(constrain(u.amount, 0, 2) / 2f * 100) + "%";
  return round(u.amount * 100) + "%";
}

/** Rack row: checkbox toggles, name/key selects (shows controls), Map assigns the key. */
float drawFxRackRow(FxUnit u, int index, float x, float y, float w) {
  float rowH = 26;
  boolean focus = fxFocus == index;
  boolean lit = u.on || u.fade > 0.05f;
  boolean mapArm = fxKeyMapFrom == index;

  if (inClip(y, rowH)) {
    // Name / body → select only (registered first).
    hit("fx-row#" + index, x, y, w, rowH);
    // Checkbox → toggle (wins over row).
    hit("fx-on#" + index, x, y, 18, rowH);
  }

  noStroke();
  if (focus || lit || mapArm) {
    fill(mapArm ? color(red(MAP), green(MAP), blue(MAP), 36) : (lit ? WELL : color(red(WELL), green(WELL), blue(WELL), 100)));
    rect(x - 4, y, w + 8, rowH);
  }
  if (focus || mapArm) {
    stroke(mapArm ? MAP : PLAY);
    strokeWeight(1);
    noFill();
    rect(x - 4.5f, y + 0.5f, w + 9, rowH - 1);
    noStroke();
  }

  // Soft glow bar = fade amount
  if (u.fade > 0.02f) {
    fill(GRAIN, (int) (28 + u.fade * 70));
    rect(x - 4, y + 2, 3, rowH - 4);
  }

  // Toggle checkbox only
  stroke(u.on ? PLAY : LINE);
  strokeWeight(1);
  noFill();
  rect(x + 2, y + 7, 12, 12);
  if (u.on) {
    noStroke();
    fill(PLAY);
    rect(x + 5, y + 10, 6, 6);
  }
  noStroke();

  ui(10);
  String mapLab = "Map";
  float mw = textWidth(mapLab);
  String rst = "Reset";
  float rw = textWidth(rst);
  float gap = 12;
  float rx = x + w - rw;
  float mx = rx - gap - mw;

  fill(mapArm ? MAP : (lit || focus ? PLAY : DIM));
  textAlign(LEFT, CENTER);
  ui(11);
  text(fxSlotKeyLabel(index), x + 20, y + rowH * 0.5f);

  ui(10);
  String amt = fxAmountLabel(u);
  float amtW = textWidth(amt);
  float nameX = x + 40;
  float amtRight = mx - 10;
  float nameMax = max(28, amtRight - amtW - 8 - nameX);
  ui(11);
  fill(mapArm ? MAP : (lit || focus ? PLAY : MUTED));
  textAlign(LEFT, CENTER);
  text(fitText(fxName(u.type).toUpperCase(), nameMax), nameX, y + rowH * 0.5f);

  ui(10);
  boolean mapHot = mouseX >= mx && mouseX < mx + mw && mouseY >= y && mouseY < y + rowH;
  fill(mapArm ? MAP : (mapHot ? INK : DIM));
  textAlign(LEFT, CENTER);
  text(mapLab, mx, y + rowH * 0.5f);
  if (inClip(y, rowH)) hit("fx-map#" + index, mx - 4, y, mw + 8, rowH);

  boolean hot = mouseX >= rx && mouseX < rx + rw && mouseY >= y && mouseY < y + rowH;
  fill(hot ? INK : DIM);
  textAlign(LEFT, CENTER);
  text(rst, rx, y + rowH * 0.5f);
  if (inClip(y, rowH)) hit("fx-rst#" + index, rx - 2, y, rw + 4, rowH);

  fill(DIM);
  textAlign(RIGHT, CENTER);
  text(amt, amtRight, y + rowH * 0.5f);

  return y + rowH;
}
