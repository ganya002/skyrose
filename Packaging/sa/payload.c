// SkyRoseSA.dylib: the SkyRose scripting addition, loaded into the Dock by skyrose-sa-loader.
//
// The Dock owns the window server's "universal owner" connection, so SkyLight calls made from
// here may change any app's windows: alpha, shadow, level, transform (real-window animations)
// and Space membership. Everything is driven over a Unix socket only the user can open
// (/tmp/skyrose-sa-<uid>.socket, mode 0600), one text command per line:
//
//   hello                                   → ok skyrose-sa <version> <capabilities>
//   alpha <wid> <0..1>
//   shadow <wid> <0|1>
//   level <wid> <level> | level-reset <wid>
//   visual <wid> <x> <y> <w> <h> [alpha] ;… show the window in that rect (global top-left points)
//   visual-reset <wid> [wid…]               transform only (the client sets the final alpha)
//   info <wid>                              → ok <bounds> <transform> <alpha> <level>
//   space <wid> <space id|current>
//   freeze | thaw                           hold screen updates (a frame write + its first
//                                           transform in one update); auto-thaw after 250 ms
//   reset                                   restore every window SkyRose changed
//   stop                                    reset everything, close the socket (reload restarts)
//
// Safety: every change is recorded with its original value and the connection that made it;
// when that connection closes (SkyRose quit or crashed) the changes are undone. `skyrose wm panic`
// sends `reset` + `stop`. All SkyLight symbols are looked up at run time; a missing one only
// removes that capability (the WM then keeps its SIP-on path).

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define SA_VERSION "1"
#define MAX_TRACKED 1024

typedef int CID;
typedef CID (*f_main_connection)(void);
typedef CGError (*f_set_alpha)(CID, uint32_t, float);
typedef CGError (*f_get_alpha)(CID, uint32_t, float *);
typedef CGError (*f_set_level)(CID, uint32_t, int);
typedef CGError (*f_get_level)(CID, uint32_t, int *);
typedef CGError (*f_set_transform)(CID, uint32_t, CGAffineTransform);
typedef CGError (*f_get_transform)(CID, uint32_t, CGAffineTransform *);
typedef CGError (*f_get_bounds)(CID, uint32_t, CGRect *);
typedef CGError (*f_tags)(CID, uint32_t, uint64_t *, int);
typedef CGError (*f_update)(CID);
typedef uint64_t (*f_active_space)(CID);
typedef void (*f_move_to_space)(CID, CFArrayRef, uint64_t);

static struct {
    f_main_connection main_connection;
    f_set_alpha set_alpha;
    f_get_alpha get_alpha;
    f_set_level set_level;
    f_get_level get_level;
    f_set_transform set_transform;
    f_get_transform get_transform;
    f_get_bounds get_bounds;
    f_tags set_tags, clear_tags;
    f_update disable_update, reenable_update;
    f_active_space active_space;
    f_move_to_space move_to_space;
} sls;

enum { T_ALPHA = 1, T_LEVEL = 2, T_TRANSFORM = 4, T_SHADOW = 8 };

typedef struct {
    uint32_t wid;
    int owner;  // connection serial
    int what;   // T_* bits changed
    float alpha;
    int level;
} tracked_t;

static tracked_t tracked[MAX_TRACKED];
static int tracked_count;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static atomic_int running;
static int listen_fd = -1;
static char socket_path[104];
static CID cid;
static int freeze_depth;
static uint64_t freeze_deadline_ms;

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

/// Call with `lock` held.
static void thaw_all(void) {
    while (freeze_depth > 0) {
        if (sls.reenable_update) sls.reenable_update(cid);
        freeze_depth--;
    }
}

static void *sym(const char *name) {
    static void *skylight;
    if (!skylight) skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_NOLOAD);
    if (!skylight) skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    return skylight ? dlsym(skylight, name) : NULL;
}

static void resolve(void) {
    sls.main_connection = (f_main_connection)sym("SLSMainConnectionID");
    sls.set_alpha = (f_set_alpha)sym("SLSSetWindowAlpha");
    sls.get_alpha = (f_get_alpha)sym("SLSGetWindowAlpha");
    sls.set_level = (f_set_level)sym("SLSSetWindowLevel");
    sls.get_level = (f_get_level)sym("SLSGetWindowLevel");
    sls.set_transform = (f_set_transform)sym("SLSSetWindowTransform");
    sls.get_transform = (f_get_transform)sym("SLSGetWindowTransform");
    sls.get_bounds = (f_get_bounds)sym("SLSGetWindowBounds");
    sls.set_tags = (f_tags)sym("SLSSetWindowTags");
    sls.clear_tags = (f_tags)sym("SLSClearWindowTags");
    sls.disable_update = (f_update)sym("SLSDisableUpdate");
    sls.reenable_update = (f_update)sym("SLSReenableUpdate");
    sls.active_space = (f_active_space)sym("SLSGetActiveSpace");
    sls.move_to_space = (f_move_to_space)sym("SLSMoveWindowsToManagedSpace");
    cid = sls.main_connection ? sls.main_connection() : 0;
}

static void capabilities(char *out, size_t n) {
    out[0] = 0;
    if (!cid) { strlcpy(out, "none", n); return; }
    if (sls.set_alpha && sls.get_alpha) strlcat(out, "alpha,", n);
    if (sls.set_tags && sls.clear_tags) strlcat(out, "shadow,", n);
    if (sls.set_level && sls.get_level) strlcat(out, "level,", n);
    if (sls.set_transform && sls.get_bounds) strlcat(out, "transform,", n);
    if (sls.move_to_space && sls.active_space) strlcat(out, "space,", n);
    size_t len = strlen(out);
    if (len) out[len - 1] = 0; else strlcpy(out, "none", n);
}

// MARK: tracking (call with `lock` held)

static tracked_t *track(uint32_t wid, int owner, int what) {
    for (int i = 0; i < tracked_count; i++) {
        if (tracked[i].wid == wid) {
            tracked_t *t = &tracked[i];
            if (!(t->what & what)) {
                if ((what & T_ALPHA) && sls.get_alpha) { float a = 1; if (sls.get_alpha(cid, wid, &a) == kCGErrorSuccess) t->alpha = a; }
                if ((what & T_LEVEL) && sls.get_level) { int l = 0; if (sls.get_level(cid, wid, &l) == kCGErrorSuccess) t->level = l; }
            }
            t->what |= what;
            t->owner = owner;
            return t;
        }
    }
    if (tracked_count >= MAX_TRACKED) return NULL;
    tracked_t *t = &tracked[tracked_count++];
    memset(t, 0, sizeof(*t));
    t->wid = wid;
    t->owner = owner;
    t->alpha = 1;
    if ((what & T_ALPHA) && sls.get_alpha) sls.get_alpha(cid, wid, &t->alpha);
    if ((what & T_LEVEL) && sls.get_level) sls.get_level(cid, wid, &t->level);
    t->what = what;
    return t;
}

static void reset_transform(uint32_t wid) {
    CGRect b;
    if (!sls.set_transform || !sls.get_bounds || sls.get_bounds(cid, wid, &b) != kCGErrorSuccess) return;
    sls.set_transform(cid, wid, CGAffineTransformMakeTranslation(-b.origin.x, -b.origin.y));
}

static void restore(tracked_t *t, int what) {
    int w = t->what & what;
    if ((w & T_TRANSFORM)) reset_transform(t->wid);
    if ((w & T_ALPHA) && sls.set_alpha) sls.set_alpha(cid, t->wid, t->alpha);
    if ((w & T_LEVEL) && sls.set_level) sls.set_level(cid, t->wid, t->level);
    if ((w & T_SHADOW) && sls.clear_tags) { uint64_t tags = 1ULL << 3; sls.clear_tags(cid, t->wid, &tags, 64); }
    t->what &= ~w;
}

static void compact(void) {
    int j = 0;
    for (int i = 0; i < tracked_count; i++) if (tracked[i].what) tracked[j++] = tracked[i];
    tracked_count = j;
}

/// owner < 0: everything.
static void reset_owner(int owner) {
    if (sls.disable_update) sls.disable_update(cid);
    for (int i = 0; i < tracked_count; i++) {
        if (owner < 0 || tracked[i].owner == owner) restore(&tracked[i], T_ALPHA | T_LEVEL | T_TRANSFORM | T_SHADOW);
    }
    compact();
    if (sls.reenable_update) sls.reenable_update(cid);
}

// MARK: commands

static void reply(int fd, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void reply(int fd, const char *fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf) - 1, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if (n > (int)sizeof(buf) - 2) n = (int)sizeof(buf) - 2;
    buf[n++] = '\n';
    ssize_t off = 0;
    while (off < n) {
        ssize_t w = write(fd, buf + off, (size_t)(n - off));
        if (w <= 0) return;
        off += w;
    }
}

/// One "visual" entry: show `wid` in the rect (global top-left points) instead of its bounds.
static int apply_visual(char *entry, int owner) {
    unsigned wid = 0;
    double x, y, w, h, a = -1;
    int n = sscanf(entry, "%u %lf %lf %lf %lf %lf", &wid, &x, &y, &w, &h, &a);
    if (n < 5 || !wid || w <= 1 || h <= 1) return 0;
    CGRect b;
    if (sls.get_bounds(cid, wid, &b) != kCGErrorSuccess || b.size.width <= 0 || b.size.height <= 0) return 0;
    // The window transform maps screen points to window points: q = (p - V.origin) * (B / V).
    double sx = b.size.width / w, sy = b.size.height / h;
    CGAffineTransform t = { .a = sx, .b = 0, .c = 0, .d = sy, .tx = -x * sx, .ty = -y * sy };
    int what = T_TRANSFORM | (n == 6 && a >= 0 && sls.set_alpha ? T_ALPHA : 0);
    track(wid, owner, what);
    sls.set_transform(cid, wid, t);
    if (what & T_ALPHA) sls.set_alpha(cid, wid, (float)(a > 1 ? 1 : a));
    return 1;
}

static void handle(int fd, char *line, int owner) {
    char cmd[32] = {0};
    sscanf(line, "%31s", cmd);
    char *args = line + strlen(cmd);
    while (*args == ' ') args++;
    unsigned wid = 0;

    if (!strcmp(cmd, "hello")) {
        char caps[128];
        capabilities(caps, sizeof(caps));
        reply(fd, "ok skyrose-sa %s %s", SA_VERSION, caps);
    } else if (!strcmp(cmd, "alpha")) {
        float a = 1;
        if (!sls.set_alpha || sscanf(args, "%u %f", &wid, &a) != 2) { reply(fd, "err alpha"); return; }
        pthread_mutex_lock(&lock);
        track(wid, owner, T_ALPHA);
        CGError e = sls.set_alpha(cid, wid, a < 0 ? 0 : a > 1 ? 1 : a);
        pthread_mutex_unlock(&lock);
        reply(fd, e == kCGErrorSuccess ? "ok" : "err %d", e);
    } else if (!strcmp(cmd, "shadow")) {
        int on = 1;
        if (!sls.set_tags || sscanf(args, "%u %d", &wid, &on) != 2) { reply(fd, "err shadow"); return; }
        uint64_t tags = 1ULL << 3;  // "no shadow" window tag
        pthread_mutex_lock(&lock);
        CGError e;
        if (on) {
            e = sls.clear_tags(cid, wid, &tags, 64);
            for (int i = 0; i < tracked_count; i++) if (tracked[i].wid == wid) tracked[i].what &= ~T_SHADOW;
            compact();
        } else {
            track(wid, owner, T_SHADOW);
            e = sls.set_tags(cid, wid, &tags, 64);
        }
        pthread_mutex_unlock(&lock);
        reply(fd, e == kCGErrorSuccess ? "ok" : "err %d", e);
    } else if (!strcmp(cmd, "level")) {
        int level = 0;
        if (!sls.set_level || sscanf(args, "%u %d", &wid, &level) != 2) { reply(fd, "err level"); return; }
        pthread_mutex_lock(&lock);
        track(wid, owner, T_LEVEL);
        CGError e = sls.set_level(cid, wid, level);
        pthread_mutex_unlock(&lock);
        reply(fd, e == kCGErrorSuccess ? "ok" : "err %d", e);
    } else if (!strcmp(cmd, "level-reset")) {
        if (sscanf(args, "%u", &wid) != 1) { reply(fd, "err level-reset"); return; }
        pthread_mutex_lock(&lock);
        for (int i = 0; i < tracked_count; i++) if (tracked[i].wid == wid) restore(&tracked[i], T_LEVEL);
        compact();
        pthread_mutex_unlock(&lock);
        reply(fd, "ok");
    } else if (!strcmp(cmd, "visual")) {
        if (!sls.set_transform || !sls.get_bounds) { reply(fd, "err transform"); return; }
        int applied = 0;
        pthread_mutex_lock(&lock);
        if (sls.disable_update) sls.disable_update(cid);
        char *save = NULL;
        for (char *e = strtok_r(args, ";", &save); e; e = strtok_r(NULL, ";", &save)) applied += apply_visual(e, owner);
        if (sls.reenable_update) sls.reenable_update(cid);
        pthread_mutex_unlock(&lock);
        reply(fd, "ok %d", applied);
    } else if (!strcmp(cmd, "visual-reset")) {
        pthread_mutex_lock(&lock);
        if (sls.disable_update) sls.disable_update(cid);
        char *save = NULL;
        for (char *e = strtok_r(args, " ", &save); e; e = strtok_r(NULL, " ", &save)) {
            uint32_t w = (uint32_t)strtoul(e, NULL, 10);
            for (int i = 0; i < tracked_count; i++) if (tracked[i].wid == w) restore(&tracked[i], T_TRANSFORM);
        }
        compact();
        if (sls.reenable_update) sls.reenable_update(cid);
        pthread_mutex_unlock(&lock);
        reply(fd, "ok");
    } else if (!strcmp(cmd, "info")) {
        if (sscanf(args, "%u", &wid) != 1 || !sls.get_bounds) { reply(fd, "err info"); return; }
        CGRect b = CGRectZero;
        CGAffineTransform t = CGAffineTransformIdentity;
        float a = -1;
        int l = 0;
        sls.get_bounds(cid, wid, &b);
        if (sls.get_transform) sls.get_transform(cid, wid, &t);
        if (sls.get_alpha) sls.get_alpha(cid, wid, &a);
        if (sls.get_level) sls.get_level(cid, wid, &l);
        reply(fd, "ok bounds=%.1f,%.1f,%.1f,%.1f transform=%.4f,%.4f,%.4f,%.4f,%.1f,%.1f alpha=%.3f level=%d",
              b.origin.x, b.origin.y, b.size.width, b.size.height, t.a, t.b, t.c, t.d, t.tx, t.ty, a, l);
    } else if (!strcmp(cmd, "space")) {
        char target[32] = {0};
        if (!sls.move_to_space || !sls.active_space || sscanf(args, "%u %31s", &wid, target) != 2) { reply(fd, "err space"); return; }
        uint64_t sid = !strcmp(target, "current") ? sls.active_space(cid) : strtoull(target, NULL, 10);
        if (!sid) { reply(fd, "err no space"); return; }
        int32_t w = (int32_t)wid;
        CFNumberRef num = CFNumberCreate(NULL, kCFNumberSInt32Type, &w);
        CFArrayRef list = CFArrayCreate(NULL, (const void **)&num, 1, &kCFTypeArrayCallBacks);
        sls.move_to_space(cid, list, sid);
        CFRelease(list);
        CFRelease(num);
        reply(fd, "ok %llu", (unsigned long long)sid);
    } else if (!strcmp(cmd, "freeze")) {
        if (!sls.disable_update || !sls.reenable_update) { reply(fd, "err freeze"); return; }
        pthread_mutex_lock(&lock);
        if (freeze_depth < 4) {
            sls.disable_update(cid);
            freeze_depth++;
            freeze_deadline_ms = now_ms() + 250;
        }
        pthread_mutex_unlock(&lock);
        reply(fd, "ok");
    } else if (!strcmp(cmd, "thaw")) {
        pthread_mutex_lock(&lock);
        thaw_all();
        pthread_mutex_unlock(&lock);
        reply(fd, "ok");
    } else if (!strcmp(cmd, "reset")) {
        pthread_mutex_lock(&lock);
        reset_owner(-1);
        pthread_mutex_unlock(&lock);
        reply(fd, "ok");
    } else if (!strcmp(cmd, "stop")) {
        pthread_mutex_lock(&lock);
        thaw_all();
        reset_owner(-1);
        pthread_mutex_unlock(&lock);
        reply(fd, "ok");
        atomic_store(&running, 0);
        if (listen_fd >= 0) { shutdown(listen_fd, SHUT_RDWR); close(listen_fd); listen_fd = -1; }
        unlink(socket_path);
    } else {
        reply(fd, "err unknown command");
    }
}

typedef struct { int fd; int serial; } conn_t;

static void *connection(void *arg) {
    conn_t c = *(conn_t *)arg;
    free(arg);
    char buf[16384];
    size_t used = 0;
    for (;;) {
        ssize_t n = read(c.fd, buf + used, sizeof(buf) - 1 - used);
        if (n <= 0) break;
        used += (size_t)n;
        buf[used] = 0;
        char *start = buf, *nl;
        while ((nl = strchr(start, '\n'))) {
            *nl = 0;
            if (*start) handle(c.fd, start, c.serial);
            start = nl + 1;
        }
        used = strlen(start);
        memmove(buf, start, used);
        if (used >= sizeof(buf) - 1) used = 0;  // a runaway line: drop it
    }
    close(c.fd);
    // The client went away (SkyRose quit or crashed): undo what it changed.
    pthread_mutex_lock(&lock);
    thaw_all();
    reset_owner(c.serial);
    pthread_mutex_unlock(&lock);
    return NULL;
}

static void *server(void *unused) {
    (void)unused;
    static int serial;
    while (atomic_load(&running)) {
        int fd = accept(listen_fd, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR) continue;
            break;
        }
        // Only the user who owns this Dock may talk to it.
        uid_t euid; gid_t egid;
        if (getpeereid(fd, &euid, &egid) != 0 || (euid != getuid() && euid != 0)) { close(fd); continue; }
        conn_t *c = malloc(sizeof(conn_t));
        c->fd = fd;
        c->serial = ++serial;
        pthread_t t;
        if (pthread_create(&t, NULL, connection, c) == 0) pthread_detach(t); else { close(fd); free(c); }
    }
    return NULL;
}

/// Never lets a freeze outlive its deadline (a client that froze and then hung).
static void *watchdog(void *unused) {
    (void)unused;
    while (atomic_load(&running)) {
        usleep(50000);
        pthread_mutex_lock(&lock);
        if (freeze_depth > 0 && now_ms() > freeze_deadline_ms) thaw_all();
        pthread_mutex_unlock(&lock);
    }
    pthread_mutex_lock(&lock);
    thaw_all();
    pthread_mutex_unlock(&lock);
    return NULL;
}

/// Called by the loader's trampoline after every load (dlopen of an already loaded image does
/// not run the constructor again, so a reload after `stop` restarts the server here).
__attribute__((visibility("default"))) void skyrose_sa_start(void) {
    if (atomic_exchange(&running, 1)) return;
    resolve();
    const char *override = getenv("SKYROSE_SA_SOCKET");  // test hosts only; unset in the Dock
    if (override && *override) strlcpy(socket_path, override, sizeof(socket_path));
    else snprintf(socket_path, sizeof(socket_path), "/tmp/skyrose-sa-%u.socket", getuid());
    unlink(socket_path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { atomic_store(&running, 0); return; }
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, socket_path, sizeof(addr.sun_path));
    mode_t old = umask(0077);
    int ok = bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0 && listen(fd, 8) == 0;
    umask(old);
    if (!ok) { close(fd); atomic_store(&running, 0); return; }
    chmod(socket_path, 0600);
    listen_fd = fd;
    pthread_t t;
    if (pthread_create(&t, NULL, server, NULL) == 0) pthread_detach(t);
    if (pthread_create(&t, NULL, watchdog, NULL) == 0) pthread_detach(t);
}
