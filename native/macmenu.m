#import <jni.h>
#import <AppKit/AppKit.h>

static volatile int pendingAction = 0;
static NSMutableArray<NSString *> *recentTitles = nil;
static NSMutableArray<NSString *> *recentPaths = nil;

@interface LLMenuTarget : NSObject
- (void)pick:(id)sender;
@end

@implementation LLMenuTarget
- (void)pick:(id)sender {
  pendingAction = (int)[(NSMenuItem *)sender tag];
}
@end

static LLMenuTarget *menuTarget = nil;

static NSMenuItem *makeItem(NSString *title, NSString *key, NSEventModifierFlags mods, int tag) {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                 action:@selector(pick:)
                                          keyEquivalent:key ?: @""];
  if (mods != 0) item.keyEquivalentModifierMask = mods;
  item.target = menuTarget;
  item.tag = tag;
  item.enabled = YES;
  return item;
}

static void installFileMenu(void) {
  NSMenu *main = [NSApp mainMenu];
  if (main == nil) return;
  if (menuTarget == nil) menuTarget = [LLMenuTarget new];

  // Replace existing File menu so Open Recent stays current.
  for (NSMenuItem *item in [main.itemArray copy]) {
    if ([item.title isEqualToString:@"File"]) [main removeItem:item];
  }

  NSMenu *file = [[NSMenu alloc] initWithTitle:@"File"];
  file.autoenablesItems = NO;

  [file addItem:makeItem(@"New Project…", @"n", NSEventModifierFlagCommand | NSEventModifierFlagShift, 4)];
  [file addItem:makeItem(@"Open Project…", @"o", NSEventModifierFlagCommand, 1)];

  NSMenu *recent = [[NSMenu alloc] initWithTitle:@"Open Recent"];
  recent.autoenablesItems = NO;
  if (recentTitles == nil || recentTitles.count == 0) {
    NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No Recent Projects"
                                                   action:nil
                                            keyEquivalent:@""];
    empty.enabled = NO;
    [recent addItem:empty];
  } else {
    NSUInteger n = MIN((NSUInteger)8, recentTitles.count);
    for (NSUInteger i = 0; i < n; i++) {
      NSMenuItem *item = makeItem(recentTitles[i], @"", 0, (int)(100 + i));
      [recent addItem:item];
    }
    [recent addItem:[NSMenuItem separatorItem]];
    [recent addItem:makeItem(@"Clear Menu", @"", 0, 5)];
  }
  NSMenuItem *recentTop = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
  recentTop.submenu = recent;
  [file addItem:recentTop];

  [file addItem:[NSMenuItem separatorItem]];
  [file addItem:makeItem(@"Save", @"s", NSEventModifierFlagCommand, 3)];
  [file addItem:makeItem(@"Save Project As…", @"s", NSEventModifierFlagCommand | NSEventModifierFlagShift, 6)];
  [file addItem:[NSMenuItem separatorItem]];
  [file addItem:makeItem(@"Show in Finder", @"r", NSEventModifierFlagCommand | NSEventModifierFlagShift, 2)];

  NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
  top.submenu = file;
  NSInteger index = MIN(1, (NSInteger)main.numberOfItems);
  [main insertItem:top atIndex:index];
}

static BOOL isProgramOutWindow(NSWindow *w) {
  if (w == nil) return NO;
  NSString *title = w.title ?: @"";
  // GpuOutput NEWT title: "LuckyLoop · Out"
  if ([title containsString:@"· Out"]) return YES;
  if ([title hasSuffix:@" Out"]) return YES;
  BOOL titled = (w.styleMask & NSWindowStyleMaskTitled) != 0;
  BOOL borderless = (w.styleMask & NSWindowStyleMaskBorderless) != 0 && !titled;
  // Borderless non-primary covering nearly the whole screen → treat as program out.
  if (borderless && w.screen != nil && w.screen != [NSScreen mainScreen]) {
    NSRect sf = w.screen.frame;
    NSRect f = w.frame;
    if (fabs(f.size.width - sf.size.width) < 4.0 && fabs(f.size.height - sf.size.height) < 4.0)
      return YES;
  }
  return NO;
}

/**
 * Cover the menu bar / clock on program-out screens only.
 * Laptop (main editor) keeps the normal menu bar.
 */
static void shieldProgramOut(void) {
  for (NSWindow *w in [NSApp windows]) {
    if (w == nil || !w.isVisible) continue;
    if (!isProgramOutWindow(w)) continue;

    NSScreen *screen = w.screen;
    if (screen == nil) {
      // Prefer a non-main screen whose frame contains the window center.
      NSPoint c = NSMakePoint(NSMidX(w.frame), NSMidY(w.frame));
      for (NSScreen *s in [NSScreen screens]) {
        if (NSPointInRect(c, s.frame)) { screen = s; break; }
      }
    }
    if (screen == nil) continue;

    // Sit above the menu bar so the clock never shows through on the beamer.
    if (w.level < NSMainMenuWindowLevel + 1) {
      w.level = NSMainMenuWindowLevel + 1;
    }
    w.collectionBehavior = NSWindowCollectionBehaviorStationary
      | NSWindowCollectionBehaviorTransient
      | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSRect want = screen.frame; // full display — includes menu-bar strip
    NSRect f = w.frame;
    if (fabs(f.origin.x - want.origin.x) > 0.5
        || fabs(f.origin.y - want.origin.y) > 0.5
        || fabs(f.size.width - want.size.width) > 0.5
        || fabs(f.size.height - want.size.height) > 0.5) {
      [w setFrame:want display:YES animate:NO];
    }
    [w orderFrontRegardless];
  }
}

/** Keep the Mac menu bar (clock) visible on the laptop — never touch program-out. */
static void keepDesktopChrome(void) {
  NSApplicationPresentationOptions hideBits =
      NSApplicationPresentationAutoHideMenuBar
    | NSApplicationPresentationHideMenuBar;
  NSApplicationPresentationOptions cur = [NSApp presentationOptions];
  if ((cur & hideBits) != 0) {
    [NSApp setPresentationOptions:(cur & ~hideBits)];
  }

  for (NSWindow *w in [NSApp windows]) {
    if (w == nil || !w.isVisible) continue;
    if (isProgramOutWindow(w)) continue; // beamer covers its own chrome

    NSString *title = w.title ?: @"";
    BOOL named = [title containsString:@"LuckyLoop"];
    BOOL titled = (w.styleMask & NSWindowStyleMaskTitled) != 0;
    BOOL borderless = (w.styleMask & NSWindowStyleMaskBorderless) != 0 && !titled;
    // Main editor only — skip borderless / utilities.
    if (borderless) continue;
    if (!named || !titled) continue;

    if ((w.styleMask & NSWindowStyleMaskFullScreen) != 0) {
      [w toggleFullScreen:nil];
    }

    NSScreen *screen = w.screen ?: [NSScreen mainScreen];
    if (screen == nil) continue;
    NSRect vis = screen.visibleFrame; // excludes menu bar + Dock
    NSRect f = w.frame;
    BOOL coversMenu = NSMaxY(f) > NSMaxY(vis) + 0.5;
    BOOL tooTall = f.size.height > vis.size.height + 0.5;
    BOOL tooWide = f.size.width > vis.size.width + 0.5;
    if (!coversMenu && !tooTall && !tooWide) continue;

    if (tooWide) f.size.width = vis.size.width;
    if (tooTall || coversMenu) {
      f.size.height = MIN(f.size.height, vis.size.height);
    }
    f.origin.x = vis.origin.x + MAX(0.0, (vis.size.width - f.size.width) * 0.5);
    f.origin.y = NSMaxY(vis) - f.size.height;
    if (f.origin.y < vis.origin.y) f.origin.y = vis.origin.y;
    [w setFrame:f display:YES animate:NO];
  }
}

static void runOnMain(void (^block)(void)) {
  if ([NSThread isMainThread]) block();
  else dispatch_async(dispatch_get_main_queue(), block);
}

JNIEXPORT void JNICALL Java_MacMenu_setRecents(JNIEnv *env, jclass cls, jobjectArray titles, jobjectArray paths) {
  if (recentTitles == nil) recentTitles = [NSMutableArray new];
  if (recentPaths == nil) recentPaths = [NSMutableArray new];
  [recentTitles removeAllObjects];
  [recentPaths removeAllObjects];
  if (titles == NULL || paths == NULL) return;
  jsize n = (*env)->GetArrayLength(env, titles);
  jsize m = (*env)->GetArrayLength(env, paths);
  if (m < n) n = m;
  for (jsize i = 0; i < n; i++) {
    jstring jt = (jstring)(*env)->GetObjectArrayElement(env, titles, i);
    jstring jp = (jstring)(*env)->GetObjectArrayElement(env, paths, i);
    if (jt == NULL || jp == NULL) continue;
    const char *ct = (*env)->GetStringUTFChars(env, jt, NULL);
    const char *cp = (*env)->GetStringUTFChars(env, jp, NULL);
    if (ct && cp) {
      [recentTitles addObject:[NSString stringWithUTF8String:ct]];
      [recentPaths addObject:[NSString stringWithUTF8String:cp]];
    }
    if (ct) (*env)->ReleaseStringUTFChars(env, jt, ct);
    if (cp) (*env)->ReleaseStringUTFChars(env, jp, cp);
  }
}

JNIEXPORT void JNICALL Java_MacMenu_install(JNIEnv *env, jclass cls) {
  runOnMain(^{
    installFileMenu();
    keepDesktopChrome();
  });
}

JNIEXPORT void JNICALL Java_MacMenu_keepDesktopChrome(JNIEnv *env, jclass cls) {
  runOnMain(^{ keepDesktopChrome(); });
}

JNIEXPORT void JNICALL Java_MacMenu_shieldProgramOut(JNIEnv *env, jclass cls) {
  runOnMain(^{ shieldProgramOut(); });
}

JNIEXPORT jint JNICALL Java_MacMenu_poll(JNIEnv *env, jclass cls) {
  int action = pendingAction;
  pendingAction = 0;
  return action;
}
