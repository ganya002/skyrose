// skyrose-sa-loader: loads the SkyRose scripting addition into the invoking user's Dock.
//
// Run as root (sudo), once per boot. It takes no arguments on purpose: it only ever loads
// SkyRoseSA.dylib from its own directory, and only into the Dock of the user who ran sudo.
// Needs SIP's Debugging Restrictions off (task_for_pid on the Dock) and, on Apple Silicon, the
// -arm64e_preview_abi boot argument (a third-party arm64e dylib in an Apple process).
//
// Steps: find Dock (path + uid) → task_for_pid → allocate a read-execute code page with the
// trampoline and a read-write data page with the addresses it calls → create a thread whose
// state is converted to the Dock's pointer-authentication keys → wait for the trampoline's
// `done` flag → terminate that bare thread. The payload then runs on its own pthread.
//
// Written for SkyRose from the public Mach and dyld APIs; the approach is the one yabai made
// known (task port + pthread_create_from_mach_thread), not its code.

#include <dlfcn.h>
#include <libproc.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/thread_status.h>
#include <ptrauth.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

extern char skyrose_sa_trampoline_start[];
extern char skyrose_sa_trampoline_end[];

#define DOCK_PATH "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"
#define PAYLOAD_NAME "SkyRoseSA.dylib"
#define START_SYMBOL "skyrose_sa_start"
#define STACK_SIZE (64 * 1024)
#define DATA_SIZE 4096

static int fail(const char *what, kern_return_t kr) {
    fprintf(stderr, "skyrose-sa-loader: %s failed (%s, %d)\n", what, mach_error_string(kr), kr);
    return 1;
}

static uint64_t strip(void *p) { return (uint64_t)ptrauth_strip(p, ptrauth_key_function_pointer); }

static pid_t find_dock(uid_t uid) {
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return 0;
    pid_t *pids = calloc((size_t)count * 2, sizeof(pid_t));
    count = proc_listallpids(pids, count * 2 * (int)sizeof(pid_t));
    pid_t found = 0;
    for (int i = 0; i < count && !found; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[i], path, sizeof(path)) <= 0 || strcmp(path, DOCK_PATH) != 0) continue;
        struct proc_bsdinfo info;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) continue;
        if (info.pbi_uid == uid) found = pids[i];
    }
    free(pids);
    return found;
}

int main(int argc, char **argv) {
    (void)argv;
    if (argc != 1) {
        fprintf(stderr, "usage: sudo skyrose-sa-loader   (no arguments)\n");
        return 2;
    }
    if (geteuid() != 0) {
        fprintf(stderr, "skyrose-sa-loader: run it with sudo (it needs the Dock's task port)\n");
        return 2;
    }
    const char *sudo_uid = getenv("SUDO_UID");
    uid_t uid = sudo_uid ? (uid_t)strtoul(sudo_uid, NULL, 10) : getuid();
    if (uid == 0) {
        fprintf(stderr, "skyrose-sa-loader: run it with sudo from your own account, not as root\n");
        return 2;
    }

    // The payload sits next to this executable (…/Contents/Resources/sa/).
    char self[PATH_MAX], real[PATH_MAX], payload[PATH_MAX];
    uint32_t size = sizeof(self);
    if (_NSGetExecutablePath(self, &size) != 0 || !realpath(self, real)) {
        fprintf(stderr, "skyrose-sa-loader: cannot resolve its own path\n");
        return 1;
    }
    char *slash = strrchr(real, '/');
    if (!slash) return 1;
    *slash = 0;
    snprintf(payload, sizeof(payload), "%s/%s", real, PAYLOAD_NAME);
    struct stat st;
    if (stat(payload, &st) != 0 || !S_ISREG(st.st_mode)) {
        fprintf(stderr, "skyrose-sa-loader: %s is missing\n", payload);
        return 1;
    }
    if (strlen(payload) >= DATA_SIZE - 80) return 1;

    pid_t dock = find_dock(uid);
    if (!dock) {
        fprintf(stderr, "skyrose-sa-loader: no Dock running for uid %u\n", uid);
        return 1;
    }

    task_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), dock, &task);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "skyrose-sa-loader: task_for_pid(Dock) was refused: SIP's Debugging Restrictions must be off\n");
        return fail("task_for_pid", kr);
    }

    // Data page (read-write): addresses + names the trampoline uses.
    uint8_t data[DATA_SIZE];
    memset(data, 0, sizeof(data));
    uint64_t addrs[3] = {
        strip(dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread")),
        strip(dlsym(RTLD_DEFAULT, "dlopen")),
        strip(dlsym(RTLD_DEFAULT, "dlsym")),
    };
    if (!addrs[0] || !addrs[1] || !addrs[2]) {
        fprintf(stderr, "skyrose-sa-loader: libSystem symbols not found\n");
        return 1;
    }
    memcpy(data, addrs, sizeof(addrs));
    strlcpy((char *)data + 40, START_SYMBOL, 40);
    strlcpy((char *)data + 80, payload, DATA_SIZE - 80);

    size_t code_len = (size_t)(skyrose_sa_trampoline_end - skyrose_sa_trampoline_start);
    mach_vm_address_t code = 0, remote_data = 0, stack = 0;
    if ((kr = mach_vm_allocate(task, &code, vm_page_size, VM_FLAGS_ANYWHERE)) != KERN_SUCCESS) return fail("allocate code", kr);
    if ((kr = mach_vm_allocate(task, &remote_data, DATA_SIZE, VM_FLAGS_ANYWHERE)) != KERN_SUCCESS) return fail("allocate data", kr);
    if ((kr = mach_vm_allocate(task, &stack, STACK_SIZE, VM_FLAGS_ANYWHERE)) != KERN_SUCCESS) return fail("allocate stack", kr);
    void *code_src = ptrauth_strip((void *)skyrose_sa_trampoline_start, ptrauth_key_function_pointer);
    if ((kr = mach_vm_write(task, code, (vm_offset_t)code_src, (mach_msg_type_number_t)code_len)) != KERN_SUCCESS) return fail("write code", kr);
    if ((kr = mach_vm_write(task, remote_data, (vm_offset_t)data, DATA_SIZE)) != KERN_SUCCESS) return fail("write data", kr);
    if ((kr = mach_vm_protect(task, code, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE)) != KERN_SUCCESS) return fail("protect code", kr);

    thread_act_t thread = MACH_PORT_NULL;
    if ((kr = thread_create(task, &thread)) != KERN_SUCCESS) return fail("thread_create", kr);

    arm_thread_state64_t local;
    memset(&local, 0, sizeof(local));
    __darwin_arm_thread_state64_set_pc_fptr(local, ptrauth_sign_unauthenticated((void *)code, ptrauth_key_function_pointer, 0));
    __darwin_arm_thread_state64_set_sp(local, (void *)((stack + STACK_SIZE - 64) & ~(uint64_t)15));
    local.__x[0] = remote_data;

    arm_thread_state64_t remote;
    mach_msg_type_number_t remote_count = ARM_THREAD_STATE64_COUNT;
    kr = thread_convert_thread_state(thread, THREAD_CONVERT_THREAD_STATE_FROM_SELF, ARM_THREAD_STATE64,
                                     (thread_state_t)&local, ARM_THREAD_STATE64_COUNT,
                                     (thread_state_t)&remote, &remote_count);
    if (kr != KERN_SUCCESS) return fail("thread_convert_thread_state", kr);
    if ((kr = thread_set_state(thread, ARM_THREAD_STATE64, (thread_state_t)&remote, remote_count)) != KERN_SUCCESS) return fail("thread_set_state", kr);
    if ((kr = thread_resume(thread)) != KERN_SUCCESS) return fail("thread_resume", kr);

    // Wait for the trampoline to hand over to its pthread (≤ 2 s), then stop the bare thread.
    int done = 0;
    for (int i = 0; i < 200 && !done; i++) {
        usleep(10000);
        uint32_t flag = 0;
        mach_vm_size_t got = 0;
        if (mach_vm_read_overwrite(task, remote_data + 32, sizeof(flag), (mach_vm_address_t)&flag, &got) == KERN_SUCCESS && flag == 1) done = 1;
    }
    thread_terminate(thread);
    mach_port_deallocate(mach_task_self(), thread);
    mach_port_deallocate(mach_task_self(), task);
    if (!done) {
        fprintf(stderr, "skyrose-sa-loader: the Dock did not start the payload (stopped it again)\n");
        return 1;
    }
    printf("skyrose-sa-loader: loaded %s into the Dock (pid %d)\n", payload, dock);
    return 0;
}
