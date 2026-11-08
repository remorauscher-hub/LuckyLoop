#pragma once

#include <stdint.h>

typedef struct {
  int open;
  uint16_t vid;
  uint16_t pid;
  uint8_t vc;
  uint8_t ct;
  uint8_t pu;
  int focAbs;
  int focAuto;
  int expAbs;
  int expAuto;
  int gain;
  int wbTemp;
  int wbAuto;
  long focMin, focMax, focCur;
  long expMin, expMax, expCur;
  long gainMin, gainMax, gainCur;
  long wbMin, wbMax, wbCur;
  int focAutoCur;
  int expAutoCur; /* raw AE mode byte */
  int wbAutoCur;
  char name[128];
} UvcCam;

/* Open by USB product name and/or vid:pid (0 = wildcard). Returns 1 on success. */
int uvcOpen(UvcCam *cam, const char *name, uint16_t vid, uint16_t pid);

/* Reuse an already-open handle when vid/pid match — avoids USB reopen stutter. */
int uvcEnsure(UvcCam *cam, const char *name, uint16_t vid, uint16_t pid);

void uvcClose(UvcCam *cam);

/* Probe current ranges/values into cam fields. */
int uvcRefresh(UvcCam *cam);

/* Auto focus on/off. */
int uvcSetAutoFocus(UvcCam *cam, int on);

/* Absolute focus as 0..1 across device min..max. */
int uvcSetFocusNorm(UvcCam *cam, float norm01);

/* Auto exposure on/off. Off switches to manual AE mode. */
int uvcSetAutoExposure(UvcCam *cam, int on);

/* Absolute exposure as 0..1 (log-mapped across device min..max). */
int uvcSetExposureNorm(UvcCam *cam, float norm01);

/* Auto white balance on/off. */
int uvcSetAutoWhite(UvcCam *cam, int on);

/* Parse "0x....046d085c" style AVFoundation uniqueIDs into vid/pid. */
int uvcParseUniqueId(const char *uid, uint16_t *vid, uint16_t *pid);

float uvcFocusNorm(const UvcCam *cam);
float uvcExposureNorm(const UvcCam *cam);
