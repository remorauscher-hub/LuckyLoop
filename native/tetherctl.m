#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <jni.h>
#import <stdatomic.h>
#import <string.h>

#define LT_MAGIC 0x4C546B31u
#define LT_HEADER 12
#define LT_JPEG 1
#define LT_CTRL 2
#define LT_STATUS 3

static nw_browser_t gBrowser;
static nw_connection_t gConn;
static dispatch_queue_t gQueue;
static NSMutableData *gRx;
static atomic_int gRunning;
static atomic_int gConnected;
static char gStatus[256];
static char gPhone[2048];
static NSData *gJpeg;
static int gJpegW, gJpegH;
static uint64_t gFrameSeq;
static NSLock *gLock;

static void setStatus(const char *s) {
  @synchronized ([NSString class]) {
    snprintf(gStatus, sizeof(gStatus), "%s", s ? s : "");
  }
}

static void stopLocked(void) {
  if (gConn) {
    nw_connection_cancel(gConn);
    gConn = nil;
  }
  if (gBrowser) {
    nw_browser_cancel(gBrowser);
    gBrowser = nil;
  }
  atomic_store(&gConnected, 0);
  [gRx setLength:0];
}

static void receiveLocked(void);
static void consumeLocked(void);

static void connectLocked(nw_endpoint_t endpoint) {
  if (gConn) return;
  nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                         NW_PARAMETERS_DEFAULT_CONFIGURATION);
  nw_parameters_set_include_peer_to_peer(params, true);
  gConn = nw_connection_create(endpoint, params);
  nw_connection_set_queue(gConn, gQueue);
  nw_connection_set_state_changed_handler(gConn, ^(nw_connection_state_t state, nw_error_t error) {
    if (state == nw_connection_state_ready) {
      atomic_store(&gConnected, 1);
      [gRx setLength:0];
      setStatus("Tether: LIVE");
      receiveLocked();
    } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
      atomic_store(&gConnected, 0);
      gConn = nil;
      if (atomic_load(&gRunning)) {
        setStatus(error ? "Tether: reconnecting…" : "Tether: disconnected — browsing…");
      }
    }
  });
  setStatus("Tether: connecting…");
  nw_connection_start(gConn);
}

static void receiveLocked(void) {
  if (!gConn) return;
  nw_connection_receive(gConn, 1, 512 * 1024,
    ^(dispatch_data_t content, nw_content_context_t context, bool isComplete, nw_error_t error) {
      (void)context;
      if (error || isComplete) {
        if (gConn) nw_connection_cancel(gConn);
        return;
      }
      if (content) {
        dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset,
                                           const void *buffer, size_t size) {
          (void)region; (void)offset;
          [gRx appendBytes:buffer length:size];
          return true;
        });
        consumeLocked();
      }
      receiveLocked();
    });
}

static uint32_t be32(const uint8_t *b) {
  return ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
}

static void consumeLocked(void) {
  while (gRx.length >= LT_HEADER) {
    const uint8_t *b = (const uint8_t *)gRx.bytes;
    uint32_t magic = be32(b);
    if (magic != LT_MAGIC) {
      [gRx replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
      continue;
    }
    uint8_t type = b[4];
    uint32_t length = be32(b + 8);
    if (length > 8u * 1024u * 1024u) {
      [gRx setLength:0];
      return;
    }
    NSUInteger total = LT_HEADER + (NSUInteger)length;
    if (gRx.length < total) return;
    NSData *payload = [gRx subdataWithRange:NSMakeRange(LT_HEADER, length)];
    [gRx replaceBytesInRange:NSMakeRange(0, total) withBytes:NULL length:0];
    if (type == LT_JPEG) {
      [gLock lock];
      gJpeg = payload;
      gFrameSeq++;
      [gLock unlock];
    } else if (type == LT_STATUS) {
      NSString *s = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
      if (s) {
        snprintf(gPhone, sizeof(gPhone), "%s", s.UTF8String);
      }
    }
  }
}

static void ensureQueue(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    gQueue = dispatch_queue_create("luckytether.jni", DISPATCH_QUEUE_SERIAL);
    gRx = [NSMutableData data];
    gLock = [[NSLock alloc] init];
    setStatus("Tether off");
  });
}

JNIEXPORT void JNICALL Java_TetherNative_start(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  ensureQueue();
  dispatch_sync(gQueue, ^{
    if (atomic_load(&gRunning)) return;
    atomic_store(&gRunning, 1);
    stopLocked();
    nw_browse_descriptor_t desc =
      nw_browse_descriptor_create_bonjour_service("_luckytether._tcp", NULL);
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                           NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_parameters_set_include_peer_to_peer(params, true);
    gBrowser = nw_browser_create(desc, params);
    nw_browser_set_queue(gBrowser, gQueue);
    nw_browser_set_browse_results_changed_handler(gBrowser,
      ^(nw_browse_result_t old_result, nw_browse_result_t new_result, bool batch_complete) {
        (void)old_result; (void)batch_complete;
        if (!atomic_load(&gRunning) || !new_result) return;
        if (gConn) return;
        nw_endpoint_t ep = nw_browse_result_copy_endpoint(new_result);
        if (!ep) return;
        connectLocked(ep);
      });
    setStatus("Tether: browsing…");
    nw_browser_start(gBrowser);
  });
}

JNIEXPORT void JNICALL Java_TetherNative_stop(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  ensureQueue();
  dispatch_sync(gQueue, ^{
    atomic_store(&gRunning, 0);
    stopLocked();
    setStatus("Tether off");
  });
}

JNIEXPORT jboolean JNICALL Java_TetherNative_connected(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  return atomic_load(&gConnected) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL Java_TetherNative_status(JNIEnv *env, jclass cls) {
  (void)cls;
  ensureQueue();
  char buf[256];
  snprintf(buf, sizeof(buf), "%s", gStatus);
  return (*env)->NewStringUTF(env, buf);
}

JNIEXPORT jstring JNICALL Java_TetherNative_phoneStatus(JNIEnv *env, jclass cls) {
  (void)cls;
  ensureQueue();
  char buf[2048];
  snprintf(buf, sizeof(buf), "%s", gPhone);
  return (*env)->NewStringUTF(env, buf);
}

JNIEXPORT jlong JNICALL Java_TetherNative_frameSeq(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  [gLock lock];
  jlong s = (jlong)gFrameSeq;
  [gLock unlock];
  return s;
}

JNIEXPORT jbyteArray JNICALL Java_TetherNative_copyJpeg(JNIEnv *env, jclass cls) {
  (void)cls;
  ensureQueue();
  [gLock lock];
  NSData *jpeg = gJpeg;
  [gLock unlock];
  if (!jpeg || jpeg.length == 0) return NULL;
  jbyteArray arr = (*env)->NewByteArray(env, (jsize)jpeg.length);
  if (!arr) return NULL;
  (*env)->SetByteArrayRegion(env, arr, 0, (jsize)jpeg.length, (const jbyte *)jpeg.bytes);
  return arr;
}

JNIEXPORT void JNICALL Java_TetherNative_sendControl(JNIEnv *env, jclass cls, jstring jjson) {
  (void)cls;
  if (!jjson) return;
  ensureQueue();
  const char *utf = (*env)->GetStringUTFChars(env, jjson, NULL);
  if (!utf) return;
  NSData *payload = [[NSString stringWithUTF8String:utf] dataUsingEncoding:NSUTF8StringEncoding];
  (*env)->ReleaseStringUTFChars(env, jjson, utf);
  if (!payload) return;
  dispatch_async(gQueue, ^{
    if (!gConn || !atomic_load(&gConnected)) return;
    uint8_t header[LT_HEADER] = {0};
    header[0] = (LT_MAGIC >> 24) & 0xff;
    header[1] = (LT_MAGIC >> 16) & 0xff;
    header[2] = (LT_MAGIC >> 8) & 0xff;
    header[3] = LT_MAGIC & 0xff;
    header[4] = LT_CTRL;
    uint32_t len = (uint32_t)payload.length;
    header[8] = (len >> 24) & 0xff;
    header[9] = (len >> 16) & 0xff;
    header[10] = (len >> 8) & 0xff;
    header[11] = len & 0xff;
    NSMutableData *packet = [NSMutableData dataWithBytes:header length:LT_HEADER];
    [packet appendData:payload];
    NSData *owned = [packet copy];
    dispatch_data_t dd = dispatch_data_create(owned.bytes, owned.length, gQueue, ^{
      (void)owned;
    });
    nw_connection_send(gConn, dd, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
                       ^(nw_error_t error) { (void)error; });
  });
}
