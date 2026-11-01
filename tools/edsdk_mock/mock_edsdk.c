/* EDSDK palsu untuk menguji binding dart:ffi tanpa kamera/SDK Canon.
 * Meniru bentuk API (bukan perilaku kamera sungguhan):
 *   gcc -shared -fPIC -o libmock_edsdk.so mock_edsdk.c
 * Variabel env MOCK_NO_CAMERA=1 -> daftar kamera kosong.
 * MOCK_BUSY=n -> n kali pertama TakePicture membalas DEVICE_BUSY.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define EXPORT __attribute__((visibility("default")))
typedef uint32_t U32;
typedef int32_t I32;
typedef uint64_t U64;
typedef void* Ref;
typedef struct { I32 a, b, r; } Cap;
typedef U32 (*Handler)(U32, Ref, Ref);

enum { K_STREAM = 1, K_EVF, K_DIR, K_CAM, K_LIST, K_VOL };
typedef struct { int kind; unsigned char* data; U64 len; Ref stream; } Obj;

static Obj g_cam = {K_CAM}, g_list = {K_LIST}, g_dir = {K_DIR}, g_vol = {K_VOL};
static Handler g_handler; static Ref g_ctx;
static int g_pending, g_busy = -1, g_frames, g_notready_done, g_session, g_init;
static U32 g_save_to, g_evf_dev, g_evf_mode, g_iso, g_av, g_tv, g_wb;
static int g_cap_set; static I32 g_cap[3];
static U32 g_last_af;
static int g_present = -1; /* -1: ikut env MOCK_NO_CAMERA; 0/1: diatur uji */
static const char* kPhoto = "\xFF\xD8\xFF\xE0" "FAKE-PHOTO-BYTES-0123456789" "\xFF\xD9";

static void sset(Obj* o, const void* d, U64 n) {
  free(o->data); o->data = malloc(n ? n : 1); memcpy(o->data, d, n); o->len = n;
}

EXPORT U32 EdsInitializeSDK(void) { g_init = 1; return 0; }
EXPORT U32 EdsTerminateSDK(void) { g_init = 0; return 0; }
EXPORT U32 EdsRelease(Ref r) {
  Obj* o = (Obj*)r; if (o && (o->kind == K_STREAM || o->kind == K_EVF)) { free(o->data); free(o); } return 0; }
EXPORT U32 EdsGetCameraList(Ref* out) { *out = &g_list; return 0; }
static int present(void) { return g_present >= 0 ? g_present : (getenv("MOCK_NO_CAMERA") ? 0 : 1); }
EXPORT U32 EdsGetChildCount(Ref r, U32* n) {
  *n = (((Obj*)r)->kind == K_LIST) ? (U32)present() : 1; return 0; }
EXPORT U32 EdsGetChildAtIndex(Ref r, I32 i, Ref* out) {
  (void)i; *out = (((Obj*)r)->kind == K_LIST) ? (Ref)&g_cam : (Ref)&g_vol; return 0; }
EXPORT U32 EdsOpenSession(Ref c) { (void)c; g_session = 1; return 0; }
EXPORT U32 EdsCloseSession(Ref c) { (void)c; g_session = 0; return 0; }
EXPORT U32 EdsGetEvent(void) {
  if (g_pending && g_handler) { g_pending = 0; g_handler(0x208, &g_dir, g_ctx); } return 0; }
EXPORT U32 EdsSetObjectEventHandler(Ref c, U32 ev, Handler h, Ref ctx) {
  (void)c; (void)ev; g_handler = h; g_ctx = ctx; return 0; }

EXPORT U32 EdsSendCommand(Ref c, U32 cmd, I32 param) {
  (void)c; (void)param;
  if (cmd == 0x0) {
    if (g_busy < 0) { const char* b = getenv("MOCK_BUSY"); g_busy = b ? atoi(b) : 0; }
    if (g_busy > 0) { g_busy--; return 0x81; }
    g_pending = 1; return 0;
  }
  if (cmd == 0x102) { g_last_af = (U32)param; return 0; }
  return 0;
}

EXPORT U32 EdsGetPropertyData(Ref c, U32 prop, I32 param, U32 size, void* data) {
  (void)c; (void)param; (void)size;
  switch (prop) {
    case 0x2: strcpy((char*)data, "Canon EOS R100 (FFI-MOCK)"); return 0;
    case 0x7: strcpy((char*)data, "1.2.0"); return 0;
    case 0x15: strcpy((char*)data, "SER12345"); return 0;
    case 0x409: strcpy((char*)data, "RF-S18-45mm F4.5-6.3 IS STM"); return 0;
    case 0x8: *(U32*)data = 73; return 0;
    case 0x500: *(U32*)data = g_evf_dev; return 0;
    case 0xB: *(U32*)data = g_save_to; return 0;
  }
  return 0x2; /* internal error: prop tidak ada */
}
EXPORT U32 EdsSetPropertyData(Ref c, U32 prop, I32 param, U32 size, void* data) {
  (void)c; (void)param; (void)size; U32 v = *(U32*)data;
  switch (prop) {
    case 0xB: g_save_to = v; return 0;
    case 0x500: g_evf_dev = v; return 0;
    case 0x501: g_evf_mode = v; return 0;
    case 0x404: g_iso = v; return 0; case 0x402: g_av = v; return 0;
    case 0x403: g_tv = v; return 0; case 0x106: g_wb = v; return 0;
  }
  return 0x2;
}
EXPORT U32 EdsSetCapacity(Ref c, Cap cap) {
  (void)c; g_cap_set = 1; g_cap[0] = cap.a; g_cap[1] = cap.b; g_cap[2] = cap.r; return 0; }

EXPORT U32 EdsCreateMemoryStream(U64 size, Ref* out) {
  (void)size; Obj* o = calloc(1, sizeof(Obj)); o->kind = K_STREAM; *out = o; return 0; }
EXPORT U32 EdsGetPointer(Ref s, Ref* p) { *p = ((Obj*)s)->data; return 0; }
EXPORT U32 EdsGetLength(Ref s, U64* n) { *n = ((Obj*)s)->len; return 0; }
EXPORT U32 EdsCreateEvfImageRef(Ref s, Ref* out) {
  Obj* o = calloc(1, sizeof(Obj)); o->kind = K_EVF; o->stream = s; *out = o; return 0; }
EXPORT U32 EdsDownloadEvfImage(Ref c, Ref evf) {
  (void)c; if (!(g_evf_dev & 2)) return 0xA102;
  if (!g_notready_done) { g_notready_done = 1; return 0xA102; }
  char buf[64]; int n = snprintf(buf, sizeof buf, "\xFF\xD8LIVE-%03d\xFF\xD9", ++g_frames);
  sset((Obj*)((Obj*)evf)->stream, buf, (U64)n); return 0; }

EXPORT U32 EdsGetDirectoryItemInfo(Ref item, void* buf) {
  (void)item; memset(buf, 0, 512);
  *(U64*)buf = (U64)(strlen(kPhoto));        /* size @0 (u64) */
  strcpy((char*)buf + 20, "IMG_0001.JPG");   /* nama @20 (layout SDK baru) */
  return 0; }
EXPORT U32 EdsDownload(Ref item, U64 size, Ref stream) {
  (void)item; sset((Obj*)stream, kPhoto, size); return 0; }
EXPORT U32 EdsDownloadComplete(Ref item) { (void)item; return 0; }
EXPORT U32 EdsGetVolumeInfo(Ref v, void* buf) {
  (void)v; memset(buf, 0, 512);
  *(U64*)((char*)buf + 8) = 64ULL << 30; *(U64*)((char*)buf + 16) = 12345ULL << 20; return 0; }

/* hook uji: atur kamera hadir (1) / dicabut (0) saat runtime */
EXPORT void mock_set_present(int v) { g_present = v; }
/* hook uji: baca state internal */
EXPORT U32 mock_state(U32 what) {
  switch (what) { case 0: return g_save_to; case 1: return g_evf_dev; case 2: return g_iso;
    case 3: return g_av; case 4: return g_tv; case 5: return g_wb; case 6: return (U32)g_cap_set;
    case 7: return (U32)g_cap[0]; case 8: return (U32)g_cap[1]; case 9: return (U32)g_cap[2];
    case 10: return (U32)g_session; case 11: return g_evf_mode; case 12: return g_last_af; }
  return 0; }
