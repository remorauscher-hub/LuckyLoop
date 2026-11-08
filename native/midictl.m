#import <jni.h>
#import <CoreMIDI/CoreMIDI.h>
#import <pthread.h>
#import <string.h>
#import <stdlib.h>
#import <stdio.h>

// Lock-free-ish ring of packed MIDI shorts: type, ch, num, val
// type: 0 = CC, 1 = note
#define MQ 256
static int midiQ[MQ * 4];
static volatile int midiQR = 0;
static volatile int midiQW = 0;
static pthread_mutex_t midiMu = PTHREAD_MUTEX_INITIALIZER;

static MIDIClientRef midiClient = 0;
static MIDIPortRef midiInPort = 0;
static int midiStarted = 0;

static void midiOffer(int type, int ch, int num, int val) {
  pthread_mutex_lock(&midiMu);
  int next = (midiQW + 1) % MQ;
  if (next == midiQR) midiQR = (midiQR + 1) % MQ; // drop oldest
  int at = midiQW * 4;
  midiQ[at] = type;
  midiQ[at + 1] = ch & 15;
  midiQ[at + 2] = num & 127;
  midiQ[at + 3] = val & 127;
  midiQW = next;
  pthread_mutex_unlock(&midiMu);
}

static void midiHandleByteStream(const uint8_t *data, int len) {
  static uint8_t run = 0;
  int i = 0;
  while (i < len) {
    uint8_t b = data[i];
    if (b >= 0xF8) { // realtime — ignore
      i++;
      continue;
    }
    if (b >= 0xF0) { // sys common — skip
      run = 0;
      if (b == 0xF0) { // sysex
        while (i < len && data[i] != 0xF7) i++;
        if (i < len) i++;
      } else {
        i++;
      }
      continue;
    }
    uint8_t status;
    if (b & 0x80) {
      status = b;
      run = b;
      i++;
    } else if (run) {
      status = run;
    } else {
      i++;
      continue;
    }
    uint8_t cmd = status & 0xF0;
    uint8_t ch = status & 0x0F;
    int need = 2;
    if (cmd == 0xC0 || cmd == 0xD0) need = 1;
    if (i + need > len) break;
    uint8_t d1 = data[i++];
    uint8_t d2 = (need == 2) ? data[i++] : 0;
    if (cmd == 0xB0) midiOffer(0, ch, d1, d2);
    else if (cmd == 0x90) midiOffer(1, ch, d1, d2);
    else if (cmd == 0x80) midiOffer(1, ch, d1, 0);
  }
}

static void midiReadProc(const MIDIPacketList *pktList, void *refCon, void *srcConn) {
  (void)refCon;
  (void)srcConn;
  if (pktList == NULL || pktList->numPackets == 0) return;
  const MIDIPacket *pkt = &pktList->packet[0];
  for (UInt32 n = 0; n < pktList->numPackets; n++) {
    UInt16 len = pkt->length;
    if (len > 0) {
      // Copy out of the packet — data[] is flexible and must not be passed by fragile ref.
      uint8_t tmp[256];
      UInt16 ncopy = len > 256 ? 256 : len;
      memcpy(tmp, pkt->data, ncopy);
      midiHandleByteStream(tmp, (int)ncopy);
    }
    pkt = MIDIPacketNext(pkt);
  }
}

static void midiConnectAllSources(void) {
  if (!midiInPort) return;
  ItemCount n = MIDIGetNumberOfSources();
  for (ItemCount i = 0; i < n; i++) {
    MIDIEndpointRef src = MIDIGetSource(i);
    if (src) MIDIPortConnectSource(midiInPort, src, NULL);
  }
}

JNIEXPORT jint JNICALL Java_MidiCtl_start(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  if (midiStarted) {
    midiConnectAllSources();
    return 1;
  }
  OSStatus err = MIDIClientCreate(CFSTR("LuckyLoopMIDI"), NULL, NULL, &midiClient);
  if (err != noErr) return 0;
  err = MIDIInputPortCreate(midiClient, CFSTR("LuckyLoopIn"), midiReadProc, NULL, &midiInPort);
  if (err != noErr) return 0;
  midiConnectAllSources();
  midiStarted = 1;
  return 1;
}

JNIEXPORT void JNICALL Java_MidiCtl_stop(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  if (midiInPort) {
    MIDIPortDispose(midiInPort);
    midiInPort = 0;
  }
  if (midiClient) {
    MIDIClientDispose(midiClient);
    midiClient = 0;
  }
  midiStarted = 0;
}

JNIEXPORT void JNICALL Java_MidiCtl_refresh(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  if (!midiStarted) {
    Java_MidiCtl_start(env, cls);
    return;
  }
  midiConnectAllSources();
}

JNIEXPORT jint JNICALL Java_MidiCtl_poll(JNIEnv *env, jclass cls, jintArray out) {
  (void)cls;
  if (out == NULL) return 0;
  jsize cap = (*env)->GetArrayLength(env, out);
  if (cap < 4) return 0;
  jint *buf = (*env)->GetIntArrayElements(env, out, NULL);
  if (buf == NULL) return 0;
  int written = 0;
  pthread_mutex_lock(&midiMu);
  while (midiQR != midiQW && written + 4 <= (int)cap) {
    int at = midiQR * 4;
    buf[written++] = midiQ[at];
    buf[written++] = midiQ[at + 1];
    buf[written++] = midiQ[at + 2];
    buf[written++] = midiQ[at + 3];
    midiQR = (midiQR + 1) % MQ;
  }
  pthread_mutex_unlock(&midiMu);
  (*env)->ReleaseIntArrayElements(env, out, buf, 0);
  return written / 4;
}

JNIEXPORT jint JNICALL Java_MidiCtl_sourceCount(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  return (jint)MIDIGetNumberOfSources();
}

static jstring midiCfToJString(JNIEnv *env, CFStringRef s) {
  if (env == NULL || s == NULL) return NULL;
  CFIndex len = CFStringGetLength(s);
  CFIndex max = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
  char *buf = (char *)malloc((size_t)max);
  if (buf == NULL) return NULL;
  jstring out = NULL;
  if (CFStringGetCString(s, buf, max, kCFStringEncodingUTF8)) {
    out = (*env)->NewStringUTF(env, buf);
  }
  free(buf);
  return out;
}

/** Display name for CoreMIDI source index, or null. */
JNIEXPORT jstring JNICALL Java_MidiCtl_sourceName(JNIEnv *env, jclass cls, jint index) {
  (void)cls;
  if (index < 0) return NULL;
  ItemCount n = MIDIGetNumberOfSources();
  if ((ItemCount)index >= n) return NULL;
  MIDIEndpointRef src = MIDIGetSource((ItemCount)index);
  if (!src) return NULL;
  CFStringRef name = NULL;
  if (MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name) != noErr || name == NULL) {
    name = NULL;
    MIDIObjectGetStringProperty(src, kMIDIPropertyName, &name);
  }
  if (name == NULL) {
    char fallback[64];
    snprintf(fallback, sizeof(fallback), "MIDI source %d", (int)index + 1);
    return (*env)->NewStringUTF(env, fallback);
  }
  jstring out = midiCfToJString(env, name);
  CFRelease(name);
  return out;
}
