#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <jni.h>
#import <dlfcn.h>
#import <pthread.h>
#import <math.h>
#import <string.h>

/*
 Absolute finger positions on the built-in trackpad via MultitouchSupport,
 plus NSEvent magnify (pinch) which works even when the GL/NEWT surface
 never sees Apple AWT MagnificationListener events.

 NOTE: MTDeviceStop() SIGBUS-crashes on some macOS 26 builds
 (mt_DeviceUnregisterForHotplugNotifications / PAC). We soft-stop instead:
 leave the device running, ignore callbacks while inactive.
*/

typedef struct { float x, y; } MTPoint;
typedef struct {
  MTPoint pos;
  MTPoint vel;
} MTVector;

typedef struct {
  int frame;
  double timestamp;
  int identifier;
  int state;
  int fingerId;
  int handle;
  MTVector normalized;
  float size;
  int zero1;
  float angle;
  float majorAxis;
  float minorAxis;
  MTVector unknown;
  int zero2[2];
  float unknown1;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallback)(int device, MTTouch *touches, int count, double timestamp, int frame);
typedef CFMutableArrayRef (*MTDeviceCreateListFn)(void);
typedef void (*MTRegisterFn)(MTDeviceRef, MTContactCallback);
typedef void (*MTDeviceStartFn)(MTDeviceRef, int);

enum {
  MT_STATE_END = 4,
  MT_STATE_CANCEL = 5
};

enum { PAD_MAX_TOUCHES = 5 };

static void *mtHandle = NULL;
static MTDeviceCreateListFn mtCreateList = NULL;
static MTRegisterFn mtRegister = NULL;
static MTDeviceStartFn mtStart = NULL;
static MTDeviceRef mtDevice = NULL;
static int mtRunning = 0;   // Java-visible active
static int mtArmed = 0;     // device started once

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static float touchX = 0.5f;
static float touchY = 0.5f;
static int touching = 0;
static int touchCount = 0;
static float touchXs[PAD_MAX_TOUCHES];
static float touchYs[PAD_MAX_TOUCHES];
static int frameHits = 0;

static float pendingMagnify = 0;
static float pendingRotate = 0;
static float pendingScrollX = 0;
static float pendingScrollY = 0;
static id magnifyMonitor = nil;
static id rotateMonitor = nil;
static id scrollMonitor = nil;

static int resolveSymbols(void) {
  if (mtCreateList && mtRegister && mtStart) return 1;
  if (mtHandle == NULL) {
    mtHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
    if (mtHandle == NULL) return 0;
  }
  mtCreateList = (MTDeviceCreateListFn)dlsym(mtHandle, "MTDeviceCreateList");
  mtRegister = (MTRegisterFn)dlsym(mtHandle, "MTRegisterContactFrameCallback");
  mtStart = (MTDeviceStartFn)dlsym(mtHandle, "MTDeviceStart");
  return mtCreateList && mtRegister && mtStart;
}

static int onFrame(int device, MTTouch *touches, int count, double timestamp, int frame) {
  (void)device;
  (void)timestamp;
  (void)frame;
  if (!mtRunning) return 0;
  float xs[PAD_MAX_TOUCHES];
  float ys[PAD_MAX_TOUCHES];
  int n = 0;
  for (int i = 0; i < count && n < PAD_MAX_TOUCHES; i++) {
    int st = touches[i].state;
    if (st == MT_STATE_END || st == MT_STATE_CANCEL) continue;
    float nx = touches[i].normalized.pos.x;
    float ny = touches[i].normalized.pos.y;
    // Keep slightly out-of-range contacts — pinch near pad edges is common.
    if (nx < -0.2f || nx > 1.2f || ny < -0.2f || ny > 1.2f) continue;
    xs[n] = nx;
    ys[n] = ny;
    n++;
  }
  pthread_mutex_lock(&lock);
  touchCount = n;
  touching = n > 0 ? 1 : 0;
  if (n > 0) {
    touchX = xs[0];
    touchY = ys[0];
    frameHits++;
    for (int i = 0; i < n; i++) {
      touchXs[i] = xs[i];
      touchYs[i] = ys[i];
    }
  }
  pthread_mutex_unlock(&lock);
  return 0;
}

static MTDeviceRef firstTrackpad(void) {
  if (!resolveSymbols()) return NULL;
  CFMutableArrayRef list = mtCreateList();
  if (list == NULL) return NULL;
  CFIndex n = CFArrayGetCount(list);
  MTDeviceRef chosen = NULL;
  if (n > 0) {
    chosen = (MTDeviceRef)CFArrayGetValueAtIndex(list, 0);
  }
  static CFMutableArrayRef kept = NULL;
  if (kept == NULL) kept = list;
  else CFRelease(list);
  return chosen;
}

static void installGestureMonitorsOnMain(void) {
  if (magnifyMonitor == nil) {
    magnifyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMagnify
                                                           handler:^NSEvent *(NSEvent *event) {
      float m = (float)[event magnification];
      if (fabsf(m) > 0.00001f) {
        pthread_mutex_lock(&lock);
        pendingMagnify += m;
        pthread_mutex_unlock(&lock);
      }
      return event;
    }];
  }
  if (rotateMonitor == nil) {
    rotateMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskRotate
                                                          handler:^NSEvent *(NSEvent *event) {
      float r = (float)[event rotation];
      if (fabsf(r) > 0.0001f) {
        pthread_mutex_lock(&lock);
        pendingRotate += r;
        pthread_mutex_unlock(&lock);
      }
      return event;
    }];
  }
  // Two-finger trackpad drag → precise scroll deltas (pan). Mouse wheels ignored.
  if (scrollMonitor == nil) {
    scrollMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel
                                                          handler:^NSEvent *(NSEvent *event) {
      if ([event hasPreciseScrollingDeltas]) {
        float dx = (float)[event scrollingDeltaX];
        float dy = (float)[event scrollingDeltaY];
        if (fabsf(dx) > 0.0001f || fabsf(dy) > 0.0001f) {
          pthread_mutex_lock(&lock);
          pendingScrollX += dx;
          pendingScrollY += dy;
          pthread_mutex_unlock(&lock);
        }
      }
      return event;
    }];
  }
}

static void ensureMagnifyMonitor(void) {
  if ([NSThread isMainThread]) {
    installGestureMonitorsOnMain();
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    installGestureMonitorsOnMain();
  });
}

static void clearMagnifyMonitor(void) {
  void (^clear)(void) = ^{
    if (magnifyMonitor != nil) {
      [NSEvent removeMonitor:magnifyMonitor];
      magnifyMonitor = nil;
    }
    if (rotateMonitor != nil) {
      [NSEvent removeMonitor:rotateMonitor];
      rotateMonitor = nil;
    }
    if (scrollMonitor != nil) {
      [NSEvent removeMonitor:scrollMonitor];
      scrollMonitor = nil;
    }
  };
  if ([NSThread isMainThread]) clear();
  else dispatch_sync(dispatch_get_main_queue(), clear);
}

JNIEXPORT jint JNICALL Java_PadCtl_start(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  if (mtRunning) {
    ensureMagnifyMonitor();
    return 1;
  }
  if (!resolveSymbols()) {
    // Still try magnify — pinch can work without MultitouchSupport.
    ensureMagnifyMonitor();
    mtRunning = 1;
    return 1;
  }
  if (!mtArmed) {
    mtDevice = firstTrackpad();
    if (mtDevice != NULL) {
      mtRegister(mtDevice, onFrame);
      mtStart(mtDevice, 0);
      mtArmed = 1;
    }
  }
  ensureMagnifyMonitor();
  mtRunning = 1;
  pthread_mutex_lock(&lock);
  touching = 0;
  touchCount = 0;
  frameHits = 0;
  pendingMagnify = 0;
  pendingRotate = 0;
  pendingScrollX = 0;
  pendingScrollY = 0;
  pthread_mutex_unlock(&lock);
  return 1;
}

JNIEXPORT void JNICALL Java_PadCtl_stop(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  mtRunning = 0;
  clearMagnifyMonitor();
  pthread_mutex_lock(&lock);
  touching = 0;
  touchCount = 0;
  pendingMagnify = 0;
  pendingRotate = 0;
  pendingScrollX = 0;
  pendingScrollY = 0;
  pthread_mutex_unlock(&lock);
}

JNIEXPORT jint JNICALL Java_PadCtl_poll(JNIEnv *env, jclass cls, jfloatArray out) {
  (void)cls;
  float x, y;
  int down;
  pthread_mutex_lock(&lock);
  x = touchX;
  y = touchY;
  down = touching && mtRunning;
  pthread_mutex_unlock(&lock);
  if (out != NULL && (*env)->GetArrayLength(env, out) >= 2) {
    jfloat vals[2] = { x, y };
    (*env)->SetFloatArrayRegion(env, out, 0, 2, vals);
  }
  return down ? 1 : 0;
}

JNIEXPORT jint JNICALL Java_PadCtl_pollAll(JNIEnv *env, jclass cls, jfloatArray out) {
  (void)cls;
  float xs[PAD_MAX_TOUCHES];
  float ys[PAD_MAX_TOUCHES];
  int n;
  pthread_mutex_lock(&lock);
  n = (touching && mtRunning) ? touchCount : 0;
  for (int i = 0; i < n; i++) {
    xs[i] = touchXs[i];
    ys[i] = touchYs[i];
  }
  pthread_mutex_unlock(&lock);
  if (out != NULL) {
    jsize len = (*env)->GetArrayLength(env, out);
    int write = n;
    if (write * 2 > len) write = len / 2;
    if (write > 0) {
      jfloat vals[PAD_MAX_TOUCHES * 2];
      for (int i = 0; i < write; i++) {
        vals[i * 2] = xs[i];
        vals[i * 2 + 1] = ys[i];
      }
      (*env)->SetFloatArrayRegion(env, out, 0, write * 2, vals);
    }
    return write;
  }
  return n;
}

/** Returns accumulated magnify delta since last poll and clears it. */
JNIEXPORT jfloat JNICALL Java_PadCtl_pollMagnify(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  float m;
  pthread_mutex_lock(&lock);
  m = pendingMagnify;
  pendingMagnify = 0;
  pthread_mutex_unlock(&lock);
  return m;
}

/** Returns accumulated rotate delta in degrees since last poll and clears it. */
JNIEXPORT jfloat JNICALL Java_PadCtl_pollRotate(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  float r;
  pthread_mutex_lock(&lock);
  r = pendingRotate;
  pendingRotate = 0;
  pthread_mutex_unlock(&lock);
  return r;
}

/**
 * out[0]=dx, out[1]=dy in points (AppKit scrollingDelta, natural direction).
 * Returns 1 if any delta was pending (then clears).
 */
JNIEXPORT jint JNICALL Java_PadCtl_pollScroll(JNIEnv *env, jclass cls, jfloatArray out) {
  (void)cls;
  float dx, dy;
  pthread_mutex_lock(&lock);
  dx = pendingScrollX;
  dy = pendingScrollY;
  pendingScrollX = 0;
  pendingScrollY = 0;
  pthread_mutex_unlock(&lock);
  if (out != NULL && (*env)->GetArrayLength(env, out) >= 2) {
    jfloat vals[2] = { dx, dy };
    (*env)->SetFloatArrayRegion(env, out, 0, 2, vals);
  }
  return (fabsf(dx) > 0.0001f || fabsf(dy) > 0.0001f) ? 1 : 0;
}
