#import "uvc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USB.h>
#include <CoreFoundation/CoreFoundation.h>

#define UVC_SET_CUR 0x01
#define UVC_GET_CUR 0x81
#define UVC_GET_MIN 0x82
#define UVC_GET_MAX 0x83
#define UVC_GET_INFO 0x86

#define CC_VIDEO 0x0E
#define SC_VIDEOCONTROL 0x01
#define CS_INTERFACE 0x24
#define VC_INPUT_TERMINAL 0x02
#define VC_PROCESSING_UNIT 0x05
#define ITT_CAMERA 0x0201

#define CT_AE_MODE 0x02
#define CT_EXPOSURE_ABS 0x04
#define CT_FOCUS_ABS 0x06
#define CT_FOCUS_AUTO 0x08
#define PU_GAIN 0x04
#define PU_WB_TEMP 0x0A
#define PU_WB_AUTO 0x0B

/* AE mode bits used by Logitech C9xx: 1=manual, 8=aperture priority (auto). */
#define AE_MANUAL 0x01
#define AE_AUTO 0x08

typedef struct {
  IOUSBDeviceInterface500 **dev;
  int opened;
} UvcDev;

static UvcDev gDev;

static int bmHas(const uint8_t *bm, int len, int bit) {
  int byte = bit / 8;
  if (byte < 0 || byte >= len) return 0;
  return (bm[byte] >> (bit % 8)) & 1;
}

static long decode(const uint8_t *b, int len) {
  unsigned long v = 0;
  for (int i = 0; i < len; i++) v |= ((unsigned long)b[i]) << (8 * i);
  return (long)v;
}

static void encode(long v, uint8_t *b, int len) {
  for (int i = 0; i < len; i++) b[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
}

static float clampf(float v, float lo, float hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

int uvcParseUniqueId(const char *uid, uint16_t *vid, uint16_t *pid) {
  if (uid == NULL || vid == NULL || pid == NULL) return 0;
  /* Prefer trailing 8 hex digits: …046d085c */
  const char *p = uid;
  if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
  size_t n = strlen(p);
  if (n < 8) return 0;
  char hex[9];
  memcpy(hex, p + n - 8, 8);
  hex[8] = 0;
  unsigned long v = strtoul(hex, NULL, 16);
  *vid = (uint16_t)((v >> 16) & 0xFFFF);
  *pid = (uint16_t)(v & 0xFFFF);
  return *vid != 0;
}

static int parseVc(IOUSBDeviceInterface500 **dev, UvcCam *cam, uint8_t *ctBm, int *ctLen, uint8_t *puBm, int *puLen) {
  IOUSBConfigurationDescriptorPtr cfg = NULL;
  if ((*dev)->GetConfigurationDescriptorPtr(dev, 0, &cfg) != kIOReturnSuccess || cfg == NULL) return 0;
  const uint8_t *p = (const uint8_t *)cfg;
  int total = USBToHostWord(cfg->wTotalLength);
  int off = 0, inVc = 0, found = 0;
  cam->vc = 0;
  cam->ct = 0;
  cam->pu = 0;
  *ctLen = 0;
  *puLen = 0;
  while (off + 2 <= total) {
    int len = p[off];
    int type = p[off + 1];
    if (len < 2) break;
    if (type == 0x04 && off + 9 <= total) {
      inVc = (p[off + 5] == CC_VIDEO && p[off + 6] == SC_VIDEOCONTROL);
      if (inVc) {
        cam->vc = p[off + 2];
        found = 1;
      }
    } else if (inVc && type == CS_INTERFACE && len >= 3) {
      int sub = p[off + 2];
      if (sub == VC_INPUT_TERMINAL && len >= 8) {
        int term = p[off + 4] | (p[off + 5] << 8);
        if (term == ITT_CAMERA && len >= 15) {
          cam->ct = p[off + 3];
          int sz = p[off + 14];
          if (sz > 8) sz = 8;
          if (off + 15 + sz <= total) {
            memcpy(ctBm, p + off + 15, sz);
            *ctLen = sz;
          }
        }
      } else if (sub == VC_PROCESSING_UNIT && len >= 8) {
        cam->pu = p[off + 3];
        int sz = p[off + 7];
        if (sz > 8) sz = 8;
        if (off + 8 + sz <= total) {
          memcpy(puBm, p + off + 8, sz);
          *puLen = sz;
        }
      }
    }
    off += len;
  }
  return found && (cam->ct || cam->pu);
}

static int nameMatch(const char *want, const char *have) {
  if (want == NULL || want[0] == 0) return 1;
  if (have == NULL || have[0] == 0) return 0;
  if (strcasecmp(want, have) == 0) return 1;
  /* Case-insensitive substring either way. */
  size_t wn = strlen(want), hn = strlen(have);
  char a[256], b[256];
  if (wn >= sizeof(a) || hn >= sizeof(b)) return 0;
  for (size_t i = 0; i <= wn; i++) a[i] = (char)tolower((unsigned char)want[i]);
  for (size_t i = 0; i <= hn; i++) b[i] = (char)tolower((unsigned char)have[i]);
  return strstr(a, b) != NULL || strstr(b, a) != NULL;
}

static int openDevice(UvcCam *cam, const char *name, uint16_t vid, uint16_t pid) {
  uvcClose(cam);
  memset(&gDev, 0, sizeof(gDev));
  memset(cam, 0, sizeof(*cam));

  const char *classes[] = {"IOUSBHostDevice", "IOUSBDevice"};
  for (int ci = 0; ci < 2; ci++) {
    CFMutableDictionaryRef match = IOServiceMatching(classes[ci]);
    if (match == NULL) continue;
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS) continue;

    io_service_t svc;
    while ((svc = IOIteratorNext(it))) {
      IOCFPlugInInterface **plug = NULL;
      SInt32 score = 0;
      if (IOCreatePlugInInterfaceForService(svc, kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plug, &score) != kIOReturnSuccess || plug == NULL) {
        IOObjectRelease(svc);
        continue;
      }
      IOUSBDeviceInterface500 **dev = NULL;
      HRESULT hr = (*plug)->QueryInterface(plug,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID500), (LPVOID *)&dev);
      IODestroyPlugInInterface(plug);
      if (hr != 0 || dev == NULL) {
        IOObjectRelease(svc);
        continue;
      }

      uint16_t dVid = 0, dPid = 0;
      (*dev)->GetDeviceVendor(dev, &dVid);
      (*dev)->GetDeviceProduct(dev, &dPid);

      char product[128] = {0};
      CFStringRef ns = IORegistryEntryCreateCFProperty(svc, CFSTR("USB Product Name"),
        kCFAllocatorDefault, 0);
      if (ns) {
        CFStringGetCString(ns, product, sizeof(product), kCFStringEncodingUTF8);
        CFRelease(ns);
      }

      uint8_t ctBm[8] = {0}, puBm[8] = {0};
      int ctLen = 0, puLen = 0;
      UvcCam probe;
      memset(&probe, 0, sizeof(probe));
      int isUvc = parseVc(dev, &probe, ctBm, &ctLen, puBm, &puLen);

      int vidOk = (vid == 0 || dVid == vid);
      int pidOk = (pid == 0 || dPid == pid);
      int nameOk = nameMatch(name, product);
      /* If caller gave vid:pid, name is optional. If only name, require match. */
      int keep = 0;
      if (isUvc && vidOk && pidOk) {
        if (vid != 0 || pid != 0) keep = 1;
        else if (name != NULL && name[0] != 0 && nameOk) keep = 1;
      }

      if (keep) {
        gDev.dev = dev;
        IOReturn kr = (*dev)->USBDeviceOpen(dev);
        if (kr != kIOReturnSuccess) kr = (*dev)->USBDeviceOpenSeize(dev);
        if (kr != kIOReturnSuccess) {
          (*dev)->Release(dev);
          gDev.dev = NULL;
          IOObjectRelease(svc);
          continue;
        }
        gDev.opened = 1;
        *cam = probe;
        cam->open = 1;
        cam->vid = dVid;
        cam->pid = dPid;
        strlcpy(cam->name, product[0] ? product : "UVC Camera", sizeof(cam->name));
        cam->focAbs = bmHas(ctBm, ctLen, 5);
        cam->focAuto = bmHas(ctBm, ctLen, 17);
        cam->expAbs = bmHas(ctBm, ctLen, 3);
        cam->expAuto = bmHas(ctBm, ctLen, 1);
        cam->gain = bmHas(puBm, puLen, 9);
        cam->wbTemp = bmHas(puBm, puLen, 6);
        cam->wbAuto = bmHas(puBm, puLen, 12);
        IOObjectRelease(svc);
        IOObjectRelease(it);
        return 1;
      }

      (*dev)->Release(dev);
      IOObjectRelease(svc);
    }
    IOObjectRelease(it);
  }
  return 0;
}

void uvcClose(UvcCam *cam) {
  if (gDev.dev != NULL) {
    if (gDev.opened) (*gDev.dev)->USBDeviceClose(gDev.dev);
    (*gDev.dev)->Release(gDev.dev);
  }
  memset(&gDev, 0, sizeof(gDev));
  if (cam) memset(cam, 0, sizeof(*cam));
}

static int req(UvcCam *cam, int in, uint8_t request, uint8_t unit, uint8_t sel, uint8_t *buf, int len) {
  if (!cam->open || gDev.dev == NULL) return 0;
  IOUSBDevRequestTO r;
  memset(&r, 0, sizeof(r));
  r.bmRequestType = USBmakebmRequestType(in ? kUSBIn : kUSBOut, kUSBClass, kUSBInterface);
  r.bRequest = request;
  r.wValue = (uint16_t)(sel << 8);
  r.wIndex = (uint16_t)((unit << 8) | cam->vc);
  r.pData = buf;
  r.wLength = (uint16_t)len;
  r.noDataTimeout = 1000;
  r.completionTimeout = 1000;
  return (*gDev.dev)->DeviceRequestTO(gDev.dev, &r) == kIOReturnSuccess;
}

static int getRange(UvcCam *cam, uint8_t unit, uint8_t sel, int len, long *cur, long *mn, long *mx) {
  uint8_t buf[8] = {0};
  if (!req(cam, 1, UVC_GET_CUR, unit, sel, buf, len)) return 0;
  *cur = decode(buf, len);
  *mn = *cur;
  *mx = *cur;
  if (req(cam, 1, UVC_GET_MIN, unit, sel, buf, len)) *mn = decode(buf, len);
  if (req(cam, 1, UVC_GET_MAX, unit, sel, buf, len)) *mx = decode(buf, len);
  if (*mx < *mn) {
    long t = *mn;
    *mn = *mx;
    *mx = t;
  }
  return 1;
}

int uvcRefresh(UvcCam *cam) {
  if (!cam->open) return 0;
  if (cam->focAbs) getRange(cam, cam->ct, CT_FOCUS_ABS, 2, &cam->focCur, &cam->focMin, &cam->focMax);
  if (cam->expAbs) getRange(cam, cam->ct, CT_EXPOSURE_ABS, 4, &cam->expCur, &cam->expMin, &cam->expMax);
  if (cam->gain) getRange(cam, cam->pu, PU_GAIN, 2, &cam->gainCur, &cam->gainMin, &cam->gainMax);
  if (cam->wbTemp) getRange(cam, cam->pu, PU_WB_TEMP, 2, &cam->wbCur, &cam->wbMin, &cam->wbMax);
  uint8_t b[4] = {0};
  if (cam->focAuto && req(cam, 1, UVC_GET_CUR, cam->ct, CT_FOCUS_AUTO, b, 1)) cam->focAutoCur = (int)b[0];
  if (cam->expAuto && req(cam, 1, UVC_GET_CUR, cam->ct, CT_AE_MODE, b, 1)) cam->expAutoCur = (int)b[0];
  if (cam->wbAuto && req(cam, 1, UVC_GET_CUR, cam->pu, PU_WB_AUTO, b, 1)) cam->wbAutoCur = (int)b[0];
  return 1;
}

int uvcOpen(UvcCam *cam, const char *name, uint16_t vid, uint16_t pid) {
  if (!openDevice(cam, name, vid, pid)) return 0;
  uvcRefresh(cam);
  return 1;
}

int uvcEnsure(UvcCam *cam, const char *name, uint16_t vid, uint16_t pid) {
  if (cam != NULL && cam->open && gDev.dev != NULL && gDev.opened) {
    int vidOk = (vid == 0 || cam->vid == vid);
    int pidOk = (pid == 0 || cam->pid == pid);
    int nameOk = (name == NULL || name[0] == 0 || nameMatch(name, cam->name));
    if (vidOk && pidOk && nameOk) return 1;
  }
  return uvcOpen(cam, name, vid, pid);
}

float uvcFocusNorm(const UvcCam *cam) {
  if (!cam->focAbs || cam->focMax <= cam->focMin) return 0.5f;
  return clampf((float)(cam->focCur - cam->focMin) / (float)(cam->focMax - cam->focMin), 0, 1);
}

float uvcExposureNorm(const UvcCam *cam) {
  if (!cam->expAbs || cam->expMax <= cam->expMin || cam->expMin <= 0) return 0.5f;
  float lo = logf((float)cam->expMin);
  float hi = logf((float)cam->expMax);
  if (hi <= lo) return 0.5f;
  float cur = logf((float)(cam->expCur < cam->expMin ? cam->expMin : cam->expCur));
  return clampf((cur - lo) / (hi - lo), 0, 1);
}

int uvcSetAutoFocus(UvcCam *cam, int on) {
  if (!cam->open || !cam->focAuto) return 0;
  uint8_t b[1] = { on ? 1 : 0 };
  if (!req(cam, 0, UVC_SET_CUR, cam->ct, CT_FOCUS_AUTO, b, 1)) return 0;
  cam->focAutoCur = on ? 1 : 0;
  return 1;
}

int uvcSetFocusNorm(UvcCam *cam, float norm01) {
  if (!cam->open || !cam->focAbs) return 0;
  if (cam->focAuto) uvcSetAutoFocus(cam, 0);
  float n = clampf(norm01, 0, 1);
  long v = cam->focMin + (long)lroundf(n * (float)(cam->focMax - cam->focMin));
  uint8_t b[2];
  encode(v, b, 2);
  if (!req(cam, 0, UVC_SET_CUR, cam->ct, CT_FOCUS_ABS, b, 2)) return 0;
  cam->focCur = v;
  return 1;
}

int uvcSetAutoExposure(UvcCam *cam, int on) {
  if (!cam->open || !cam->expAuto) return 0;
  uint8_t b[1] = { on ? AE_AUTO : AE_MANUAL };
  if (!req(cam, 0, UVC_SET_CUR, cam->ct, CT_AE_MODE, b, 1)) {
    /* Some cams use bit 2 (auto shutter) instead of aperture priority. */
    if (on) {
      b[0] = 0x02;
      if (!req(cam, 0, UVC_SET_CUR, cam->ct, CT_AE_MODE, b, 1)) return 0;
    } else {
      return 0;
    }
  }
  cam->expAutoCur = b[0];
  return 1;
}

int uvcSetExposureNorm(UvcCam *cam, float norm01) {
  if (!cam->open || !cam->expAbs || cam->expMin <= 0 || cam->expMax <= cam->expMin) return 0;
  if (cam->expAuto) uvcSetAutoExposure(cam, 0);
  float n = clampf(norm01, 0, 1);
  float lo = logf((float)cam->expMin);
  float hi = logf((float)cam->expMax);
  long v = (long)lroundf(expf(lo + n * (hi - lo)));
  if (v < cam->expMin) v = cam->expMin;
  if (v > cam->expMax) v = cam->expMax;
  uint8_t b[4];
  encode(v, b, 4);
  if (!req(cam, 0, UVC_SET_CUR, cam->ct, CT_EXPOSURE_ABS, b, 4)) return 0;
  cam->expCur = v;
  return 1;
}

int uvcSetAutoWhite(UvcCam *cam, int on) {
  if (!cam->open || !cam->wbAuto) return 0;
  uint8_t b[1] = { on ? 1 : 0 };
  if (!req(cam, 0, UVC_SET_CUR, cam->pu, PU_WB_AUTO, b, 1)) return 0;
  cam->wbAutoCur = on ? 1 : 0;
  return 1;
}
