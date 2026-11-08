#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <jni.h>
#import <stdatomic.h>
#import <string.h>

static VTDecompressionSessionRef gSession;
static CMVideoFormatDescriptionRef gFormat;
static NSLock *gLock;
static int gW, gH;
static int *gPixels;
static int gCap;
static uint64_t gSeq;
static uint8_t *gSps;
static size_t gSpsLen;
static uint8_t *gPps;
static size_t gPpsLen;
static BOOL gReady;

static void ensureLock(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{ gLock = [[NSLock alloc] init]; });
}

static void freeParam(uint8_t **p, size_t *n) {
  if (*p) free(*p);
  *p = NULL;
  *n = 0;
}

static void resetLocked(void) {
  if (gSession) {
    VTDecompressionSessionInvalidate(gSession);
    CFRelease(gSession);
    gSession = NULL;
  }
  if (gFormat) {
    CFRelease(gFormat);
    gFormat = NULL;
  }
  freeParam(&gSps, &gSpsLen);
  freeParam(&gPps, &gPpsLen);
  gReady = NO;
}

static void storeNal(uint8_t **dst, size_t *dstLen, const uint8_t *src, size_t len) {
  freeParam(dst, dstLen);
  if (!src || len == 0) return;
  *dst = (uint8_t *)malloc(len);
  if (!*dst) return;
  memcpy(*dst, src, len);
  *dstLen = len;
}

static BOOL rebuildSessionLocked(void) {
  if (gSession) {
    VTDecompressionSessionInvalidate(gSession);
    CFRelease(gSession);
    gSession = NULL;
  }
  if (gFormat) {
    CFRelease(gFormat);
    gFormat = NULL;
  }
  if (!gSps || !gPps || gSpsLen < 4 || gPpsLen < 2) return NO;

  const uint8_t *sets[2] = { gSps, gPps };
  const size_t sizes[2] = { gSpsLen, gPpsLen };
  OSStatus st = CMVideoFormatDescriptionCreateFromH264ParameterSets(
    kCFAllocatorDefault, 2, sets, sizes, 4, &gFormat);
  if (st != noErr || !gFormat) return NO;

  NSDictionary *dest = @{
    (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
  };
  VTDecompressionOutputCallbackRecord cb = {0};
  st = VTDecompressionSessionCreate(
    kCFAllocatorDefault, gFormat, NULL, (__bridge CFDictionaryRef)dest, &cb, &gSession);
  if (st != noErr || !gSession) {
    CFRelease(gFormat);
    gFormat = NULL;
    return NO;
  }
  gReady = YES;
  return YES;
}

typedef struct {
  const uint8_t *ptr;
  size_t len;
  int type;
} Nal;

static size_t startCodeLen(const uint8_t *b, size_t n, size_t i) {
  if (i + 3 < n && b[i] == 0 && b[i + 1] == 0 && b[i + 2] == 1) return 3;
  if (i + 4 < n && b[i] == 0 && b[i + 1] == 0 && b[i + 2] == 0 && b[i + 3] == 1) return 4;
  return 0;
}

static int collectNals(const uint8_t *data, size_t len, Nal *out, int maxOut) {
  int count = 0;
  size_t i = 0;
  while (i + 3 < len && count < maxOut) {
    size_t sc = startCodeLen(data, len, i);
    if (sc == 0) { i++; continue; }
    size_t nalStart = i + sc;
    size_t j = nalStart;
    while (j < len) {
      size_t nsc = startCodeLen(data, len, j);
      if (nsc) break;
      j++;
    }
    if (nalStart < j) {
      out[count].ptr = data + nalStart;
      out[count].len = j - nalStart;
      out[count].type = out[count].ptr[0] & 0x1f;
      count++;
    }
    i = j;
  }
  return count;
}

static void copyBGRALocked(CVPixelBufferRef pb) {
  CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  size_t w = CVPixelBufferGetWidth(pb);
  size_t h = CVPixelBufferGetHeight(pb);
  size_t stride = CVPixelBufferGetBytesPerRow(pb);
  uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(pb);
  if (!base || w < 2 || h < 2) {
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    return;
  }
  int need = (int)(w * h);
  if (!gPixels || gCap < need) {
    free(gPixels);
    gPixels = (int *)malloc((size_t)need * sizeof(int));
    gCap = gPixels ? need : 0;
  }
  if (!gPixels) {
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    return;
  }
  for (size_t y = 0; y < h; y++) {
    uint8_t *row = base + y * stride;
    int *dst = gPixels + (int)(y * w);
    for (size_t x = 0; x < w; x++) {
      uint8_t b = row[x * 4 + 0];
      uint8_t g = row[x * 4 + 1];
      uint8_t r = row[x * 4 + 2];
      uint8_t a = row[x * 4 + 3];
      dst[x] = ((int)a << 24) | ((int)r << 16) | ((int)g << 8) | (int)b;
    }
  }
  gW = (int)w;
  gH = (int)h;
  gSeq++;
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
}

static OSStatus decodeSampleLocked(CMSampleBufferRef sample) {
  if (!gSession || !sample) return -1;
  // Synchronous decode — caller already holds gLock; callback must not re-lock.
  __block OSStatus cbStatus = noErr;
  VTDecodeInfoFlags info = 0;
  OSStatus st = VTDecompressionSessionDecodeFrameWithOutputHandler(
    gSession, sample, 0, &info,
    ^(OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime pts, CMTime duration) {
      (void)infoFlags; (void)pts; (void)duration;
      cbStatus = status;
      if (status != noErr || !imageBuffer) return;
      if (CFGetTypeID(imageBuffer) != CVPixelBufferGetTypeID()) return;
      copyBGRALocked((CVPixelBufferRef)imageBuffer);
    });
  if (st == noErr) st = cbStatus;
  return st;
}

static BOOL feedAnnexBLocked(const uint8_t *data, size_t len, int keyframe) {
  Nal nals[32];
  int n = collectNals(data, len, nals, 32);
  if (n <= 0) return NO;

  BOOL sawSps = NO, sawPps = NO;
  for (int i = 0; i < n; i++) {
    if (nals[i].type == 7) {
      storeNal(&gSps, &gSpsLen, nals[i].ptr, nals[i].len);
      sawSps = YES;
    } else if (nals[i].type == 8) {
      storeNal(&gPps, &gPpsLen, nals[i].ptr, nals[i].len);
      sawPps = YES;
    }
  }
  if ((sawSps || sawPps || !gReady) && gSps && gPps) {
    if (!rebuildSessionLocked()) return NO;
  }
  if (!gReady || !gSession || !gFormat) return NO;
  (void)keyframe;

  // Build AVCC block: length-prefixed VCL (+SEI) NALs only.
  size_t avccNeed = 0;
  int vcl = 0;
  for (int i = 0; i < n; i++) {
    int t = nals[i].type;
    if (t == 7 || t == 8) continue; // already in format desc
    avccNeed += 4 + nals[i].len;
    if (t == 1 || t == 5) vcl++;
  }
  if (vcl == 0 || avccNeed == 0) return NO;

  CMBlockBufferRef block = NULL;
  OSStatus st = CMBlockBufferCreateWithMemoryBlock(
    kCFAllocatorDefault, NULL, avccNeed, kCFAllocatorDefault, NULL, 0, avccNeed, 0, &block);
  if (st != noErr || !block) return NO;

  size_t off = 0;
  for (int i = 0; i < n; i++) {
    int t = nals[i].type;
    if (t == 7 || t == 8) continue;
    uint8_t lenb[4] = {
      (uint8_t)((nals[i].len >> 24) & 0xff),
      (uint8_t)((nals[i].len >> 16) & 0xff),
      (uint8_t)((nals[i].len >> 8) & 0xff),
      (uint8_t)(nals[i].len & 0xff)
    };
    CMBlockBufferReplaceDataBytes(lenb, block, off, 4);
    off += 4;
    CMBlockBufferReplaceDataBytes(nals[i].ptr, block, off, nals[i].len);
    off += nals[i].len;
  }

  CMSampleBufferRef sample = NULL;
  size_t sampleSize = avccNeed;
  st = CMSampleBufferCreateReady(kCFAllocatorDefault, block, gFormat, 1, 0, NULL, 1, &sampleSize, &sample);
  CFRelease(block);
  if (st != noErr || !sample) return NO;

  st = decodeSampleLocked(sample);
  CFRelease(sample);
  return st == noErr && gW > 1 && gH > 1;
}

JNIEXPORT jint JNICALL Java_H264Dec_decode(JNIEnv *env, jclass cls,
    jbyteArray jau, jint keyframe, jint hintW, jint hintH) {
  (void)cls; (void)hintW; (void)hintH;
  if (!jau) return 0;
  ensureLock();
  jsize len = (*env)->GetArrayLength(env, jau);
  if (len < 8) return 0;
  jbyte *bytes = (*env)->GetByteArrayElements(env, jau, NULL);
  if (!bytes) return 0;
  [gLock lock];
  BOOL ok = feedAnnexBLocked((const uint8_t *)bytes, (size_t)len, keyframe != 0);
  [gLock unlock];
  (*env)->ReleaseByteArrayElements(env, jau, bytes, JNI_ABORT);
  return ok ? 1 : 0;
}

static BOOL decodeJpegLocked(const uint8_t *data, size_t len) {
  if (!data || len < 24) return NO;
  CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, data, len, NULL);
  if (!provider) return NO;
  CGImageSourceRef src = CGImageSourceCreateWithDataProvider(provider, NULL);
  CGDataProviderRelease(provider);
  if (!src) return NO;
  CGImageRef image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
  CFRelease(src);
  if (!image) return NO;

  size_t w = CGImageGetWidth(image);
  size_t h = CGImageGetHeight(image);
  if (w < 2 || h < 2) {
    CGImageRelease(image);
    return NO;
  }
  int need = (int)(w * h);
  if (!gPixels || gCap < need) {
    free(gPixels);
    gPixels = (int *)malloc((size_t)need * sizeof(int));
    gCap = gPixels ? need : 0;
  }
  if (!gPixels) {
    CGImageRelease(image);
    return NO;
  }

  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  // Premultiplied first-byte alpha layout that matches Processing ARGB ints on LE:
  // byte order B,G,R,A in memory → int 0xAARRGGBB
  CGContextRef ctx = CGBitmapContextCreate(
    gPixels, w, h, 8, w * 4, space,
    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(space);
  if (!ctx) {
    CGImageRelease(image);
    return NO;
  }
  CGContextSetBlendMode(ctx, kCGBlendModeCopy);
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image);
  CGContextRelease(ctx);
  CGImageRelease(image);

  // CG draws bottom-up into some contexts — flip vertically into place if needed.
  // With CGBitmapContext + DrawImage, origin is bottom-left; Processing wants top-left.
  int *tmp = (int *)malloc((size_t)need * sizeof(int));
  if (tmp) {
    for (size_t y = 0; y < h; y++) {
      memcpy(tmp + (int)(y * w), gPixels + (int)((h - 1 - y) * w), w * sizeof(int));
    }
    memcpy(gPixels, tmp, (size_t)need * sizeof(int));
    free(tmp);
  }

  gW = (int)w;
  gH = (int)h;
  gSeq++;
  return YES;
}

JNIEXPORT jint JNICALL Java_H264Dec_decodeJpeg(JNIEnv *env, jclass cls, jbyteArray jjpeg) {
  (void)cls;
  if (!jjpeg) return 0;
  ensureLock();
  jsize len = (*env)->GetArrayLength(env, jjpeg);
  if (len < 24) return 0;
  jbyte *bytes = (*env)->GetByteArrayElements(env, jjpeg, NULL);
  if (!bytes) return 0;
  // Copy — CGDataProviderCreateWithData does not copy; buffer must live through decode.
  uint8_t *copy = (uint8_t *)malloc((size_t)len);
  if (!copy) {
    (*env)->ReleaseByteArrayElements(env, jjpeg, bytes, JNI_ABORT);
    return 0;
  }
  memcpy(copy, bytes, (size_t)len);
  (*env)->ReleaseByteArrayElements(env, jjpeg, bytes, JNI_ABORT);
  [gLock lock];
  BOOL ok = decodeJpegLocked(copy, (size_t)len);
  [gLock unlock];
  free(copy);
  return ok ? 1 : 0;
}

JNIEXPORT jintArray JNICALL Java_H264Dec_copyPixels(JNIEnv *env, jclass cls, jintArray jdest) {
  (void)cls;
  ensureLock();
  [gLock lock];
  if (!gPixels || gW < 2 || gH < 2) {
    [gLock unlock];
    return NULL;
  }
  int n = gW * gH;
  jintArray out = jdest;
  if (out == NULL || (*env)->GetArrayLength(env, out) < n) {
    out = (*env)->NewIntArray(env, n);
  }
  if (out) (*env)->SetIntArrayRegion(env, out, 0, n, (jint *)gPixels);
  [gLock unlock];
  return out;
}

JNIEXPORT jint JNICALL Java_H264Dec_width(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  ensureLock();
  [gLock lock];
  int w = gW;
  [gLock unlock];
  return w;
}

JNIEXPORT jint JNICALL Java_H264Dec_height(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  ensureLock();
  [gLock lock];
  int h = gH;
  [gLock unlock];
  return h;
}

JNIEXPORT jlong JNICALL Java_H264Dec_frameSeq(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  ensureLock();
  [gLock lock];
  jlong s = (jlong)gSeq;
  [gLock unlock];
  return s;
}

JNIEXPORT void JNICALL Java_H264Dec_reset(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  ensureLock();
  [gLock lock];
  resetLocked();
  [gLock unlock];
}
