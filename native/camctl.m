#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <jni.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "uvc.h"

static int tookStage = 0;
static int lensSupport = -1;
static int logged = 0;

static NSArray<AVCaptureDevice *> *allCameras(void) {
  NSArray<AVCaptureDeviceType> *types = @[
    AVCaptureDeviceTypeBuiltInWideAngleCamera,
    AVCaptureDeviceTypeContinuityCamera,
    AVCaptureDeviceTypeExternal,
    AVCaptureDeviceTypeDeskViewCamera
  ];
  AVCaptureDeviceDiscoverySession *session =
    [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:types
      mediaType:AVMediaTypeVideo
      position:AVCaptureDevicePositionUnspecified];
  NSMutableArray<AVCaptureDevice *> *all = [NSMutableArray arrayWithArray:session.devices];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
    if (![all containsObject:d]) [all addObject:d];
  }
#pragma clang diagnostic pop
  return all;
}

static AVCaptureDevice *matchCamera(NSString *want, NSArray<AVCaptureDevice *> *all) {
  if (all.count == 0) return nil;
  if (want.length == 0) {
    for (AVCaptureDevice *d in all) if (d.continuityCamera) return d;
    return all.firstObject;
  }
  NSString *fold = want.lowercaseString;
  for (AVCaptureDevice *d in all) {
    if ([d.localizedName caseInsensitiveCompare:want] == NSOrderedSame) return d;
  }
  for (AVCaptureDevice *d in all) {
    NSString *name = d.localizedName.lowercaseString;
    if ([fold containsString:name] || [name containsString:fold]) return d;
  }
  if ([fold containsString:@"iphone"] || [fold containsString:@"continuity"]) {
    for (AVCaptureDevice *d in all) if (d.continuityCamera) return d;
  }
  if (all.count == 1) return all.firstObject;
  return nil;
}

static NSString *lensLabel(AVCaptureDevice *d) {
  NSString *t = d.deviceType == nil ? @"" : d.deviceType;
  if ([t containsString:@"UltraWide"]) return @"0.5×";
  if ([t containsString:@"Telephoto"]) return @"Tele";
  if ([t containsString:@"Wide"]) return @"1×";
  NSString *n = d.localizedName == nil ? @"Lens" : d.localizedName;
  if (n.length > 10) n = [n substringToIndex:10];
  return [[n stringByReplacingOccurrencesOfString:@"|" withString:@""]
    stringByReplacingOccurrencesOfString:@"," withString:@""];
}

static NSArray *constituentsOf(AVCaptureDevice *dev) {
  SEL sel = sel_registerName("constituentDevices");
  if (![dev respondsToSelector:sel]) return nil;
  NSArray *(*fn)(id, SEL) = (NSArray *(*)(id, SEL))objc_msgSend;
  @try {
    return fn(dev, sel);
  } @catch (NSException *ex) {
    return nil;
  }
}

static NSArray *switchFactorsOf(AVCaptureDevice *dev) {
  SEL sel = sel_registerName("virtualDeviceSwitchOverVideoZoomFactors");
  if (![dev respondsToSelector:sel]) return nil;
  NSArray *(*fn)(id, SEL) = (NSArray *(*)(id, SEL))objc_msgSend;
  @try {
    return fn(dev, sel);
  } @catch (NSException *ex) {
    return nil;
  }
}

static BOOL canZoom(AVCaptureDevice *dev) {
  return [dev respondsToSelector:sel_registerName("setVideoZoomFactor:")];
}

static CGFloat readZoom(AVCaptureDevice *dev) {
  SEL sel = sel_registerName("videoZoomFactor");
  if (![dev respondsToSelector:sel]) return 1;
  CGFloat (*fn)(id, SEL) = (CGFloat (*)(id, SEL))objc_msgSend;
  return fn(dev, sel);
}

static CGFloat readZoomBound(AVCaptureDevice *dev, const char *selName, CGFloat fallback) {
  SEL sel = sel_registerName(selName);
  if (![dev respondsToSelector:sel]) return fallback;
  CGFloat (*fn)(id, SEL) = (CGFloat (*)(id, SEL))objc_msgSend;
  CGFloat v = fn(dev, sel);
  return v > 0 ? v : fallback;
}

static void writeZoom(AVCaptureDevice *dev, CGFloat z) {
  SEL sel = sel_registerName("setVideoZoomFactor:");
  if (![dev respondsToSelector:sel]) return;
  void (*fn)(id, SEL, CGFloat) = (void (*)(id, SEL, CGFloat))objc_msgSend;
  fn(dev, sel, z);
}

static BOOL canBias(AVCaptureDevice *dev) {
  return [dev respondsToSelector:sel_registerName("setExposureTargetBias:completionHandler:")];
}

static float readFloatSel(AVCaptureDevice *dev, const char *selName, float fallback) {
  SEL sel = sel_registerName(selName);
  if (![dev respondsToSelector:sel]) return fallback;
  float (*fn)(id, SEL) = (float (*)(id, SEL))objc_msgSend;
  return fn(dev, sel);
}

static void writeBias(AVCaptureDevice *dev, float bias) {
  SEL sel = sel_registerName("setExposureTargetBias:completionHandler:");
  if (![dev respondsToSelector:sel]) return;
  void (*fn)(id, SEL, float, id) = (void (*)(id, SEL, float, id))objc_msgSend;
  fn(dev, sel, bias, nil);
}

static BOOL canFocusPos(AVCaptureDevice *dev) {
  return [dev respondsToSelector:sel_registerName("setFocusModeLockedWithLensPosition:completionHandler:")];
}

static void writeFocus(AVCaptureDevice *dev, float pos) {
  SEL sel = sel_registerName("setFocusModeLockedWithLensPosition:completionHandler:");
  if (![dev respondsToSelector:sel]) return;
  void (*fn)(id, SEL, float, id) = (void (*)(id, SEL, float, id))objc_msgSend;
  fn(dev, sel, pos, nil);
}

static void setBoolSel(id obj, const char *selName, BOOL value) {
  SEL sel = sel_registerName(selName);
  if (![obj respondsToSelector:sel]) return;
  void (*fn)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
  fn(obj, sel, value);
}

static void quietFaces(AVCaptureDevice *dev) {
  setBoolSel(dev, "setAutomaticallyAdjustsFaceDrivenAutoExposureEnabled:", NO);
  setBoolSel(dev, "setFaceDrivenAutoExposureEnabled:", NO);
  setBoolSel(dev, "setAutomaticallyAdjustsFaceDrivenAutoFocusEnabled:", NO);
  setBoolSel(dev, "setFaceDrivenAutoFocusEnabled:", NO);
}

static int setStage(int on) {
  @try {
    if (![AVCaptureDevice respondsToSelector:@selector(setCenterStageControlMode:)]) return 0;
    AVCaptureDevice.centerStageControlMode = AVCaptureCenterStageControlModeApp;
    AVCaptureDevice.centerStageEnabled = on ? YES : NO;
    tookStage = 1;
    return 1;
  } @catch (NSException *ex) {
    return 0;
  }
}

static void appendName(char *dst, size_t cap, NSArray *parts) {
  dst[0] = 0;
  if (parts == nil) return;
  int n = 0;
  for (AVCaptureDevice *c in parts) {
    if (n >= 4) break;
    NSString *label = lensLabel(c);
    if (n > 0 && strlen(dst) + 1 < cap) strlcat(dst, ",", cap);
    strlcat(dst, label.UTF8String, cap);
    n++;
  }
}

JNIEXPORT void JNICALL Java_CamCtl_releaseStage(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  if (!tookStage) return;
  @autoreleasepool {
    @try {
      AVCaptureDevice.centerStageControlMode = AVCaptureCenterStageControlModeUser;
    } @catch (NSException *ex) {
    }
    tookStage = 0;
  }
}

JNIEXPORT jint JNICALL Java_CamCtl_continuityOptIn(JNIEnv *env, jclass cls) {
  (void)env;
  (void)cls;
  @autoreleasepool {
    id v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSCameraUseContinuityCameraDeviceType"];
    if (v == nil) return 0;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v boolValue] ? 1 : 0;
    if ([v isKindOfClass:[NSString class]]) {
      NSString *s = [(NSString *)v lowercaseString];
      return ([s isEqualToString:@"true"] || [s isEqualToString:@"yes"] || [s isEqualToString:@"1"]) ? 1 : 0;
    }
    return 0;
  }
}

/* Each entry: "name\tuniqueID\tcontinuity(0|1)" — includes Continuity Camera / iPhone. */
JNIEXPORT jobjectArray JNICALL Java_CamCtl_listDevices(JNIEnv *env, jclass cls) {
  (void)cls;
  jclass stringClass = (*env)->FindClass(env, "java/lang/String");
  if (stringClass == NULL) return NULL;

  @autoreleasepool {
    NSArray<AVCaptureDevice *> *all = allCameras();
    jsize n = (jsize)all.count;
    jobjectArray out = (*env)->NewObjectArray(env, n, stringClass, NULL);
    if (out == NULL) return NULL;

    for (jsize i = 0; i < n; i++) {
      AVCaptureDevice *d = all[i];
      NSString *name = d.localizedName == nil ? @"Camera" : d.localizedName;
      name = [[name stringByReplacingOccurrencesOfString:@"\t" withString:@" "]
        stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
      NSString *uid = d.uniqueID == nil ? @"" : d.uniqueID;
      uid = [[uid stringByReplacingOccurrencesOfString:@"\t" withString:@""]
        stringByReplacingOccurrencesOfString:@"\n" withString:@""];
      int cont = d.continuityCamera ? 1 : 0;
      NSString *low = name.lowercaseString;
      if (!cont && ([low containsString:@"iphone"] || [low containsString:@"ipad"]
          || [low containsString:@"continuity"] || [low containsString:@"kontinuit"])) {
        cont = 1;
      }
      NSString *row = [NSString stringWithFormat:@"%@\t%@\t%d", name, uid, cont];
      jstring js = (*env)->NewStringUTF(env, row.UTF8String);
      if (js != NULL) {
        (*env)->SetObjectArrayElement(env, out, i, js);
        (*env)->DeleteLocalRef(env, js);
      }
    }
    return out;
  }
}

JNIEXPORT jint JNICALL Java_CamCtl_configure(JNIEnv *env, jclass cls, jstring jname, jstring juid, jbyteArray jout,
    jint autoExposure, jint autoFocus, jint autoWhite, jint lensLock, jint centerStage,
    jfloat bias, jfloat focus, jfloat zoom, jint lens,
    jint applyBias, jint applyFocus, jint applyZoom, jint applyLens) {
  (void)cls;
  const char *cname = "";
  const char *cuid = "";
  if (jname != NULL) cname = (*env)->GetStringUTFChars(env, jname, NULL);
  if (juid != NULL) cuid = (*env)->GetStringUTFChars(env, juid, NULL);
  char line[1600];
  line[0] = 0;
  int found = 0;

  @autoreleasepool {
    NSArray<AVCaptureDevice *> *all = allCameras();
    NSMutableString *seen = [NSMutableString string];
    for (AVCaptureDevice *d in all) {
      if (seen.length > 0) [seen appendString:@","];
      NSString *n = [d.localizedName stringByReplacingOccurrencesOfString:@"," withString:@" "];
      [seen appendString:n == nil ? @"?" : n];
    }
    NSString *want = [NSString stringWithUTF8String:cname == NULL ? "" : cname];
    AVCaptureDevice *dev = matchCamera(want, all);
    int expL = 0, expA = 0, focL = 0, focA = 0, wbL = 0, wbA = 0;
    int lensOk = 0, stageOk = 0, stageOn = 0, biasOk = 0, focOk = 0, zoomOk = 0;
    int portrait = 0, studio = 0, cont = 0, lensAt = -1, nlens = 0, uvcOn = 0;
    float bmin = 0, bmax = 0, bread = 0, fread = 0;
    double zmin = 1, zmax = 1, zread = 1;
    char lenses[256];
    lenses[0] = 0;
    char err[160];
    err[0] = 0;
    char primary[64];
    primary[0] = 0;

    /* USB webcams (Logitech C922 etc.): real focus/exposure via UVC, not AVFoundation.
       Keep the USB handle open across calls — open/close each slider tick stutters the stream. */
    static UvcCam uvcPersist;
    UvcCam *uvc = &uvcPersist;
    uint16_t uvid = 0, upid = 0;
    uvcParseUniqueId(cuid == NULL ? "" : cuid, &uvid, &upid);
    int uvcReady = uvcEnsure(uvc, cname == NULL ? "" : cname, uvid, upid);
    if (!uvcReady && uvid != 0) uvcReady = uvcEnsure(uvc, "", uvid, upid);
    if (!uvcReady) uvcReady = uvcEnsure(uvc, cname == NULL ? "" : cname, 0, 0);
    if (uvcReady) {
      uvcOn = 1;
      found = 1;
      expL = uvc->expAbs ? 1 : 0;
      expA = uvc->expAuto ? 1 : 0;
      focL = uvc->focAbs ? 1 : 0;
      focA = uvc->focAuto ? 1 : 0;
      wbL = uvc->wbTemp ? 1 : 0;
      wbA = uvc->wbAuto ? 1 : 0;
      biasOk = uvc->expAbs ? 1 : 0;
      focOk = uvc->focAbs ? 1 : 0;
      if (biasOk) {
        bmin = 0;
        bmax = 1;
        bread = uvcExposureNorm(uvc);
      }
      if (focOk) fread = uvcFocusNorm(uvc);

      if (uvc->expAuto) uvcSetAutoExposure(uvc, autoExposure ? 1 : 0);
      if (applyBias && biasOk && !autoExposure) {
        uvcSetExposureNorm(uvc, bias);
        bread = bias;
      }
      if (uvc->focAuto) uvcSetAutoFocus(uvc, autoFocus ? 1 : 0);
      if (applyFocus && focOk && !autoFocus) {
        uvcSetFocusNorm(uvc, focus);
        fread = focus;
      }
      if (uvc->wbAuto) uvcSetAutoWhite(uvc, autoWhite ? 1 : 0);
      /* Avoid full GET_MIN/MAX refresh on every slider tick. */
      if (!applyBias && !applyFocus) uvcRefresh(uvc);
      if (biasOk && !applyBias) bread = uvcExposureNorm(uvc);
      if (focOk && !applyFocus) fread = uvcFocusNorm(uvc);

      if (!logged) {
        logged = 1;
        printf("Camera UVC: %s (%04x:%04x) exposure %s focus %s\n",
          uvc->name, uvc->vid, uvc->pid,
          autoExposure ? "auto" : "manual",
          autoFocus ? "auto" : "manual");
        fflush(stdout);
      }
    }

    if (dev != nil) {
      if (!found) found = 1;
      cont = dev.continuityCamera ? 1 : 0;
      portrait = dev.portraitEffectActive ? 1 : 0;
      studio = dev.studioLightActive ? 1 : 0;
      if (!uvcOn) {
        expL = [dev isExposureModeSupported:AVCaptureExposureModeLocked] ? 1 : 0;
        expA = [dev isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure] ? 1 : 0;
        focL = [dev isFocusModeSupported:AVCaptureFocusModeLocked] ? 1 : 0;
        focA = [dev isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus] ? 1 : 0;
        wbL = [dev isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked] ? 1 : 0;
        wbA = [dev isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance] ? 1 : 0;
        biasOk = canBias(dev) ? 1 : 0;
        if (biasOk) {
          bmin = readFloatSel(dev, "minExposureTargetBias", -8);
          bmax = readFloatSel(dev, "maxExposureTargetBias", 8);
          bread = readFloatSel(dev, "exposureTargetBias", 0);
        }
        focOk = canFocusPos(dev) ? 1 : 0;
        if (focOk) fread = readFloatSel(dev, "lensPosition", 0.5f);
      }
      zoomOk = canZoom(dev) ? 1 : 0;
      if (zoomOk) {
        zmin = readZoomBound(dev, "minAvailableVideoZoomFactor", 1);
        zmax = readZoomBound(dev, "maxAvailableVideoZoomFactor", 1);
        zread = readZoom(dev);
      }
      NSArray *parts = constituentsOf(dev);
      appendName(lenses, sizeof(lenses), parts);
      nlens = parts == nil ? 0 : (int)MIN(parts.count, 4);
      AVCaptureDevice *primaryDev = dev.activePrimaryConstituentDevice;
      if (primaryDev != nil) {
        strlcpy(primary, lensLabel(primaryDev).UTF8String, sizeof(primary));
        if (parts != nil) {
          NSUInteger idx = [parts indexOfObject:primaryDev];
          if (idx != NSNotFound && idx < 4) lensAt = (int)idx;
        }
      }
      if (lensSupport != 0) {
        lensOk = dev.primaryConstituentDeviceSwitchingBehavior != AVCapturePrimaryConstituentDeviceSwitchingBehaviorUnsupported ? 1 : 0;
      }

      NSError *lockErr = nil;
      if ([dev lockForConfiguration:&lockErr]) {
        @try {
          if ([dev respondsToSelector:@selector(setAutoVideoFrameRateEnabled:)]) {
            dev.autoVideoFrameRateEnabled = NO;
          }
          quietFaces(dev);
          if (!uvcOn) {
            if (autoExposure && expA) dev.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
            else if (expL) dev.exposureMode = AVCaptureExposureModeLocked;
            if (applyBias && biasOk && !autoExposure) {
              float b = bias;
              if (b < bmin) b = bmin;
              if (b > bmax) b = bmax;
              writeBias(dev, b);
              bread = b;
            }
            if (applyFocus && focOk && !autoFocus) {
              float p = focus;
              if (p < 0) p = 0;
              if (p > 1) p = 1;
              writeFocus(dev, p);
              fread = p;
            } else if (autoFocus && focA) {
              dev.focusMode = AVCaptureFocusModeContinuousAutoFocus;
            } else if (focL) {
              dev.focusMode = AVCaptureFocusModeLocked;
            }
            if (autoWhite && wbA) dev.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
            else if (wbL) dev.whiteBalanceMode = AVCaptureWhiteBalanceModeLocked;
          }

          BOOL needZoom = (applyLens && lens >= 0 && nlens > 1) || (applyZoom && zoomOk);
          if (needZoom && lensSupport != 0) {
            @try {
              [dev setPrimaryConstituentDeviceSwitchingBehavior:AVCapturePrimaryConstituentDeviceSwitchingBehaviorAuto
                restrictedSwitchingBehaviorConditions:AVCapturePrimaryConstituentDeviceRestrictedSwitchingBehaviorConditionNone];
            } @catch (NSException *ex) {
            }
          }
          if (applyLens && lens >= 0 && nlens > 1 && zoomOk) {
            NSArray *factors = switchFactorsOf(dev);
            CGFloat z = zmin;
            if (lens > 0 && factors != nil && lens - 1 < (int)factors.count) {
              z = [factors[lens - 1] doubleValue];
            }
            writeZoom(dev, z);
            zread = z;
            lensAt = lens;
          } else if (applyZoom && zoomOk) {
            CGFloat z = zoom;
            if (z < zmin) z = zmin;
            if (z > zmax) z = zmax;
            writeZoom(dev, z);
            zread = z;
          }
          if (lensSupport != 0) {
            @try {
              AVCapturePrimaryConstituentDeviceSwitchingBehavior behavior = lensLock
                ? AVCapturePrimaryConstituentDeviceSwitchingBehaviorLocked
                : AVCapturePrimaryConstituentDeviceSwitchingBehaviorAuto;
              [dev setPrimaryConstituentDeviceSwitchingBehavior:behavior
                restrictedSwitchingBehaviorConditions:AVCapturePrimaryConstituentDeviceRestrictedSwitchingBehaviorConditionNone];
              lensOk = 1;
              lensSupport = 1;
            } @catch (NSException *ex) {
              lensOk = 0;
              lensSupport = 0;
            }
          }
        } @catch (NSException *ex) {
          snprintf(err, sizeof(err), "%s", ex.reason.UTF8String);
        }
        [dev unlockForConfiguration];
      } else if (lockErr != nil) {
        snprintf(err, sizeof(err), "%s", lockErr.localizedDescription.UTF8String);
      }
      stageOk = setStage(centerStage);
      stageOn = AVCaptureDevice.centerStageEnabled ? 1 : 0;
      if (!logged) {
        logged = 1;
        printf("Camera hardware: %s  exposure %s  focus %s  white balance %s  lenses %d\n",
          dev.localizedName.UTF8String,
          autoExposure ? "auto" : "locked",
          autoFocus ? "auto" : "locked",
          autoWhite ? "auto" : "locked",
          nlens);
        fflush(stdout);
      }
    }

    /* UVC alone (AVFoundation busy / TCC) still counts as found. */
    if (!found && uvcOn) found = 1;

    snprintf(line, sizeof(line),
      "found=%d|uvc=%d|cont=%d|expL=%d|expA=%d|focL=%d|focA=%d|wbL=%d|wbA=%d|lensOk=%d|lensAt=%d|stageOk=%d|stage=%d|biasOk=%d|bmin=%.3f|bmax=%.3f|bias=%.3f|focOk=%d|focus=%.3f|zoomOk=%d|zmin=%.3f|zmax=%.3f|zoom=%.3f|nlens=%d|lenses=%s|primary=%s|portrait=%d|studio=%d|seen=%s|err=%s",
      found, uvcOn, cont, expL, expA, focL, focA, wbL, wbA, lensOk, lensAt, stageOk, stageOn,
      biasOk, bmin, bmax, bread, focOk, fread, zoomOk, zmin, zmax, zread, nlens,
      lenses, primary, portrait, studio,
      seen.UTF8String == NULL ? "" : seen.UTF8String,
      err);
  }

  if (jname != NULL) (*env)->ReleaseStringUTFChars(env, jname, cname);
  if (juid != NULL) (*env)->ReleaseStringUTFChars(env, juid, cuid);
  if (jout != NULL) {
    jsize cap = (*env)->GetArrayLength(env, jout);
    jbyte *out = (*env)->GetByteArrayElements(env, jout, NULL);
    if (out != NULL && cap > 0) {
      size_t n = strlen(line);
      if (n >= (size_t)cap) n = (size_t)cap - 1;
      memcpy(out, line, n);
      if (n < (size_t)cap) out[n] = 0;
      (*env)->ReleaseByteArrayElements(env, jout, out, 0);
    }
  }
  return found;
}
