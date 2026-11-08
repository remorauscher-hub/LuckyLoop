import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.Rectangle;
import java.awt.RenderingHints;
import java.awt.Shape;
import java.awt.image.BufferedImage;
import java.awt.image.DataBufferInt;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;

import javax.swing.JTextPane;
import javax.swing.text.AttributeSet;
import javax.swing.text.BadLocationException;
import javax.swing.text.DefaultCaret;
import javax.swing.text.Element;
import javax.swing.text.SimpleAttributeSet;
import javax.swing.text.StyleConstants;
import javax.swing.text.StyledDocument;
import javax.swing.text.View;
import javax.swing.text.rtf.RTFEditorKit;

/**
 * Headless Mac-TextEdit-ish RTF pad: standard RTF on disk, painted into GL.
 */
public class NotesPad {
  static final int[] SWATCH_RGB = {
    0xECECEF, // paper white
    0xF0D878, // warm yellow
    0xE09050, // orange
    0xD07068, // signal red
    0x7A9E9A, // chroma green
    0x7AA3C4, // map blue
    0x9A8FB0, // grain purple
    0x1A1A1E  // near black
  };

  final JTextPane pane = new JTextPane();
  final RTFEditorKit kit = new RTFEditorKit();
  final SimpleAttributeSet typing = new SimpleAttributeSet();
  final String fileName;
  final int fontPx;

  BufferedImage buf;
  int bufW, bufH;
  int[] pixels;
  int scrollY = 0;
  int contentH = 1;
  boolean dirty = false;
  public int visualRev = 1;
  /** 0 top, 1 center, 2 bottom — applied when painting, not stored in the RTF. */
  public int vAlign = 1;
  int lastVShift = 0;
  String loadedPath = "";
  int colorIdx = 0;
  boolean boldOn = false;
  boolean italicOn = false;
  public String fontFamily = "Menlo";
  int align = StyleConstants.ALIGN_LEFT;
  int sizePx;
  long lastClickMs = 0;
  int lastClickPos = -1;
  int clickStreak = 0;

  static final int SIZE_MIN = 1;
  static final int SIZE_MAX = 200;
  static final int[] SIZE_STEPS = {1, 5, 8, 12, 14, 16, 18, 24, 32, 42, 56, 72, 96, 128, 160, 200};
  static final Color SEL_BG = new Color(0x3A, 0x55, 0x78, 200);
  static final Color CARET = new Color(0xEC, 0xEC, 0xEF);
  static final Color PAPER_BG = new Color(0x12, 0x12, 0x14);

  // Offscreen view buffer (scrolled window) for caret/selection compositing
  BufferedImage viewBuf;
  int viewBufW, viewBufH;

  public NotesPad() {
    this("notes.rtf", 15);
  }

  public NotesPad(String fileName, int fontPx) {
    this.fileName = (fileName == null || fileName.length() == 0) ? "notes.rtf" : fileName;
    this.fontPx = Math.max(10, fontPx);
    this.sizePx = this.fontPx;
    pane.setEditorKit(kit);
    pane.setDocument(kit.createDefaultDocument());
    pane.setOpaque(true);
    pane.setBackground(PAPER_BG);
    pane.setForeground(new Color(0xEC, 0xEC, 0xEF));
    pane.setCaretColor(CARET);
    pane.setSelectionColor(SEL_BG);
    pane.setSelectedTextColor(new Color(0xEC, 0xEC, 0xEF));
    pane.setFont(new Font("Menlo", Font.PLAIN, this.fontPx));
    pane.setBorder(null);
    pane.setMargin(new java.awt.Insets(28, 36, 28, 36));
    pane.setEditable(true);
    pane.setFocusable(true);
    try {
      DefaultCaret caret = new DefaultCaret() {
        @Override public void setSelectionVisible(boolean vis) {
          super.setSelectionVisible(true);
        }
      };
      caret.setBlinkRate(530);
      caret.setUpdatePolicy(DefaultCaret.ALWAYS_UPDATE);
      pane.setCaret(caret);
      caret.setVisible(true);
      caret.setSelectionVisible(true);
    } catch (Throwable t) {
    }
    applyColorIndex(0, false);
    resetTypingDefaults();
  }

  void resetTypingDefaults() {
    if (fontFamily == null || fontFamily.length() == 0) fontFamily = "Menlo";
    StyleConstants.setFontFamily(typing, fontFamily);
    StyleConstants.setFontSize(typing, sizePx);
    StyleConstants.setBold(typing, boldOn);
    StyleConstants.setItalic(typing, italicOn);
    StyleConstants.setForeground(typing, new Color(SWATCH_RGB[colorIdx]));
    pane.setCharacterAttributes(typing, true);
    applyAlign(align, false);
  }

  public void applyColorIndex(int idx, boolean toSelection) {
    colorIdx = Math.max(0, Math.min(SWATCH_RGB.length - 1, idx));
    setForegroundRgb(SWATCH_RGB[colorIdx], toSelection);
  }

  public void setForegroundRgb(int rgb, boolean toSelection) {
    Color c = new Color(rgb & 0xFFFFFF);
    StyleConstants.setForeground(typing, c);
    applyCharAttr(StyleConstants.Foreground, c, toSelection);
  }

  public int foregroundRgb() {
    try {
      AttributeSet attrs = pane.getCharacterAttributes();
      if (attrs != null) {
        Color fg = StyleConstants.getForeground(attrs);
        if (fg != null) return fg.getRGB() & 0xFFFFFF;
      }
    } catch (Exception e) {
    }
    return 0xFFFFFF;
  }

  public void setFontFamily(String family) {
    if (family == null || family.length() == 0) family = "Menlo";
    fontFamily = family;
    StyleConstants.setFontFamily(typing, family);
    applyCharAttr(StyleConstants.FontFamily, family, true);
  }

  public void toggleBold() {
    boldOn = !boldOn;
    StyleConstants.setBold(typing, boldOn);
    applyCharAttr(StyleConstants.Bold, boldOn ? Boolean.TRUE : Boolean.FALSE, true);
  }

  public void toggleItalic() {
    italicOn = !italicOn;
    StyleConstants.setItalic(typing, italicOn);
    applyCharAttr(StyleConstants.Italic, italicOn ? Boolean.TRUE : Boolean.FALSE, true);
  }

  public void setAlign(int next) {
    if (next != StyleConstants.ALIGN_LEFT
        && next != StyleConstants.ALIGN_CENTER
        && next != StyleConstants.ALIGN_RIGHT) {
      next = StyleConstants.ALIGN_LEFT;
    }
    applyAlign(next, true);
  }

  void applyAlign(int next, boolean mark) {
    align = next;
    SimpleAttributeSet para = new SimpleAttributeSet();
    StyleConstants.setAlignment(para, align);
    int start = pane.getSelectionStart();
    int end = pane.getSelectionEnd();
    StyledDocument doc = (StyledDocument) pane.getDocument();
    doc.setParagraphAttributes(start, Math.max(1, end - start), para, false);
    if (mark) touch();
  }

  /** Align every paragraph — a text field has one block alignment. */
  public void setBlockAlign(int next) {
    if (next != StyleConstants.ALIGN_LEFT
        && next != StyleConstants.ALIGN_CENTER
        && next != StyleConstants.ALIGN_RIGHT) {
      next = StyleConstants.ALIGN_LEFT;
    }
    align = next;
    SimpleAttributeSet para = new SimpleAttributeSet();
    StyleConstants.setAlignment(para, align);
    try {
      StyledDocument doc = (StyledDocument) pane.getDocument();
      doc.setParagraphAttributes(0, Math.max(1, doc.getLength()), para, false);
    } catch (Exception e) {
    }
    touch();
  }

  public void nudgeSize(int dir) {
    int next = dir < 0 ? SIZE_MIN : SIZE_MAX;
    if (dir < 0) {
      for (int i = SIZE_STEPS.length - 1; i >= 0; i--) {
        if (SIZE_STEPS[i] < sizePx) { next = SIZE_STEPS[i]; break; }
      }
    } else {
      for (int i = 0; i < SIZE_STEPS.length; i++) {
        if (SIZE_STEPS[i] > sizePx) { next = SIZE_STEPS[i]; break; }
      }
    }
    setSizePx(next);
  }

  public void setSizePx(int px) {
    sizePx = Math.max(SIZE_MIN, Math.min(SIZE_MAX, px));
    StyleConstants.setFontSize(typing, sizePx);
    applyCharAttr(StyleConstants.FontSize, Integer.valueOf(sizePx), true);
  }

  /** Cmd +/− : one point, every character in the active field, not only the selection. */
  public void nudgeFieldSize(int dir) {
    int px = Math.max(SIZE_MIN, Math.min(SIZE_MAX, sizePx + (dir < 0 ? -1 : 1)));
    sizePx = px;
    StyleConstants.setFontSize(typing, sizePx);
    SimpleAttributeSet a = new SimpleAttributeSet();
    a.addAttribute(StyleConstants.FontSize, Integer.valueOf(sizePx));
    try {
      StyledDocument doc = (StyledDocument) pane.getDocument();
      if (doc.getLength() > 0) doc.setCharacterAttributes(0, doc.getLength(), a, false);
    } catch (Exception e) {
    }
    pane.setCharacterAttributes(typing, false);
    touch();
  }

  void applyCharAttr(Object key, Object value, boolean toSelection) {
    typing.addAttribute(key, value);
    pane.setCharacterAttributes(typing, false);
    if (!toSelection) return;
    StyledDocument doc = (StyledDocument) pane.getDocument();
    int start = pane.getSelectionStart();
    int end = pane.getSelectionEnd();
    // No selection → the whole field, so a title updates when you pick a size or color.
    if (start == end) {
      if (doc.getLength() == 0) return;
      start = 0;
      end = doc.getLength();
    }
    SimpleAttributeSet a = new SimpleAttributeSet();
    a.addAttribute(key, value);
    doc.setCharacterAttributes(start, Math.max(0, end - start), a, false);
    touch();
  }

  /** Sync toolbar state from caret / selection attributes. */
  public void syncFormatFromCaret() {
    AttributeSet attrs = pane.getCharacterAttributes();
    if (attrs != null) {
      boldOn = StyleConstants.isBold(attrs);
      italicOn = StyleConstants.isItalic(attrs);
      int sz = StyleConstants.getFontSize(attrs);
      if (sz > 0) sizePx = sz;
      String fam = StyleConstants.getFontFamily(attrs);
      if (fam != null && fam.length() > 0) fontFamily = fam;
      Color fg = StyleConstants.getForeground(attrs);
      if (fg != null) {
        int rgb = fg.getRGB() & 0xFFFFFF;
        for (int i = 0; i < SWATCH_RGB.length; i++) {
          if (SWATCH_RGB[i] == rgb) {
            colorIdx = i;
            break;
          }
        }
      }
    }
    try {
      int pos = Math.max(0, pane.getCaretPosition() - (pane.getCaretPosition() > 0 ? 1 : 0));
      AttributeSet para = ((StyledDocument) pane.getDocument()).getParagraphElement(pos).getAttributes();
      align = StyleConstants.getAlignment(para);
    } catch (Exception e) {
    }
  }

  public int swatchCount() {
    return SWATCH_RGB.length;
  }

  public int swatchRgb(int i) {
    return SWATCH_RGB[Math.max(0, Math.min(SWATCH_RGB.length - 1, i))];
  }

  public void clear() {
    pane.setDocument(kit.createDefaultDocument());
    boldOn = false;
    italicOn = false;
    align = StyleConstants.ALIGN_LEFT;
    sizePx = fontPx;
    scrollY = 0;
    lastVShift = 0;
    dirty = false;
    visualRev++;
    loadedPath = "";
    resetTypingDefaults();
    invalidateBuf();
  }

  void touch() {
    dirty = true;
    visualRev++;
    invalidateBuf();
  }

  void invalidateBuf() {
    buf = null;
    pixels = null;
    bufW = bufH = 0;
  }

  public boolean isDirty() {
    return dirty;
  }

  public void markDirty() {
    touch();
  }

  public File notesFile(String projectDir) {
    if (projectDir == null || projectDir.length() == 0) return null;
    return new File(projectDir, fileName);
  }

  public void loadFromProject(String projectDir) {
    loadRtf(notesFile(projectDir));
  }

  /** Copy styled text into this pad. Existing glyphs keep their attributes. */
  public void copyDocumentFrom(NotesPad src) {
    if (src == null) return;
    try {
      ByteArrayOutputStream bos = new ByteArrayOutputStream();
      StyledDocument srcDoc = (StyledDocument) src.pane.getDocument();
      src.kit.write(bos, srcDoc, 0, srcDoc.getLength());
      byte[] raw = bos.toByteArray();
      pane.setDocument(kit.createDefaultDocument());
      if (raw.length >= 8) {
        ByteArrayInputStream in = new ByteArrayInputStream(raw);
        try {
          kit.read(in, pane.getDocument(), 0);
        } finally {
          in.close();
        }
      }
      pane.setCaretPosition(0);
      scrollY = 0;
      dirty = true;
      visualRev++;
      invalidateBuf();
      syncFormatFromCaret();
      vAlign = src.vAlign;
      fontFamily = src.fontFamily;
      StyleConstants.setFontFamily(typing, fontFamily);
      StyleConstants.setFontSize(typing, sizePx);
      StyleConstants.setBold(typing, boldOn);
      StyleConstants.setItalic(typing, italicOn);
      StyleConstants.setForeground(typing, new Color(src.foregroundRgb() & 0xFFFFFF));
      pane.setCharacterAttributes(typing, false);
    } catch (Exception e) {
      System.err.println("text copy failed: " + e.getMessage());
    }
  }

  public void loadRtf(File f) {
    clear();
    if (f == null || !f.isFile()) {
      loadedPath = f != null ? f.getAbsolutePath() : "";
      return;
    }
    try {
      FileInputStream in = new FileInputStream(f);
      try {
        pane.setDocument(kit.createDefaultDocument());
        kit.read(in, pane.getDocument(), 0);
      } finally {
        in.close();
      }
      pane.setCaretPosition(0);
      scrollY = 0;
      dirty = false;
      visualRev++;
      loadedPath = f.getAbsolutePath();
      invalidateBuf();
      syncFormatFromCaret();
      resetTypingDefaults();
    } catch (Exception e) {
      System.err.println("text rtf load failed: " + e.getMessage());
      clear();
      loadedPath = f.getAbsolutePath();
    }
  }

  public void saveToProject(String projectDir) {
    saveRtf(notesFile(projectDir));
  }

  public void saveRtf(File f) {
    if (f == null) return;
    try {
      File parent = f.getParentFile();
      if (parent != null) parent.mkdirs();
      // Round-trip through kit so TextEdit opens a normal .rtf
      ByteArrayOutputStream bos = new ByteArrayOutputStream();
      StyledDocument doc = (StyledDocument) pane.getDocument();
      kit.write(bos, doc, 0, doc.getLength());
      byte[] raw = bos.toByteArray();
      if (raw.length < 8) raw = emptyRtfBytes();
      FileOutputStream out = new FileOutputStream(f);
      try {
        out.write(raw);
      } finally {
        out.close();
      }
      dirty = false;
      loadedPath = f.getAbsolutePath();
    } catch (Exception e) {
      System.err.println("text rtf save failed: " + e.getMessage());
    }
  }

  byte[] emptyRtfBytes() {
    int fs = Math.max(20, fontPx * 2); // RTF half-points
    String rtf = "{\\rtf1\\ansi\\deff0\n"
      + "{\\fonttbl{\\f0 Menlo;}}\n"
      + "{\\colortbl;\\red236\\green236\\blue239;}\n"
      + "\\f0\\fs" + fs + "\\cf1\n"
      + "}";
    return rtf.getBytes(java.nio.charset.StandardCharsets.US_ASCII);
  }

  public int getScrollY() {
    return scrollY;
  }

  public int maxScroll(int viewH) {
    return Math.max(0, contentH - Math.max(1, viewH));
  }

  public void setScrollY(int y, int viewH) {
    int next = Math.max(0, Math.min(maxScroll(viewH), y));
    if (next == scrollY) return;
    scrollY = next;
    visualRev++;
  }

  public void nudgeScroll(float wheelCount, int viewH) {
    setScrollY(scrollY + Math.round(wheelCount * 28f), viewH);
  }

  /** Keep caret inside the visible scrolled window (TextEdit-like). */
  public void ensureCaretVisible(int viewH) {
    try {
      Rectangle r = pane.modelToView(pane.getCaretPosition());
      if (r == null) return;
      if (r.y < scrollY) setScrollY(r.y, viewH);
      else if (r.y + r.height > scrollY + viewH) setScrollY(r.y + r.height - viewH, viewH);
    } catch (Exception e) {
    }
  }

  void ensureContentHeight(int viewW) {
    try {
      pane.setSize(viewW, Short.MAX_VALUE / 4);
      java.awt.Dimension pref = pane.getPreferredSize();
      int h = pref != null ? pref.height : 0;
      try {
        View root = pane.getUI().getRootView(pane);
        if (root != null) {
          root.setSize(viewW, Short.MAX_VALUE / 4);
          h = Math.max(h, (int) Math.ceil(root.getPreferredSpan(View.Y_AXIS)));
        }
      } catch (Throwable ignored) {
      }
      contentH = Math.max(fontPx + 4, h);
    } catch (Throwable t) {
      contentH = 200;
    }
  }

  /**
   * Paint scrolled editor view into dest, with TextEdit-like selection + blinking caret.
   * focused+caretOn → draw caret; selection always drawn when present.
   */
  public void copyView(int[] dest, int destW, int destH, boolean transparentBg,
                       boolean focused, boolean caretOn) {
    destW = Math.max(1, destW);
    destH = Math.max(1, destH);
    ensureContentHeight(destW);
    int paintH = Math.max(destH, contentH);
    pane.setSize(destW, paintH);
    pane.setBounds(0, 0, destW, paintH);
    try {
      pane.getUI().getPreferredSize(pane);
      View root = pane.getUI().getRootView(pane);
      if (root != null) root.setSize(destW, paintH);
    } catch (Throwable t) {
    }
    int maxY = Math.max(0, contentH - destH);
    if (scrollY > maxY) scrollY = maxY;
    // Vertical center / bottom only when the block fits. Taller text scrolls from the top.
    int yShift = 0;
    if (vAlign != 0) {
      int extra = destH - contentH;
      if (extra > 0) yShift = (vAlign == 2) ? extra : extra / 2;
    }
    lastVShift = yShift;
    int origin = scrollY - yShift;

    if (viewBuf == null || viewBufW != destW || viewBufH != destH) {
      viewBufW = destW;
      viewBufH = destH;
      viewBuf = new BufferedImage(destW, destH, BufferedImage.TYPE_INT_ARGB);
    }
    Graphics2D g2 = viewBuf.createGraphics();
    try {
      g2.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
      g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
      if (transparentBg) {
        g2.setBackground(new Color(0, 0, 0, 0));
        g2.clearRect(0, 0, destW, destH);
      } else {
        g2.setColor(PAPER_BG);
        g2.fillRect(0, 0, destW, destH);
      }

      // Selection behind glyphs (document space → view via -origin)
      g2.translate(0, -origin);
      paintSelection(g2, destW);
      Shape oldClip = g2.getClip();
      g2.setClip(0, origin, destW, destH);
      try {
        View root = pane.getUI().getRootView(pane);
        if (root != null) {
          root.paint(g2, new Rectangle(0, 0, destW, paintH));
        } else {
          pane.paint(g2);
        }
      } catch (Throwable t) {
        pane.setOpaque(false);
        pane.paint(g2);
      }
      g2.setClip(oldClip);

      if (focused) paintCaret(g2, caretOn);
      g2.translate(0, origin);
    } finally {
      g2.dispose();
    }

    int[] src = ((DataBufferInt) viewBuf.getRaster().getDataBuffer()).getData();
    System.arraycopy(src, 0, dest, 0, destW * destH);
  }

  /** Back-compat: no caret chrome (preview peek / program plate). */
  public void copyView(int[] dest, int destW, int destH, boolean transparentBg) {
    copyView(dest, destW, destH, transparentBg, false, false);
  }

  void paintSelection(Graphics2D g, int viewW) {
    int a = pane.getSelectionStart();
    int b = pane.getSelectionEnd();
    if (a == b) return;
    if (a > b) {
      int t = a;
      a = b;
      b = t;
    }
    StyledDocument doc = (StyledDocument) pane.getDocument();
    g.setColor(SEL_BG);
    try {
      int p = a;
      int guard = 0;
      while (p < b && guard++ < 4096) {
        Element line = doc.getParagraphElement(p);
        int lineStart = line.getStartOffset();
        int lineEnd = line.getEndOffset();
        int ls = Math.max(a, lineStart);
        int le = Math.min(b, lineEnd);
        Rectangle rs = pane.modelToView(ls);
        if (rs == null) {
          p = lineEnd;
          continue;
        }
        int x1 = rs.x;
        int y = rs.y;
        int h = lineBox(ls, rs);
        int x2;
        if (le >= lineEnd) {
          // whole remainder of paragraph line
          x2 = Math.max(x1 + 2, viewW - 4);
        } else if (le > ls) {
          Rectangle re = pane.modelToView(le);
          x2 = re != null ? Math.max(x1 + 2, re.x) : x1 + 8;
        } else {
          x2 = x1 + 2;
        }
        g.fillRect(x1, y, Math.max(2, x2 - x1), h);
        p = lineEnd;
        if (p <= ls) p = ls + 1;
      }
    } catch (Exception e) {
    }
  }

  void paintCaret(Graphics2D g, boolean on) {
    if (!on) return;
    try {
      int pos = pane.getCaretPosition();
      Rectangle r = pane.modelToView(pos);
      if (r == null) return;
      g.setColor(CARET);
      int h = lineBox(pos, r);
      g.fillRect(r.x, r.y, 2, h);
    } catch (Exception e) {
    }
  }

  /** Glyph box. modelToView can return the whole pane after a size change. */
  int lineBox(int pos, Rectangle r) {
    int size = Math.max(SIZE_MIN, sizePx);
    try {
      int len = pane.getDocument().getLength();
      int p = pos;
      if (p > len) p = len;
      if (p > 0 && p == len) p--;
      if (p < 0) p = 0;
      AttributeSet attrs = ((StyledDocument) pane.getDocument()).getCharacterElement(p).getAttributes();
      int sz = StyleConstants.getFontSize(attrs);
      if (sz >= SIZE_MIN && sz < 400) size = sz;
    } catch (Exception e) {
    }
    int h = size + Math.max(2, size / 10);
    // Trust the view box only when it matches the glyph. A size change often
    // reports the whole field as the caret height.
    if (r != null && r.height > 0 && r.height <= h * 1.35f) h = r.height;
    return h;
  }

  /** Insert / edit helpers driven from Processing keys. */
  public boolean typeChar(char ch) {
    if (ch == 0 || ch == java.awt.event.KeyEvent.CHAR_UNDEFINED) return false;
    if (Character.isISOControl(ch) && ch != '\n' && ch != '\t') return false;
    try {
      replaceSelection(String.valueOf(ch));
      touch();
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  public boolean typeKey(int code, boolean shift, boolean meta, boolean alt) {
    try {
      int start = pane.getSelectionStart();
      int end = pane.getSelectionEnd();
      StyledDocument doc = (StyledDocument) pane.getDocument();
      if (code == java.awt.event.KeyEvent.VK_BACK_SPACE) {
        if (start != end) {
          doc.remove(start, end - start);
        } else if (start > 0) {
          doc.remove(start - 1, 1);
          pane.setCaretPosition(start - 1);
        }
        touch();
        return true;
      }
      if (code == java.awt.event.KeyEvent.VK_DELETE) {
        if (start != end) doc.remove(start, end - start);
        else if (start < doc.getLength()) doc.remove(start, 1);
        touch();
        return true;
      }
      if (code == java.awt.event.KeyEvent.VK_ENTER) {
        replaceSelection("\n");
        touch();
        return true;
      }
      if (code == java.awt.event.KeyEvent.VK_LEFT) {
        if (meta) moveLineEdge(false, shift);
        else moveCaret(-1, shift);
        return true;
      }
      if (code == java.awt.event.KeyEvent.VK_RIGHT) {
        if (meta) moveLineEdge(true, shift);
        else moveCaret(1, shift);
        return true;
      }
      if (code == java.awt.event.KeyEvent.VK_UP) {
        if (meta) moveDocEdge(false, shift);
        else moveCaretVertical(-1, shift);
        return true;
      }
      if (code == java.awt.event.KeyEvent.VK_DOWN) {
        if (meta) moveDocEdge(true, shift);
        else moveCaretVertical(1, shift);
        return true;
      }
      if (code == java.awt.event.KeyEvent.VK_HOME) {
        moveLineEdge(false, shift);
        return true;
      }
      if (code == java.awt.event.KeyEvent.VK_END) {
        moveLineEdge(true, shift);
        return true;
      }
      if (meta && (code == java.awt.event.KeyEvent.VK_A)) {
        pane.selectAll();
        return true;
      }
      if (meta && (code == java.awt.event.KeyEvent.VK_C)) {
        pane.copy();
        return true;
      }
      if (meta && (code == java.awt.event.KeyEvent.VK_X)) {
        pane.cut();
        touch();
        return true;
      }
      if (meta && (code == java.awt.event.KeyEvent.VK_V)) {
        pane.paste();
        touch();
        return true;
      }
      if (meta && (code == java.awt.event.KeyEvent.VK_Z)) {
        // no undo stack in rudimentary pad
        return true;
      }
    } catch (Exception e) {
      return false;
    }
    return false;
  }

  void replaceSelection(String s) throws BadLocationException {
    int start = pane.getSelectionStart();
    int end = pane.getSelectionEnd();
    StyledDocument doc = (StyledDocument) pane.getDocument();
    AttributeSet attrs = pane.getInputAttributes();
    if (start != end) doc.remove(start, end - start);
    doc.insertString(start, s, attrs != null ? attrs.copyAttributes() : typing.copyAttributes());
    pane.setCaretPosition(start + s.length());
  }

  void moveCaret(int delta, boolean shift) {
    int pos = pane.getCaretPosition();
    int next = Math.max(0, Math.min(pane.getDocument().getLength(), pos + delta));
    if (shift) {
      int mark = pane.getCaret().getMark();
      pane.setCaretPosition(mark);
      pane.moveCaretPosition(next);
    } else {
      pane.setCaretPosition(next);
    }
    syncFormatFromCaret();
  }

  void moveLineEdge(boolean end, boolean shift) {
    try {
      StyledDocument doc = (StyledDocument) pane.getDocument();
      Element line = doc.getParagraphElement(pane.getCaretPosition());
      int next = end
        ? Math.min(doc.getLength(), Math.max(line.getStartOffset(), line.getEndOffset() - 1))
        : line.getStartOffset();
      if (shift) {
        int mark = pane.getCaret().getMark();
        pane.setCaretPosition(mark);
        pane.moveCaretPosition(next);
      } else {
        pane.setCaretPosition(next);
      }
      syncFormatFromCaret();
    } catch (Exception e) {
    }
  }

  void moveDocEdge(boolean end, boolean shift) {
    int next = end ? pane.getDocument().getLength() : 0;
    if (shift) {
      int mark = pane.getCaret().getMark();
      pane.setCaretPosition(mark);
      pane.moveCaretPosition(next);
    } else {
      pane.setCaretPosition(next);
    }
    syncFormatFromCaret();
  }

  void moveCaretVertical(int dir, boolean shift) {
    try {
      int pos = pane.getCaretPosition();
      Rectangle r = pane.modelToView(pos);
      if (r == null) {
        moveCaret(dir * 20, shift);
        return;
      }
      int y = r.y + dir * Math.max(16, r.height);
      int x = r.x;
      int next = pane.viewToModel(new java.awt.Point(x, y));
      if (next < 0) next = dir < 0 ? 0 : pane.getDocument().getLength();
      if (shift) {
        int mark = pane.getCaret().getMark();
        pane.setCaretPosition(mark);
        pane.moveCaretPosition(next);
      } else {
        pane.setCaretPosition(next);
      }
      syncFormatFromCaret();
    } catch (Exception e) {
      moveCaret(dir * 20, shift);
    }
  }

  public void clickAt(float localX, float localY, boolean extend) {
    clickAt(localX, localY, extend, 1);
  }

  public void clickAt(float localX, float localY, boolean extend, int clickCount) {
    try {
      int y = Math.round(localY) + scrollY - lastVShift;
      int x = Math.round(localX);
      int pos = pane.viewToModel(new java.awt.Point(x, y));
      if (pos < 0) return;
      visualRev++;
      long now = System.currentTimeMillis();
      if (!extend && clickCount <= 1) {
        if (now - lastClickMs < 450 && Math.abs(pos - lastClickPos) <= 1) {
          clickStreak++;
        } else {
          clickStreak = 1;
        }
        lastClickMs = now;
        lastClickPos = pos;
      } else if (extend) {
        clickStreak = 1;
      } else {
        clickStreak = Math.max(1, clickCount);
      }

      int streak = Math.max(clickStreak, clickCount);
      if (!extend && streak >= 3) {
        selectLine(pos);
        return;
      }
      if (!extend && streak >= 2) {
        selectWord(pos);
        return;
      }
      if (extend) {
        int mark = pane.getCaret().getMark();
        pane.setCaretPosition(mark);
        pane.moveCaretPosition(pos);
      } else {
        pane.setCaretPosition(pos);
        pane.moveCaretPosition(pos);
      }
      syncFormatFromCaret();
    } catch (Exception e) {
    }
  }

  void selectWord(int pos) {
    try {
      StyledDocument doc = (StyledDocument) pane.getDocument();
      String text = doc.getText(0, doc.getLength());
      int n = text.length();
      int p = Math.max(0, Math.min(n, pos));
      if (n == 0) {
        pane.setCaretPosition(0);
        return;
      }
      if (p >= n) p = n - 1;
      int a = p;
      int b = p;
      if (Character.isWhitespace(text.charAt(p))) {
        while (a > 0 && Character.isWhitespace(text.charAt(a - 1))) a--;
        while (b < n && Character.isWhitespace(text.charAt(b))) b++;
      } else {
        while (a > 0 && isWordChar(text.charAt(a - 1))) a--;
        while (b < n && isWordChar(text.charAt(b))) b++;
      }
      pane.setCaretPosition(a);
      pane.moveCaretPosition(b);
      syncFormatFromCaret();
    } catch (Exception e) {
    }
  }

  void selectLine(int pos) {
    try {
      StyledDocument doc = (StyledDocument) pane.getDocument();
      Element line = doc.getParagraphElement(pos);
      int a = line.getStartOffset();
      int b = Math.min(doc.getLength(), line.getEndOffset());
      pane.setCaretPosition(a);
      pane.moveCaretPosition(b);
      syncFormatFromCaret();
    } catch (Exception e) {
    }
  }

  static boolean isWordChar(char c) {
    return Character.isLetterOrDigit(c) || c == '_' || c == '-';
  }

  public boolean hasSelection() {
    return pane.getSelectionStart() != pane.getSelectionEnd();
  }

  public int caretPos() {
    return pane.getCaretPosition();
  }

  public boolean isEmpty() {
    return pane.getDocument().getLength() == 0;
  }

  /** Plain text for empty-state checks / fallback overlay. */
  public String plainText() {
    try {
      return pane.getDocument().getText(0, pane.getDocument().getLength());
    } catch (Exception e) {
      return "";
    }
  }
}
