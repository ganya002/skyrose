#ifndef CSHIMS_H
#define CSHIMS_H

#include <stdbool.h>
#include <stdint.h>
#include <ApplicationServices/ApplicationServices.h>

#ifdef __cplusplus
extern "C" {
#endif

CF_ASSUME_NONNULL_BEGIN

/*
 * Private symbols used by Caelestia for Mac.
 *
 * Every declaration here is weak-linked so that a macOS release that removes a symbol
 * yields a NULL function pointer instead of a dyld abort at launch. Swift code must never
 * call the raw symbols; it goes through the caelestia_* wrappers, which perform the NULL
 * check.
 */

/* ------------------------------------------------------------------------------------ */
/* HIServices (ApplicationServices)                                                      */
/* ------------------------------------------------------------------------------------ */

/*
 * Returns the CGWindowID backing an accessibility window element. Private, but exported by
 * HIServices since macOS 10.x and relied on by AeroSpace, yabai and Rectangle. Works with
 * SIP fully enabled; it only needs the Accessibility permission the caller already has.
 */
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *outWindowID)
    __attribute__((weak_import));

/*
 * Safe wrapper: false when the symbol is unavailable, the call fails, or the element has no
 * window (window id 0). On success *outWindowID receives the id.
 */
bool caelestia_ax_window_id(AXUIElementRef element, CGWindowID *outWindowID);

/* ------------------------------------------------------------------------------------ */
/* SkyLight (private framework; Enhanced mode only)                                      */
/* ------------------------------------------------------------------------------------ */

typedef int CGSConnectionID;

/*
 * Declared for the Enhanced module, which will probe them at runtime. They are NOT referenced
 * by this module's object code, so nothing here forces a link against SkyLight. A target that
 * does call them directly must add
 *   -F <SDK>/System/Library/PrivateFrameworks -weak_framework SkyLight
 * to its linker settings (the SDK ships only a .tbd stub for SkyLight).
 */
extern CGSConnectionID SLSMainConnectionID(void) __attribute__((weak_import));
extern CGError SLSGetWindowAlpha(CGSConnectionID cid, uint32_t wid, float *outAlpha) __attribute__((weak_import));
extern CGError SLSSetWindowAlpha(CGSConnectionID cid, uint32_t wid, float alpha) __attribute__((weak_import));
extern CGError SLSGetWindowLevel(CGSConnectionID cid, uint32_t wid, int *outLevel) __attribute__((weak_import));
extern CGError SLSSetWindowLevel(CGSConnectionID cid, uint32_t wid, int level) __attribute__((weak_import));

/*
 * True when SLSMainConnectionID is resolvable in this process (SkyLight is loaded by every
 * AppKit process). Only checks presence of the symbol; it never calls into SkyLight.
 */
bool caelestia_skylight_available(void);

CF_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

#endif /* CSHIMS_H */
