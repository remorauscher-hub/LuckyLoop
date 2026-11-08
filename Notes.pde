// TEXT mode — fields drawn on the live image. Tools live in the right dock.
// Place: trackpad pinch scales, twist rotates, two-finger drag or mouse moves.
// On air composites the same fields onto Syphon / beamer.
// Never construct Swing/JTextPane in setup()/bootProject — macOS NEWT+AWT deadlock.

ArrayList<TextField> textFields = new ArrayList<TextField>();
int textSel = -1;
int textNextId = 1;
boolean textPlaceOn = false;
boolean textPlaceDrag = false;
boolean textLineOn = false;
float textLineX0, textLineY0, textLineX1, textLineY1;
boolean textDupLatch = false;
boolean textGeomDirty = false;
float textDragX0, textDragY0, textDragCx0, textDragCy0;
float[] textLocalBuf = new float[2];

boolean notesPreviewOn = false;
boolean feedOnAir = true;
boolean textRecordOn = false; // burn text into the Hap loop only when this is on
boolean textFontOpen = false;
boolean textHslDrag = false;
float textHslX, textHslY, textHslW, textHslH;
float textFontMenuX, textFontMenuY, textFontMenuW;
String[] textFontNames = new String[0];
PFont[] textFontFaces;
boolean textFontsReady = false;
boolean notesFocus = false;
boolean notesDraggingSelect = false;
char notesLastChar = 0;
int notesLastCharAt = -1;
boolean pendingNotesLoad = false;
boolean notesBooted = false;

static final float TEXT_BOX_W = 0.84f;
static final float TEXT_BOX_H = 0.62f;
static final int TEXT_FONT = 24;
static final float TEXT_FADE_MS = 420;

static final int NICO_BOLD = 0;
static final int NICO_ITALIC = 1;
static final int NICO_ALIGN_L = 2;
static final int NICO_ALIGN_C = 3;
static final int NICO_ALIGN_R = 4;
static final int NICO_SIZE_DN = 5;
static final int NICO_SIZE_UP = 6;
static final int NICO_VALIGN_T = 7;
static final int NICO_VALIGN_C = 8;
static final int NICO_VALIGN_B = 9;

class TextField {
  int id;
  String fileName;
  NotesPad pad;
  float cx = 0.5f;
  float cy = 0.5f;
  float rot = 0;
  float scale = 1;
  float bw = TEXT_BOX_W;
  float bh = TEXT_BOX_H;
  int hAlign = javax.swing.text.StyleConstants.ALIGN_CENTER;
  int vAlign = 1;
  float hue = 0;
  float light = 1;
  String fontName = "Menlo";
  boolean on = true;
  float fade = 1; // 0..1, duplicate eases in
  PImage plate;
  PImage caretImg;
  int[] platePix;
  int[] caretPix;
  int cacheRev = -1;
  int caretRev = -1;
  boolean caretBlink = false;
}

class TextExportSnap {
  java.awt.image.BufferedImage img;
  int pw, ph;
  float cx, cy, rot, scale, bw, bh, fade;
}

volatile ArrayList<TextExportSnap> textExportSnaps = new ArrayList<TextExportSnap>();
java.awt.image.BufferedImage textExportFrame;

boolean notesModeOn() {
  return topMode == TOP_NOTES;
}

void bootNotesIfNeeded() {
  if (notesBooted) return;
  if (frameCount < 2) return;
  notesBooted = true;
  if (pendingNotesLoad) applyPendingNotesLoad();
}

NotesPad selectedPad() {
  TextField f = selectedText();
  return f == null ? null : f.pad;
}

NotesPad activeNotesPad() {
  return selectedPad();
}

TextField selectedText() {
  if (textSel < 0 || textSel >= textFields.size()) return null;
  return textFields.get(textSel);
}

void resetTextSession() {
  textFields.clear();
  textSel = -1;
  textNextId = 1;
  notesFocus = false;
  notesPreviewOn = false;
  feedOnAir = true;
  textRecordOn = false;
  textFontOpen = false;
  textHslDrag = false;
  textPlaceOn = false;
  textPlaceDrag = false;
  textLineOn = false;
  notesDraggingSelect = false;
  textGeomDirty = false;
  pendingNotesLoad = false;
}

void loadProjectNotes() {
  pendingNotesLoad = true;
  notesFocus = false;
  textPlaceOn = false;
  textPlaceDrag = false;
  if (frameCount >= 1) applyPendingNotesLoad();
}

void applyPendingNotesLoad() {
  if (!pendingNotesLoad || frameCount < 1) return;
  textFields.clear();
  textSel = -1;
  notesPreviewOn = false;
  feedOnAir = true;
  textRecordOn = false;
  notesFocus = false;
  textGeomDirty = false;
  if (projectOpen) readTextProject();
  pendingNotesLoad = false;
}

void readTextProject() {
  File manifest = new File(projectDir, "text.json");
  if (manifest.isFile()) {
    try {
      JSONObject root = loadJSONObject(manifest.getAbsolutePath());
      if (root != null) {
        notesPreviewOn = root.getBoolean("preview", false);
        feedOnAir = root.getBoolean("onAir", true);
        textRecordOn = root.getBoolean("record", false);
        textNextId = max(1, root.getInt("nextId", 1));
        JSONArray arr = root.hasKey("fields") ? root.getJSONArray("fields") : null;
        int n = arr == null ? 0 : arr.size();
        for (int i = 0; i < n; i++) {
          JSONObject o = arr.getJSONObject(i);
          TextField f = new TextField();
          f.id = o.getInt("id", textNextId++);
          textNextId = max(textNextId, f.id + 1);
          String name = o.getString("file", "text-" + f.id + ".rtf");
          if (!safeTextName(name)) name = "text-" + f.id + ".rtf";
          f.fileName = name;
          f.cx = o.getFloat("cx", 0.5);
          f.cy = o.getFloat("cy", 0.5);
          f.rot = o.getFloat("rot", 0);
          f.scale = constrain(o.getFloat("scale", 1), 0.15, 8);
          f.bw = constrain(o.getFloat("bw", TEXT_BOX_W), 0.2, 1);
          f.bh = constrain(o.getFloat("bh", TEXT_BOX_H), 0.2, 1);
          f.hAlign = o.getInt("hAlign", javax.swing.text.StyleConstants.ALIGN_CENTER);
          f.vAlign = constrain(o.getInt("vAlign", 1), 0, 2);
          f.pad = new NotesPad(f.fileName, TEXT_FONT);
          f.pad.loadRtf(new File(projectDir, f.fileName));
          f.pad.vAlign = f.vAlign;
          f.pad.setBlockAlign(f.hAlign);
          if (o.hasKey("font")) f.pad.setFontFamily(o.getString("font"));
          f.fontName = f.pad.fontFamily;
          f.on = o.getBoolean("on", true);
          f.fade = f.on ? 1 : 0;
          if (o.hasKey("hue")) {
            f.hue = o.getFloat("hue", 0);
            f.light = constrain(o.getFloat("light", 1), 0, 1);
            f.pad.setForegroundRgb(hslToColor(f.hue, 1, f.light) & 0xFFFFFF, true);
          } else pullTextColor(f);
          f.pad.dirty = false;
          textFields.add(f);
        }
        int sel = root.getInt("sel", textFields.isEmpty() ? -1 : 0);
        textSel = textFields.isEmpty() ? -1 : constrain(sel, 0, textFields.size() - 1);
      }
    } catch (Exception e) {
      println("text.json load failed: " + e.getMessage());
    }
    return;
  }
  File legacy = new File(projectDir, "notes.rtf");
  if (!legacy.isFile()) return;
  TextField f = new TextField();
  f.id = textNextId++;
  f.fileName = "text-" + f.id + ".rtf";
  f.pad = new NotesPad(f.fileName, TEXT_FONT);
  f.pad.loadRtf(legacy);
  f.pad.syncFormatFromCaret();
  f.hAlign = f.pad.align;
  f.vAlign = 1;
  f.pad.vAlign = 1;
  f.fontName = f.pad.fontFamily;
  pullTextColor(f);
  f.pad.dirty = false;
  textFields.add(f);
  textSel = 0;
  textGeomDirty = true;
}

boolean safeTextName(String name) {
  if (name == null) return false;
  if (!name.startsWith("text-") || !name.endsWith(".rtf")) return false;
  if (name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 || name.indexOf("..") >= 0) return false;
  return true;
}

void saveProjectNotes() {
  if (!projectOpen) return;
  try {
    for (int i = 0; i < textFields.size(); i++) {
      TextField f = textFields.get(i);
      if (f.pad == null) continue;
      if (f.fileName == null || !safeTextName(f.fileName)) f.fileName = "text-" + f.id + ".rtf";
      if (f.pad.isDirty() || textGeomDirty) f.pad.saveRtf(new File(projectDir, f.fileName));
    }
    JSONObject root = new JSONObject();
    root.setInt("version", 1);
    root.setBoolean("preview", notesPreviewOn);
    root.setBoolean("onAir", feedOnAir);
    root.setBoolean("record", textRecordOn);
    root.setInt("nextId", textNextId);
    root.setInt("sel", textSel);
    JSONArray arr = new JSONArray();
    for (int i = 0; i < textFields.size(); i++) {
      TextField f = textFields.get(i);
      JSONObject o = new JSONObject();
      o.setInt("id", f.id);
      o.setString("file", f.fileName == null ? ("text-" + f.id + ".rtf") : f.fileName);
      o.setFloat("cx", f.cx);
      o.setFloat("cy", f.cy);
      o.setFloat("rot", f.rot);
      o.setFloat("scale", f.scale);
      o.setFloat("bw", f.bw);
      o.setFloat("bh", f.bh);
      o.setInt("hAlign", f.hAlign);
      o.setInt("vAlign", f.vAlign);
      o.setFloat("hue", f.hue);
      o.setFloat("light", f.light);
      o.setString("font", f.fontName != null ? f.fontName : "Menlo");
      o.setBoolean("on", f.on);
      arr.setJSONObject(i, o);
    }
    root.setJSONArray("fields", arr);
    saveJSONObject(root, new File(projectDir, "text.json").getAbsolutePath());
    textGeomDirty = false;
  } catch (Exception e) {
    println("text save failed: " + e.getMessage());
  }
}

void flushNotesIfDirty() {
  if (!projectOpen || !textStoreDirty()) return;
  saveProjectNotes();
}

boolean textStoreDirty() {
  if (textGeomDirty) return true;
  for (int i = 0; i < textFields.size(); i++) {
    TextField f = textFields.get(i);
    if (f.pad != null && f.pad.isDirty()) return true;
  }
  return false;
}

TextField addTextField() {
  if (frameCount < 1) return null;
  TextField f = new TextField();
  f.id = textNextId++;
  f.fileName = "text-" + f.id + ".rtf";
  f.pad = new NotesPad(f.fileName, TEXT_FONT);
  f.hAlign = javax.swing.text.StyleConstants.ALIGN_CENTER;
  f.vAlign = 1;
  f.pad.vAlign = 1;
  f.hue = 0;
  f.light = 1;
  f.fontName = "Menlo";
  f.pad.setBlockAlign(f.hAlign);
  f.pad.setForegroundRgb(0xFFFFFF, false);
  if (!textFields.isEmpty()) {
    f.cy = constrain(0.42f + textFields.size() * 0.08f, 0.2f, 0.8f);
  }
  textFields.add(f);
  textSel = textFields.size() - 1;
  notesFocus = !textPlaceOn;
  textGeomDirty = true;
  note("Text " + f.id);
  return f;
}

void duplicateSelectedText() {
  TextField src = selectedText();
  if (src == null || src.pad == null || frameCount < 1) return;
  TextField f = new TextField();
  f.id = textNextId++;
  f.fileName = "text-" + f.id + ".rtf";
  f.pad = new NotesPad(f.fileName, TEXT_FONT);
  f.pad.copyDocumentFrom(src.pad);
  f.cx = src.cx;
  f.cy = constrain(src.cy + 0.06f, -0.35f, 1.35f);
  f.rot = src.rot;
  f.scale = src.scale;
  f.bw = src.bw;
  f.bh = src.bh;
  f.hAlign = src.hAlign;
  f.vAlign = src.vAlign;
  f.pad.vAlign = src.vAlign;
  f.hue = src.hue;
  f.light = src.light;
  f.fontName = src.fontName != null ? src.fontName : src.pad.fontFamily;
  f.on = true;
  f.fade = 0;
  int at = constrain(textSel + 1, 0, textFields.size());
  textFields.add(at, f);
  textSel = at;
  notesFocus = !textPlaceOn;
  textFontOpen = false;
  textGeomDirty = true;
  note("Text " + f.id);
}

void removeSelectedText() {
  TextField f = selectedText();
  if (f == null) return;
  if (projectOpen && safeTextName(f.fileName)) {
    File file = new File(projectDir, f.fileName);
    if (file.isFile()) file.delete();
  }
  textFields.remove(textSel);
  if (textFields.isEmpty()) textSel = -1;
  else textSel = constrain(textSel, 0, textFields.size() - 1);
  notesFocus = false;
  notesDraggingSelect = false;
  textPlaceDrag = false;
  textFontOpen = false;
  textGeomDirty = true;
  flushNotesIfDirty();
  note("Text removed");
}

void removeAllText() {
  if (textFields.isEmpty()) return;
  if (projectOpen) {
    for (int i = 0; i < textFields.size(); i++) {
      TextField f = textFields.get(i);
      if (f == null || !safeTextName(f.fileName)) continue;
      File file = new File(projectDir, f.fileName);
      if (file.isFile()) file.delete();
    }
  }
  textFields.clear();
  textSel = -1;
  notesFocus = false;
  notesDraggingSelect = false;
  textPlaceDrag = false;
  textLineOn = false;
  textFontOpen = false;
  textGeomDirty = true;
  flushNotesIfDirty();
  note("Text cleared");
}

void selectTextIndex(int i, boolean focus) {
  if (i < 0 || i >= textFields.size()) return;
  textSel = i;
  TextField f = textFields.get(i);
  if (f.pad != null) {
    f.pad.vAlign = f.vAlign;
    f.pad.syncFormatFromCaret();
    f.fontName = f.pad.fontFamily;
    pullTextColor(f);
  }
  notesFocus = focus && !textPlaceOn && f.on;
}

void toggleTextEnabled(int i) {
  if (i < 0 || i >= textFields.size()) return;
  TextField f = textFields.get(i);
  f.on = !f.on;
  if (!f.on && textSel == i) notesFocus = false;
  textGeomDirty = true;
  markDirty();
  note(f.on ? "Text on" : "Text off");
}

/** Still on screen: enabled, or fading out after X. */
boolean textShown(TextField f) {
  return f != null && (f.on || f.fade > 0.01f);
}

/** X: fade every visible field out and leave it off. The list keeps the fields. */
boolean textFadeOut() {
  boolean any = false;
  for (int i = 0; i < textFields.size(); i++) {
    TextField f = textFields.get(i);
    if (f == null || !f.on) continue;
    f.on = false;
    any = true;
  }
  if (!any) return false;
  notesFocus = false;
  textGeomDirty = true;
  markDirty();
  return true;
}

void pullTextColor(TextField f) {
  if (f == null || f.pad == null) return;
  float[] hsl = new float[3];
  colorToHsl(f.pad.foregroundRgb() | 0xFF000000, hsl);
  f.hue = hsl[0];
  f.light = hsl[2];
}

void textHslApply(float mx, float my) {
  TextField f = selectedText();
  if (f == null || f.pad == null || textHslW < 2) return;
  f.hue = constrain((mx - textHslX) / textHslW, 0, 1) * 360f;
  f.light = constrain(1f - (my - textHslY) / textHslH, 0, 1);
  f.pad.setForegroundRgb(hslToColor(f.hue, 1, f.light) & 0xFFFFFF, true);
  textGeomDirty = true;
}

void toggleTextFontMenu() {
  if (selectedText() == null) return;
  textFontOpen = !textFontOpen;
}

void pickTextFont(int i) {
  ensureTextFonts();
  textFontOpen = false;
  if (textFontNames == null || i < 0 || i >= textFontNames.length) return;
  TextField f = selectedText();
  if (f == null || f.pad == null) return;
  f.fontName = textFontNames[i];
  f.pad.setFontFamily(f.fontName);
  textGeomDirty = true;
}

String registerBundledFont(String fileName) {
  try {
    File file = new File(dataPath(fileName));
    if (!file.isFile()) return null;
    java.awt.Font font = java.awt.Font.createFont(java.awt.Font.TRUETYPE_FONT, file);
    java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().registerFont(font);
    return font.getFamily();
  } catch (Exception e) {
    println("font " + fileName + ": " + e.getMessage());
    return null;
  }
}

boolean fontFamilyInstalled(String name) {
  if (name == null || name.length() == 0) return false;
  String[] all = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().getAvailableFontFamilyNames();
  for (int i = 0; i < all.length; i++) if (name.equals(all[i])) return true;
  return false;
}

void ensureTextFonts() {
  if (textFontsReady) return;
  textFontsReady = true;
  String src = registerBundledFont("SourceCodePro-Regular.otf");
  String rob = registerBundledFont("RobotoMono-Regular.ttf");
  String[] want = {
    "Menlo",
    src != null ? src : "Source Code Pro",
    rob != null ? rob : "Roboto Mono",
    "Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Georgia", "Courier New"
  };
  ArrayList<String> ok = new ArrayList<String>();
  for (int i = 0; i < want.length; i++) {
    if (want[i] == null) continue;
    boolean bundled = (src != null && want[i].equals(src)) || (rob != null && want[i].equals(rob));
    if (!bundled && !fontFamilyInstalled(want[i])) continue;
    boolean dup = false;
    for (int j = 0; j < ok.size(); j++) if (ok.get(j).equals(want[i])) dup = true;
    if (!dup) ok.add(want[i]);
  }
  if (ok.isEmpty()) ok.add("Menlo");
  textFontNames = new String[ok.size()];
  for (int i = 0; i < ok.size(); i++) textFontNames[i] = ok.get(i);
  textFontFaces = new PFont[textFontNames.length];
  for (int i = 0; i < textFontNames.length; i++) {
    try {
      textFontFaces[i] = createFont(textFontNames[i], 14, true);
    } catch (Exception e) {
      textFontFaces[i] = null;
    }
  }
}

void toggleTextPlace() {
  textPlaceOn = !textPlaceOn;
  if (textPlaceOn) {
    notesFocus = false;
    notesDraggingSelect = false;
    if (textSel < 0 && !textFields.isEmpty()) textSel = 0;
    ensureFramePad();
    drainPadGestures();
    note("Place  ·  pinch scales  ·  twist rotates  ·  drag moves  ·  space records");
  } else {
    textPlaceDrag = false;
    note("Place off  ·  click the field to type");
  }
}

void toggleNotesPreview() {
  notesPreviewOn = !notesPreviewOn;
  textGeomDirty = true;
  note(notesPreviewOn ? "Text visible outside Text" : "Text hidden outside Text");
  markDirty();
}

void toggleTextRecord() {
  textRecordOn = !textRecordOn;
  textGeomDirty = true;
  note(textRecordOn ? "Text records into the loop" : "Text stays out of the loop");
  markDirty();
}

void toggleFeedOnAir() {
  feedOnAir = !feedOnAir;
  textGeomDirty = true;
  note(feedOnAir ? "Text on air" : "Text off air");
  markDirty();
}

boolean notesHandleKey(char k, int code, boolean shift, boolean meta, boolean alt) {
  if (!notesModeOn() || textPlaceOn) return false;
  NotesPad pad = selectedPad();
  if (pad == null) return false;
  notesFocus = true;
  // Printable characters, including ö ä ü ß. keyPressed on NEWT often marks
  // those CODED; keyTyped inserts whatever this press does not.
  char typed = (k != CODED && k != 0 && !java.lang.Character.isISOControl(k)) ? k : 0;
  if (typed != 0 && !meta && !alt) {
    if (notesAcceptChar(typed)) return true;
  }
  if (k == CODED || code == LEFT || code == RIGHT || code == UP || code == DOWN
      || code == BACKSPACE || code == DELETE || code == ENTER || code == RETURN) {
    int vk = code;
    if (code == ENTER || code == RETURN) vk = java.awt.event.KeyEvent.VK_ENTER;
    if (code == BACKSPACE) vk = java.awt.event.KeyEvent.VK_BACK_SPACE;
    if (code == DELETE) vk = java.awt.event.KeyEvent.VK_DELETE;
    if (code == LEFT) vk = java.awt.event.KeyEvent.VK_LEFT;
    if (code == RIGHT) vk = java.awt.event.KeyEvent.VK_RIGHT;
    if (code == UP) vk = java.awt.event.KeyEvent.VK_UP;
    if (code == DOWN) vk = java.awt.event.KeyEvent.VK_DOWN;
    if (pad.typeKey(vk, shift, meta, alt)) return true;
  }
  if (meta) {
    char low = Character.toLowerCase(k);
    if (low == 'b') {
      pad.toggleBold();
      return true;
    }
    if (low == 'i') {
      pad.toggleItalic();
      return true;
    }
    int vk = -1;
    if (low == 'a') vk = java.awt.event.KeyEvent.VK_A;
    else if (low == 'c') vk = java.awt.event.KeyEvent.VK_C;
    else if (low == 'x') vk = java.awt.event.KeyEvent.VK_X;
    else if (low == 'v') vk = java.awt.event.KeyEvent.VK_V;
    else if (low == 'z') vk = java.awt.event.KeyEvent.VK_Z;
    if (vk >= 0 && pad.typeKey(vk, shift, true, alt)) return true;
  }
  return false;
}

/** Insert one glyph. A second event for the same key (press + typed) is ignored. */
boolean notesAcceptChar(char ch) {
  if (ch == 0 || ch == CODED) return false;
  if (java.lang.Character.isISOControl(ch) && ch != '\n' && ch != '\t') return false;
  NotesPad pad = selectedPad();
  if (pad == null) return false;
  int now = millis();
  if (ch == notesLastChar && now - notesLastCharAt >= 0 && now - notesLastCharAt < 12) return true;
  notesLastChar = ch;
  notesLastCharAt = now;
  return pad.typeChar(ch);
}

boolean overNotesEditor(float mx, float my) {
  return notesModeOn() && !textPlaceOn && textHitField(mx, my) >= 0;
}

int textPlateW(TextField f) {
  return max(8, round(capW * f.bw));
}

int textPlateH(TextField f) {
  return max(8, round(capH * f.bh));
}

boolean textUnproject(TextField f, float mx, float my, float[] out, float slop) {
  if (f == null || previewIw < 2 || previewIh < 2) return false;
  float cxp = previewIx + f.cx * previewIw;
  float cyp = previewIy + f.cy * previewIh;
  float dx = mx - cxp;
  float dy = my - cyp;
  float a = -radians(f.rot);
  float c = cos(a);
  float s = sin(a);
  float lx = dx * c - dy * s;
  float ly = dx * s + dy * c;
  float dw = max(1, previewIw * f.bw * f.scale);
  float dh = max(1, previewIh * f.bh * f.scale);
  float hw = dw * 0.5f;
  float hh = dh * 0.5f;
  if (out != null) {
    out[0] = ((lx + hw) / dw) * textPlateW(f);
    out[1] = ((ly + hh) / dh) * textPlateH(f);
  }
  return abs(lx) <= hw + slop && abs(ly) <= hh + slop;
}

int textHitField(float mx, float my) {
  if (!notesModeOn() || previewIw < 2) return -1;
  int best = -1;
  float bestD = 1e9f;
  for (int i = 0; i < textFields.size(); i++) {
    TextField f = textFields.get(i);
    if (!f.on) continue;
    if (!textUnproject(f, mx, my, null, 8)) continue;
    float dx = (mx - (previewIx + f.cx * previewIw)) / previewIw;
    float dy = (my - (previewIy + f.cy * previewIh)) / previewIh;
    float d = dx * dx + dy * dy;
    if (i == textSel) d *= 0.82f;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

void textPreviewPointerDown(float mx, float my, boolean shift) {
  int hit = textHitField(mx, my);
  int clicks = 1;
  if (mouseEvent != null) clicks = max(1, mouseEvent.getCount());
  if (textPlaceOn) {
    if (hit >= 0) selectTextIndex(hit, false);
    TextField f = selectedText();
    if (f == null) return;
    textPlaceDrag = true;
    notesDraggingSelect = false;
    notesFocus = false;
    textDragX0 = mx;
    textDragY0 = my;
    textDragCx0 = f.cx;
    textDragCy0 = f.cy;
    return;
  }
  // Nothing selected: the next stroke is a new field, even on top of others.
  // A short click still picks the field underneath.
  if (textSel < 0 || hit < 0) {
    notesFocus = false;
    notesDraggingSelect = false;
    textLineOn = true;
    textLineX0 = textLineX1 = mx;
    textLineY0 = textLineY1 = my;
    return;
  }
  selectTextIndex(hit, true);
  TextField f = selectedText();
  if (f == null || f.pad == null) return;
  notesFocus = true;
  notesDraggingSelect = true;
  textUnproject(f, mx, my, textLocalBuf, 0);
  f.pad.clickAt(textLocalBuf[0], textLocalBuf[1], shift, clicks);
}

void textPlaceDragMove(float mx, float my) {
  TextField f = selectedText();
  if (f == null || previewIw < 2 || previewIh < 2) return;
  f.cx = constrain(textDragCx0 + (mx - textDragX0) / previewIw, -0.35, 1.35);
  f.cy = constrain(textDragCy0 + (my - textDragY0) / previewIh, -0.35, 1.35);
  textGeomDirty = true;
}

void notesPointerDrag(float mx, float my) {
  if (!notesDraggingSelect || !notesModeOn() || textPlaceOn) return;
  TextField f = selectedText();
  if (f == null || f.pad == null) return;
  textUnproject(f, mx, my, textLocalBuf, 0);
  f.pad.clickAt(textLocalBuf[0], textLocalBuf[1], true);
}

void deselectText() {
  textSel = -1;
  notesFocus = false;
  notesDraggingSelect = false;
  textPlaceDrag = false;
  textFontOpen = false;
  flushNotesIfDirty();
  note("Deselected  ·  drag a line");
}

void notesPointerUp() {
  notesDraggingSelect = false;
}

/** Drag on empty preview: line tilt, midpoint, and length become the new field. */
void dragTextLine(float mx, float my) {
  if (!textLineOn) return;
  textLineX1 = mx;
  textLineY1 = my;
}

void finishTextLine() {
  if (!textLineOn) return;
  textLineOn = false;
  if (previewIw < 2 || previewIh < 2) return;
  float x0 = constrain(textLineX0, previewIx, previewIx + previewIw);
  float y0 = constrain(textLineY0, previewIy, previewIy + previewIh);
  float x1 = constrain(textLineX1, previewIx, previewIx + previewIw);
  float y1 = constrain(textLineY1, previewIy, previewIy + previewIh);
  float dx = x1 - x0;
  float dy = y1 - y0;
  float len = sqrt(dx * dx + dy * dy);
  if (len < 12) {
    if (textSel < 0) {
      int hit = textHitField(textLineX0, textLineY0);
      if (hit >= 0) selectTextIndex(hit, true);
    }
    return;
  }
  float span = max(previewIw, previewIh);
  int px = constrain(round(len / span * NotesPad.SIZE_MAX), NotesPad.SIZE_MIN, NotesPad.SIZE_MAX);
  float deg = degrees(atan2(dy, dx));
  while (deg > 90) deg -= 180;
  while (deg < -90) deg += 180;
  TextField f = addTextField();
  if (f == null) return;
  f.cx = constrain(((x0 + x1) * 0.5f - previewIx) / previewIw, -0.35f, 1.35f);
  f.cy = constrain(((y0 + y1) * 0.5f - previewIy) / previewIh, -0.35f, 1.35f);
  f.rot = deg;
  if (f.pad != null) f.pad.setSizePx(px);
  textGeomDirty = true;
  note("Text " + f.id + "  ·  " + px + " px");
}

void drawTextLineGesture(float ix, float iy, float iw, float ih) {
  if (!textLineOn || iw < 2 || ih < 2) return;
  float x0 = constrain(textLineX0, ix, ix + iw);
  float y0 = constrain(textLineY0, iy, iy + ih);
  float x1 = constrain(textLineX1, ix, ix + iw);
  float y1 = constrain(textLineY1, iy, iy + ih);
  stroke(ACCENT);
  strokeWeight(1.25);
  line(x0, y0, x1, y1);
  noStroke();
  fill(ACCENT);
  float mx = (x0 + x1) * 0.5f;
  float my = (y0 + y1) * 0.5f;
  ellipse(mx, my, 5, 5);
}

void notesScrollWheel(float count) {
  if (textPlaceOn || !notesModeOn()) return;
  int hit = textHitField(mouseX, mouseY);
  if (hit < 0) return;
  TextField f = textFields.get(hit);
  if (f.pad == null) return;
  f.pad.nudgeScroll(count, textPlateH(f));
}

boolean notesWheelConsumes() {
  if (!notesModeOn()) return false;
  if (textPlaceOn && overLivePreview(mouseX, mouseY)) return true;
  return textHitField(mouseX, mouseY) >= 0;
}

void drainPadGestures() {
  if (!PadCtl.loaded) return;
  try { PadCtl.pollMagnify(); } catch (Throwable t) {}
  try { PadCtl.pollRotate(); } catch (Throwable t) {}
  try { PadCtl.pollScroll(frameScrollSample); } catch (Throwable t) {}
}

float wrapDeg(float deg) {
  while (deg > 180) deg -= 360;
  while (deg < -180) deg += 360;
  return deg;
}

void serviceTextPlace() {
  if (!notesModeOn()) return;
  if (!textPlaceOn || selectedText() == null || !selectedText().on) {
    if (PadCtl.loaded && framePadOn) drainPadGestures();
    return;
  }
  ensureFramePad();
  if (!PadCtl.loaded) return;
  TextField f = selectedText();
  try {
    float mag = PadCtl.pollMagnify();
    if (abs(mag) > 0.00001f) {
      f.scale = constrain(f.scale * (1f + mag * 2.2f), 0.15f, 8f);
      textGeomDirty = true;
    }
  } catch (Throwable t) {}
  try {
    float rot = PadCtl.pollRotate();
    if (abs(rot) > 0.0001f) {
      f.rot = wrapDeg(f.rot - rot);
      textGeomDirty = true;
    }
  } catch (Throwable t) {}
  try {
    int got = PadCtl.pollScroll(frameScrollSample);
    if (got == 1 && (overLivePreview(mouseX, mouseY) || textPlaceDrag)) {
      float s = 2.2f / max(160f, min(previewIw, previewIh));
      float sdx = frameScrollSample[0];
      float sdy = frameScrollSample[1];
      f.cx = constrain(f.cx + sdx * s, -0.35f, 1.35f);
      f.cy = constrain(f.cy - sdy * s, -0.35f, 1.35f);
      textGeomDirty = true;
    }
  } catch (Throwable t) {}
}

void notesApplySwatch(int idx) {
  NotesPad pad = selectedPad();
  if (pad == null) return;
  pad.applyColorIndex(idx, true);
  note("Text  ·  color");
}

void notesToggleBold() {
  NotesPad pad = selectedPad();
  if (pad == null) return;
  pad.toggleBold();
}

void notesToggleItalic() {
  NotesPad pad = selectedPad();
  if (pad == null) return;
  pad.toggleItalic();
}

void notesSetAlign(int align) {
  TextField f = selectedText();
  if (f == null || f.pad == null) return;
  f.hAlign = align;
  f.pad.setBlockAlign(align);
  if (!textPlaceOn) notesFocus = true;
  textGeomDirty = true;
}

void notesSetVAlign(int v) {
  TextField f = selectedText();
  if (f == null) return;
  v = constrain(v, 0, 2);
  if (f.vAlign == v) return;
  f.vAlign = v;
  if (f.pad != null) {
    f.pad.vAlign = v;
    f.pad.visualRev++;
  }
  f.cacheRev = -1;
  f.caretRev = -1;
  textGeomDirty = true;
  if (!textPlaceOn) notesFocus = true;
}

void notesNudgeSize(int dir) {
  NotesPad pad = selectedPad();
  if (pad == null) return;
  pad.nudgeSize(dir);
}

void nudgeSelectedTextSize(int dir) {
  TextField f = selectedText();
  if (f == null || f.pad == null) return;
  f.pad.nudgeFieldSize(dir);
  textGeomDirty = true;
}

int textFadeAt = 0;

void tickTextFades() {
  int now = millis();
  if (textFadeAt <= 0) {
    textFadeAt = now;
    return;
  }
  float dt = constrain((now - textFadeAt) / TEXT_FADE_MS, 0, 1);
  textFadeAt = now;
  if (dt <= 0) return;
  for (int i = 0; i < textFields.size(); i++) {
    TextField f = textFields.get(i);
    if (f == null) continue;
    float target = f.on ? 1 : 0;
    if (abs(f.fade - target) < 0.001f) {
      f.fade = target;
      continue;
    }
    if (f.fade < target) f.fade = min(1, f.fade + dt);
    else f.fade = max(0, f.fade - dt);
  }
}

void notesFormatForPad(NotesPad pad) {
  if (!textPlaceOn) notesFocus = true;
}

void ensureTextPlate(TextField f, boolean withCaret) {
  if (f == null || f.pad == null) return;
  int tw = textPlateW(f);
  int th = textPlateH(f);
  f.pad.vAlign = f.vAlign;
  boolean blink = withCaret && notesFocus && (millis() / 530) % 2 == 0;
  PImage dest = withCaret ? f.caretImg : f.plate;
  boolean same = dest != null && dest.width == tw && dest.height == th
    && (withCaret
      ? (f.caretRev == f.pad.visualRev && f.caretBlink == blink)
      : f.cacheRev == f.pad.visualRev);
  if (same) return;
  int n = tw * th;
  int[] pix = withCaret ? f.caretPix : f.platePix;
  if (pix == null || pix.length != n) pix = new int[n];
  if (withCaret) f.caretPix = pix;
  else f.platePix = pix;
  f.pad.copyView(pix, tw, th, true, withCaret, blink);
  if (dest == null || dest.width != tw || dest.height != th) dest = createImage(tw, th, ARGB);
  dest.loadPixels();
  java.lang.System.arraycopy(pix, 0, dest.pixels, 0, n);
  dest.updatePixels();
  if (withCaret) {
    f.caretImg = dest;
    f.caretRev = f.pad.visualRev;
    f.caretBlink = blink;
  } else {
    f.plate = dest;
    f.cacheRev = f.pad.visualRev;
  }
}

void paintTextFields(PGraphics pg, float ix, float iy, float iw, float ih, boolean interactive) {
  if (pg == null || textFields.isEmpty() || iw < 2 || ih < 2) return;
  pg.pushStyle();
  pg.blendMode(BLEND);
  pg.imageMode(CORNER);
  pg.rectMode(CORNER);
  pg.noTint();
  TextField sel = selectedText();
  for (int i = 0; i < textFields.size(); i++) {
    TextField f = textFields.get(i);
    if (f == sel) continue;
    paintOneText(pg, f, ix, iy, iw, ih, interactive, false);
  }
  if (sel != null) paintOneText(pg, sel, ix, iy, iw, ih, interactive, true);
  pg.popStyle();
}

void paintOneText(PGraphics pg, TextField f, float ix, float iy, float iw, float ih,
                  boolean interactive, boolean selected) {
  if (f == null || f.pad == null || !textShown(f)) return;
  boolean empty = f.pad.isEmpty();
  // Caret goes out with the field (Syphon / beamer), not only on the preview.
  boolean showCaret = selected && notesFocus && !textPlaceOn && notesModeOn();
  if (!interactive && empty && !showCaret) return;
  float dw = iw * f.bw * f.scale;
  float dh = ih * f.bh * f.scale;
  if (dw < 2 || dh < 2) return;
  boolean focused = showCaret;
  if (!empty || focused) {
    if (focused) f.pad.ensureCaretVisible(textPlateH(f));
    ensureTextPlate(f, false);
    if (focused) ensureTextPlate(f, true);
  }
  PImage img = (focused && f.caretImg != null) ? f.caretImg : f.plate;
  int bus = liveBusAlpha();
  int a = round(bus * constrain(f.fade, 0, 1));
  pg.pushMatrix();
  pg.translate(ix + f.cx * iw, iy + f.cy * ih);
  pg.rotate(radians(f.rot));
  if (a > 0 && img != null && (!empty || focused)) {
    if (a < 255) pg.tint(255, a);
    pg.image(img, -dw * 0.5f, -dh * 0.5f, dw, dh);
    if (a < 255) pg.noTint();
  } else if (a > 0 && interactive && empty && selected) {
    pg.fill(DIM, a);
    pg.noStroke();
    pg.textAlign(CENTER, CENTER);
    pg.textFont(font12, 13);
    pg.text("Text", 0, 0);
  }
  pg.popMatrix();
  int boxA = round(255 * constrain(f.fade, 0, 1));
  if (interactive && selected && pg == g && boxA > 0) {
    pg.noFill();
    pg.stroke(textPlaceOn ? ACCENT : INK, boxA);
    pg.strokeWeight(1.25f);
    pg.strokeJoin(ROUND);
    drawTextBounds(pg, ix + f.cx * iw, iy + f.cy * ih, dw, dh, f.rot, ix + 1, iy + 1, iw - 2, ih - 2);
  }
}

float[] boxAx = new float[12];
float[] boxAy = new float[12];
float[] boxBx = new float[12];
float[] boxBy = new float[12];

/** Desktop-only outline, cut to the preview rectangle. */
void drawTextBounds(PGraphics pg, float cx, float cy, float dw, float dh, float rot,
                    float clipX, float clipY, float clipW, float clipH) {
  if (pg == null || dw < 2 || dh < 2 || clipW < 2 || clipH < 2) return;
  float hw = dw * 0.5f;
  float hh = dh * 0.5f;
  float a = radians(rot);
  float c = cos(a);
  float s = sin(a);
  boxAx[0] = cx - hw * c + hh * s;
  boxAy[0] = cy - hw * s - hh * c;
  boxAx[1] = cx + hw * c + hh * s;
  boxAy[1] = cy + hw * s - hh * c;
  boxAx[2] = cx + hw * c - hh * s;
  boxAy[2] = cy + hw * s + hh * c;
  boxAx[3] = cx - hw * c - hh * s;
  boxAy[3] = cy - hw * s + hh * c;
  int n = clipTextBox(4, clipX, clipY, clipX + clipW, clipY + clipH);
  if (n < 2) return;
  pg.beginShape();
  for (int i = 0; i < n; i++) pg.vertex(boxAx[i], boxAy[i]);
  pg.endShape(CLOSE);
}

int clipTextBox(int n, float minX, float minY, float maxX, float maxY) {
  n = clipTextEdge(boxAx, boxAy, n, boxBx, boxBy, 0, minX);
  n = clipTextEdge(boxBx, boxBy, n, boxAx, boxAy, 1, maxX);
  n = clipTextEdge(boxAx, boxAy, n, boxBx, boxBy, 2, minY);
  n = clipTextEdge(boxBx, boxBy, n, boxAx, boxAy, 3, maxY);
  return n;
}

int clipTextEdge(float[] ix, float[] iy, int n, float[] ox, float[] oy, int edge, float lim) {
  if (n < 2) return 0;
  int m = 0;
  for (int i = 0; i < n; i++) {
    int j = (i + 1) % n;
    float x0 = ix[i];
    float y0 = iy[i];
    float x1 = ix[j];
    float y1 = iy[j];
    boolean in0 = textBoxInside(x0, y0, edge, lim);
    boolean in1 = textBoxInside(x1, y1, edge, lim);
    if (in0 && in1) {
      if (m >= ox.length) break;
      ox[m] = x1;
      oy[m] = y1;
      m++;
    } else if (in0 != in1) {
      float dx = x1 - x0;
      float dy = y1 - y0;
      float t = 0;
      if (edge < 2) {
        if (abs(dx) < 1e-6f) continue;
        t = (lim - x0) / dx;
      } else {
        if (abs(dy) < 1e-6f) continue;
        t = (lim - y0) / dy;
      }
      if (m >= ox.length) break;
      ox[m] = x0 + dx * t;
      oy[m] = y0 + dy * t;
      m++;
      if (in1) {
        if (m >= ox.length) break;
        ox[m] = x1;
        oy[m] = y1;
        m++;
      }
    }
  }
  return m;
}

boolean textBoxInside(float x, float y, int edge, float lim) {
  if (edge == 0) return x >= lim - 0.5f;
  if (edge == 1) return x <= lim + 0.5f;
  if (edge == 2) return y >= lim - 0.5f;
  return y <= lim + 0.5f;
}

void drawTextOverlay(float ix, float iy, float iw, float ih) {
  if (notesViewOn()) {
    paintTextFields(g, ix, iy, iw, ih, true);
    drawTextLineGesture(ix, iy, iw, ih);
    return;
  }
  if (!notesPreviewOn && !feedOnAir) return;
  paintTextFields(g, ix, iy, iw, ih, false);
}

/** Place is on: Space records instead of typing or driving Stoptrick. */
boolean textPlaceRecords() {
  return notesModeOn() && textPlaceOn;
}

boolean textHasContent() {
  for (int i = 0; i < textFields.size(); i++) {
    TextField f = textFields.get(i);
    if (f.pad == null || !textShown(f)) continue;
    if (!f.pad.isEmpty()) return true;
    if (i == textSel && notesFocus && !textPlaceOn && notesModeOn()) return true;
  }
  return false;
}

boolean textHasOutput() {
  return feedOnAir && textHasContent();
}

/** Text is burned into the take only when Record into loop is on. */
boolean textWouldRecord() {
  if (!textRecordOn) return false;
  if (!notesModeOn() && !feedOnAir && !notesPreviewOn) return false;
  for (int i = 0; i < textFields.size(); i++) {
    TextField f = textFields.get(i);
    if (textShown(f) && f.pad != null && !f.pad.isEmpty()) return true;
  }
  return false;
}

PImage recTextPlate;
int[] recStampPixels;

/** Burn the current fields — scale, rotation, position — into a record frame. */
int[] stampTextOnRecord(int[] src) {
  if (src == null || !textWouldRecord()) return src;
  int n = capW * capH;
  if (src.length < n) return src;
  if (recTextPlate == null || recTextPlate.width != capW || recTextPlate.height != capH) {
    recTextPlate = createImage(capW, capH, ARGB);
  }
  recTextPlate.loadPixels();
  arrayCopy(src, 0, recTextPlate.pixels, 0, n);
  recTextPlate.updatePixels();
  feedCompGfx = ensureFrame(feedCompGfx);
  feedCompGfx.beginDraw();
  feedCompGfx.background(0);
  feedCompGfx.blendMode(BLEND);
  feedCompGfx.noTint();
  feedCompGfx.image(recTextPlate, 0, 0, capW, capH);
  paintTextFields(feedCompGfx, 0, 0, capW, capH, false);
  feedCompGfx.endDraw();
  if (recStampPixels == null || recStampPixels.length != n) recStampPixels = new int[n];
  copyFramePixels(feedCompGfx, recStampPixels);
  return recStampPixels;
}

/** Enabled text fields, without the caret, frozen for the MP4 encode. */
void snapshotTextForExport() {
  ArrayList<TextExportSnap> next = new ArrayList<TextExportSnap>();
  for (int i = 0; i < textFields.size(); i++) {
    TextField f = textFields.get(i);
    if (f == null || !textShown(f) || f.pad == null || f.pad.isEmpty()) continue;
    ensureTextPlate(f, false);
    int pw = textPlateW(f);
    int ph = textPlateH(f);
    int n = pw * ph;
    if (f.platePix == null || f.platePix.length < n || pw < 2 || ph < 2) continue;
    TextExportSnap s = new TextExportSnap();
    s.pw = pw;
    s.ph = ph;
    s.cx = f.cx;
    s.cy = f.cy;
    s.rot = f.rot;
    s.scale = f.scale;
    s.bw = f.bw;
    s.bh = f.bh;
    s.fade = constrain(f.fade, 0, 1);
    s.img = new java.awt.image.BufferedImage(pw, ph, java.awt.image.BufferedImage.TYPE_INT_ARGB);
    int[] bank = ((java.awt.image.DataBufferInt) s.img.getRaster().getDataBuffer()).getData();
    if (bank.length < n) continue;
    arrayCopy(f.platePix, 0, bank, 0, n);
    next.add(s);
  }
  textExportSnaps = next;
}

/** Composite the frozen text layers onto one export frame. Safe off the draw thread. */
void burnTextExport(int[] dest, int w, int h) {
  ArrayList<TextExportSnap> snaps = textExportSnaps;
  if (snaps == null || snaps.isEmpty() || dest == null || w < 2 || h < 2) return;
  int n = w * h;
  if (dest.length < n) return;
  if (textExportFrame == null || textExportFrame.getWidth() != w || textExportFrame.getHeight() != h) {
    textExportFrame = new java.awt.image.BufferedImage(w, h, java.awt.image.BufferedImage.TYPE_INT_ARGB);
  }
  int[] bank = ((java.awt.image.DataBufferInt) textExportFrame.getRaster().getDataBuffer()).getData();
  if (bank.length < n) return;
  arrayCopy(dest, 0, bank, 0, n);
  java.awt.Graphics2D g2 = textExportFrame.createGraphics();
  g2.setRenderingHint(java.awt.RenderingHints.KEY_INTERPOLATION, java.awt.RenderingHints.VALUE_INTERPOLATION_BILINEAR);
  g2.setRenderingHint(java.awt.RenderingHints.KEY_RENDERING, java.awt.RenderingHints.VALUE_RENDER_QUALITY);
  for (int i = 0; i < snaps.size(); i++) {
    TextExportSnap s = snaps.get(i);
    if (s == null || s.img == null || s.pw < 2 || s.ph < 2) continue;
    float dw = w * s.bw * s.scale;
    float dh = h * s.bh * s.scale;
    if (dw < 2 || dh < 2) continue;
    java.awt.geom.AffineTransform at = new java.awt.geom.AffineTransform();
    at.translate(s.cx * w, s.cy * h);
    at.rotate(Math.toRadians(s.rot));
    at.translate(-dw * 0.5, -dh * 0.5);
    at.scale(dw / (float) s.pw, dh / (float) s.ph);
    boolean fading = s.fade < 0.995f;
    if (fading) {
      g2.setComposite(java.awt.AlphaComposite.getInstance(
        java.awt.AlphaComposite.SRC_OVER, constrain(s.fade, 0, 1)));
    }
    g2.drawImage(s.img, at, null);
    if (fading) g2.setComposite(java.awt.AlphaComposite.SrcOver);
  }
  g2.dispose();
  arrayCopy(bank, 0, dest, 0, n);
}

PGraphics feedCompGfx;

PImage applyFeedToProgram(PImage program) {
  if (!textHasOutput() || program == null) return program;
  feedCompGfx = ensureFrame(feedCompGfx);
  feedCompGfx.beginDraw();
  feedCompGfx.background(0);
  feedCompGfx.blendMode(BLEND);
  feedCompGfx.noTint();
  feedCompGfx.image(program, 0, 0, capW, capH);
  paintTextFields(feedCompGfx, 0, 0, capW, capH, false);
  feedCompGfx.endDraw();
  return feedCompGfx;
}

String textFieldLabel(TextField f) {
  if (f == null || f.pad == null) return "Text";
  String raw = f.pad.plainText().replace('\r', ' ').replace('\n', ' ').trim();
  if (raw.length() == 0) return "Text " + f.id;
  return raw;
}

void textDupBtn(String id, float x, float y, float s) {
  textMiniBtn(id, "", x, y, s);
  noFill();
  stroke(INK);
  strokeWeight(1);
  rect(x + 6, y + 5, 8, 8, 1);
  rect(x + 9, y + 8, 8, 8, 1);
}

void textMiniBtn(String id, String glyph, float x, float y, float s) {
  hit(id, x, y, s, s);
  noFill();
  stroke(LINE);
  strokeWeight(1);
  rect(x + 0.5, y + 0.5, s - 1, s - 1, 4);
  noStroke();
  fill(INK);
  textAlign(CENTER, CENTER);
  ui(13);
  text(glyph, x + s * 0.5f, y + s * 0.5f - 1);
}

void drawNotesSwatches(NotesPad pad, String idPrefix, float x, float y, float w) {
  float sw = 22;
  float gap = 6;
  float total = pad.swatchCount() * sw + (pad.swatchCount() - 1) * gap;
  float sx0 = x + max(0, (w - total) * 0.5f);
  for (int i = 0; i < pad.swatchCount(); i++) {
    float sx = sx0 + i * (sw + gap);
    int rgb = pad.swatchRgb(i);
    hit(idPrefix + i, sx, y, sw, sw);
    noStroke();
    fill(rgb);
    rect(sx, y, sw, sw, 4);
    if (pad.colorIdx == i) {
      noFill();
      stroke(INK);
      strokeWeight(1.5);
      rect(sx - 1.5, y - 1.5, sw + 3, sw + 3, 4);
      noStroke();
    }
  }
}

float drawTextAlignBar(TextField f, float x, float y, float w) {
  float h = 30;
  float gap = 5;
  float bw = 30;
  float row = 6 * bw + 5 * gap + 8;
  float bx = x + max(0, (w - row) * 0.5f);
  int left = javax.swing.text.StyleConstants.ALIGN_LEFT;
  int center = javax.swing.text.StyleConstants.ALIGN_CENTER;
  int right = javax.swing.text.StyleConstants.ALIGN_RIGHT;
  bx = notesIconBtn("notes-align-l", NICO_ALIGN_L, bx, y, bw, h, f.hAlign == left);
  bx += gap;
  bx = notesIconBtn("notes-align-c", NICO_ALIGN_C, bx, y, bw, h, f.hAlign == center);
  bx += gap;
  bx = notesIconBtn("notes-align-r", NICO_ALIGN_R, bx, y, bw, h, f.hAlign == right);
  bx += gap + 8;
  bx = notesIconBtn("notes-valign-t", NICO_VALIGN_T, bx, y, bw, h, f.vAlign == 0);
  bx += gap;
  bx = notesIconBtn("notes-valign-c", NICO_VALIGN_C, bx, y, bw, h, f.vAlign == 1);
  bx += gap;
  notesIconBtn("notes-valign-b", NICO_VALIGN_B, bx, y, bw, h, f.vAlign == 2);
  return y + h;
}

float drawNotesFormatBar(NotesPad pad, String prefix, float x, float y, float w) {
  pad.syncFormatFromCaret();
  float h = 30;
  float gap = 5;
  float bw = 30;
  float row1 = 2 * bw + gap;
  float bx = x + max(0, (w - row1) * 0.5f);
  bx = notesIconBtn(prefix + "bold", NICO_BOLD, bx, y, bw, h, pad.boldOn);
  bx += gap;
  notesIconBtn(prefix + "italic", NICO_ITALIC, bx, y, bw, h, pad.italicOn);

  float y2 = y + h + 8;
  float row2 = bw + gap + 44 + gap + bw;
  bx = x + max(0, (w - row2) * 0.5f);
  bx = notesIconBtn(prefix + "size-down", NICO_SIZE_DN, bx, y2, bw, h, false);
  bx += gap;
  hit(prefix + "size", bx, y2, 44, h);
  numHit(prefix + "size", bx, y2, 44, h, pad.sizePx, NotesPad.SIZE_MIN, NotesPad.SIZE_MAX);
  boolean sizing = editId != null && editId.equals(prefix + "size");
  noStroke();
  fill(WELL);
  rect(bx, y2, 44, h, 4);
  stroke(sizing ? ACCENT : LINE);
  strokeWeight(1);
  noFill();
  rect(bx + 0.5, y2 + 0.5, 44 - 1, h - 1, 4);
  if (!sizing) {
    noStroke();
    fill(INK);
    textAlign(CENTER, CENTER);
    ui(12);
    text(str(pad.sizePx), bx + 22, y2 + h / 2f - 1);
  }
  bx += 44 + gap;
  notesIconBtn(prefix + "size-up", NICO_SIZE_UP, bx, y2, bw, h, false);
  return y2 + h;
}

float notesIconBtn(String id, int icon, float x, float y, float w, float h, boolean on) {
  hit(id, x, y, w, h);
  noStroke();
  fill(on ? WELL : color(0, 0));
  if (on) rect(x, y, w, h, 4);
  stroke(on ? ACCENT : LINE);
  strokeWeight(1);
  noFill();
  rect(x + 0.5, y + 0.5, w - 1, h - 1, 4);
  color ic = on ? INK : MUTED;
  drawNotesIcon(icon, x, y, w, h, ic);
  return x + w;
}

void drawNotesIcon(int icon, float x, float y, float w, float h, color c) {
  float cx = x + w * 0.5f;
  float cy = y + h * 0.5f;
  stroke(c);
  strokeWeight(1.4);
  strokeCap(SQUARE);
  noFill();
  if (icon == NICO_BOLD) {
    fill(c);
    textAlign(CENTER, CENTER);
    textFont(font12, 15);
    text("B", cx, cy - 1);
    noFill();
  } else if (icon == NICO_ITALIC) {
    fill(c);
    textAlign(CENTER, CENTER);
    textFont(font12, 15);
    pushMatrix();
    translate(cx, cy - 1);
    shearX(-0.25f);
    text("I", 0, 0);
    popMatrix();
    noFill();
  } else if (icon == NICO_ALIGN_L || icon == NICO_ALIGN_C || icon == NICO_ALIGN_R) {
    float left = x + 7;
    float right = x + w - 7;
    float mid = cx;
    float[] lens = {1f, 0.62f, 0.88f, 0.55f};
    float top = y + 8;
    float step = (h - 16) / 3.2f;
    for (int i = 0; i < 4; i++) {
      float len = (right - left) * lens[i];
      float x1, x2;
      if (icon == NICO_ALIGN_L) {
        x1 = left;
        x2 = left + len;
      } else if (icon == NICO_ALIGN_R) {
        x2 = right;
        x1 = right - len;
      } else {
        x1 = mid - len * 0.5f;
        x2 = mid + len * 0.5f;
      }
      line(x1, top + i * step, x2, top + i * step);
    }
  } else if (icon == NICO_VALIGN_T || icon == NICO_VALIGN_C || icon == NICO_VALIGN_B) {
    float left = x + 8;
    float right = x + w - 8;
    float[] lens = {0.92f, 0.62f, 0.78f};
    float step = 3.5f;
    float block = step * 2;
    float innerTop = y + 7;
    float innerBot = y + h - 7;
    float top;
    if (icon == NICO_VALIGN_T) top = innerTop;
    else if (icon == NICO_VALIGN_B) top = innerBot - block;
    else top = innerTop + ((innerBot - innerTop) - block) * 0.5f;
    for (int i = 0; i < 3; i++) {
      float len = (right - left) * lens[i];
      float x1 = left + ((right - left) - len) * 0.5f;
      line(x1, top + i * step, x1 + len, top + i * step);
    }
  } else if (icon == NICO_SIZE_DN) {
    fill(c);
    textAlign(CENTER, CENTER);
    textFont(font10, 11);
    text("A", cx - 3, cy - 1);
    textFont(font10, 9);
    text("−", cx + 7, cy - 1);
    noFill();
  } else if (icon == NICO_SIZE_UP) {
    fill(c);
    textAlign(CENTER, CENTER);
    textFont(font10, 11);
    text("A", cx - 4, cy - 1);
    textFont(font12, 13);
    text("+", cx + 7, cy - 2);
    noFill();
  }
  strokeWeight(1);
}

float drawTextColorPad(TextField f, float x, float cy, float w) {
  float pad = min(w, 140);
  textHslX = x + (w - pad) * 0.5f;
  textHslY = cy;
  textHslW = pad;
  textHslH = pad;
  ensureHslPadImage(max(2, round(pad)), max(2, round(pad)));
  if (hslPadImg != null) image(hslPadImg, textHslX, textHslY, pad, pad);
  else {
    noStroke();
    fill(WELL);
    rect(textHslX, textHslY, pad, pad);
  }
  float sx = textHslX + (f.hue / 360f) * pad;
  float sy = textHslY + (1f - f.light) * pad;
  stroke(PAPER);
  strokeWeight(1);
  noFill();
  ellipse(sx, sy, 10, 10);
  stroke(INK);
  ellipse(sx, sy, 8, 8);
  stroke(LINE);
  noFill();
  rect(textHslX + 0.5, textHslY + 0.5, pad - 1, pad - 1);
  noStroke();
  hit("text-hsl", textHslX, textHslY, pad, pad);
  return cy + pad + 12;
}

float drawFontPicker(TextField f, float x, float y, float w) {
  ensureTextFonts();
  String label = f.fontName != null && f.fontName.length() > 0 ? f.fontName : f.pad.fontFamily;
  hit("text-font", x, y, w, 28);
  noFill();
  stroke(textFontOpen ? ACCENT : LINE);
  strokeWeight(1);
  rect(x + 0.5, y + 0.5, w - 1, 27, 3);
  noStroke();
  fill(INK);
  textAlign(LEFT, CENTER);
  ui(12);
  text(fitText(label, w - 28), x + 10, y + 13);
  fill(MUTED);
  textAlign(RIGHT, CENTER);
  text(textFontOpen ? "▴" : "▾", x + w - 10, y + 12);
  textFontMenuX = x;
  textFontMenuY = y + 30;
  textFontMenuW = w;
  return y + 36;
}

void drawTextFontMenu() {
  if (!textFontOpen || textFontNames == null || textFontNames.length == 0) return;
  float x = textFontMenuX;
  float y = textFontMenuY;
  float w = textFontMenuW;
  float rowH = 26;
  float h = textFontNames.length * rowH + 4;
  noStroke();
  fill(CARD);
  rect(x, y, w, h, 3);
  stroke(LINE);
  strokeWeight(1);
  noFill();
  rect(x + 0.5, y + 0.5, w - 1, h - 1, 3);
  TextField cur = selectedText();
  String face = cur != null && cur.pad != null ? cur.pad.fontFamily : "";
  for (int i = 0; i < textFontNames.length; i++) {
    float ry = y + 2 + i * rowH;
    hit("text-font#" + i, x + 2, ry, w - 4, rowH);
    boolean on = textFontNames[i].equals(face);
    if (on) {
      noStroke();
      fill(WELL);
      rect(x + 2, ry, w - 4, rowH);
    }
    fill(on ? INK : MUTED);
    textAlign(LEFT, CENTER);
    if (textFontFaces != null && i < textFontFaces.length && textFontFaces[i] != null) textFont(textFontFaces[i], 13);
    else ui(12);
    text(fitText(textFontNames[i], w - 20), x + 10, ry + rowH * 0.5f);
  }
  ui(11);
}

float drawTextFieldList(float x, float cy, float w) {
  kicker("FIELDS", x, cy, w);
  float s = 22;
  float by = cy - 16;
  textMiniBtn("text-add", "+", x + w - s, by, s);
  if (selectedText() != null) {
    textDupBtn("text-dup", x + w - s * 2 - 6, by, s);
    textMiniBtn("text-del", "−", x + w - s * 3 - 12, by, s);
  }
  cy += 12;
  if (pendingNotesLoad && textFields.isEmpty()) {
    fill(MUTED);
    ui(11);
    textAlign(LEFT, TOP);
    text("Warming up…", x, cy);
    return cy + 20;
  }
  if (textFields.isEmpty()) {
    fill(MUTED);
    ui(11);
    textAlign(LEFT, TOP);
    text("None yet", x, cy);
    return cy + 20;
  }
  for (int i = 0; i < textFields.size(); i++) {
    cy = drawTextRackRow(textFields.get(i), i, x, cy, w);
  }
  cy += 12;
  button("text-clear", "Delete all", x, cy, w, 28, false);
  return cy + 36;
}

/** Same row language as the FX rack: checkbox toggles, the name selects. */
float drawTextRackRow(TextField f, int index, float x, float y, float w) {
  float rowH = 26;
  boolean focus = index == textSel;
  boolean lit = f != null && f.on;
  if (inClip(y, rowH)) {
    hit("text-sel#" + index, x, y, w, rowH);
    hit("text-on#" + index, x, y, 18, rowH);
  }
  noStroke();
  if (focus || lit) {
    fill(lit ? WELL : color(red(WELL), green(WELL), blue(WELL), 100));
    rect(x - 4, y, w + 8, rowH);
  }
  if (focus) {
    stroke(PLAY);
    strokeWeight(1);
    noFill();
    rect(x - 4.5f, y + 0.5f, w + 9, rowH - 1);
    noStroke();
  }
  stroke(lit ? PLAY : LINE);
  strokeWeight(1);
  noFill();
  rect(x + 2, y + 7, 12, 12);
  if (lit) {
    noStroke();
    fill(PLAY);
    rect(x + 5, y + 10, 6, 6);
  }
  noStroke();
  fill((lit || focus) ? PLAY : MUTED);
  textAlign(LEFT, CENTER);
  ui(11);
  text(fitText(textFieldLabel(f), w - 28), x + 22, y + rowH * 0.5f);
  return y + rowH;
}

float drawNotesPanel(float x, float y, float w, float bottom) {
  float cy = y;
  button("feed-air", feedOnAir ? "ON AIR  ·  clear" : "On air", x, cy, w, 28, feedOnAir);
  cy += 44;
  kicker("TEXT", x, cy, w);
  cy += 18;
  TextField f = selectedText();
  if (f == null) textFontOpen = false;
  if (f != null && f.pad != null) {
    kicker("ALIGN", x, cy, w);
    cy += 14;
    cy = drawTextAlignBar(f, x, cy, w) + 16;

    kicker("COLOR", x, cy, w);
    cy += 14;
    cy = drawTextColorPad(f, x, cy, w) + 4;

    kicker("FONT", x, cy, w);
    cy += 14;
    cy = drawFontPicker(f, x, cy, w) + 8;

    kicker("STYLE", x, cy, w);
    cy += 14;
    cy = drawNotesFormatBar(f.pad, "notes-", x, cy, w) + 16;

    kicker("PLACE", x, cy, w);
    cy += 14;
    check("text-place", "Pinch  ·  rotate  ·  move", x, cy, w, textPlaceOn);
    cy += 28;

    kicker("OUTPUT", x, cy, w);
    cy += 14;
    check("notes-preview", "Show outside Text  (´)", x, cy, w, notesPreviewOn);
    cy += 28;
  } else if (!pendingNotesLoad) {
    fill(DIM);
    ui(10);
    textAlign(LEFT, TOP);
    text("Plus adds a field on the live image.", x, cy, w, 28);
    cy += 36;
  }
  check("text-rec", "Record into loop", x, cy, w, textRecordOn);
  cy += 44;
  cy = drawTextFieldList(x, cy, w);
  drawTextFontMenu();
  return bottom;
}
