#include "CShims.h"

#include <dlfcn.h>
#include <stddef.h>

bool caelestia_ax_window_id(AXUIElementRef element, CGWindowID *outWindowID) {
    if (element == NULL || outWindowID == NULL) {
        return false;
    }
    /* Weak import: the address is NULL when the running macOS no longer exports the symbol. */
    if (&_AXUIElementGetWindow == NULL) {
        return false;
    }
    CGWindowID windowID = 0;
    AXError error = _AXUIElementGetWindow(element, &windowID);
    if (error != kAXErrorSuccess || windowID == 0) {
        return false;
    }
    *outWindowID = windowID;
    return true;
}

bool caelestia_skylight_available(void) {
    /* dlsym keeps this module free of any link-time dependency on the private framework. */
    return dlsym(RTLD_DEFAULT, "SLSMainConnectionID") != NULL;
}
