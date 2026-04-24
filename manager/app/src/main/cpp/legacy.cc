//
// Legacy compatibility fallback for pre-ioctl KernelSU interfaces.
//

#include <android/log.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

#include "ksu.h"

namespace {

constexpr int KERNEL_SU_OPTION = 0xDEADBEEF;

constexpr int CMD_GET_VERSION = 2;
constexpr int CMD_GET_SU_LIST = 5;
constexpr int CMD_CHECK_SAFEMODE = 9;
constexpr int CMD_GET_APP_PROFILE = 10;
constexpr int CMD_SET_APP_PROFILE = 11;
constexpr int CMD_IS_UID_SHOULD_UMOUNT = 13;
constexpr int CMD_IS_SU_ENABLED = 14;
constexpr int CMD_ENABLE_SU = 15;
constexpr int CMD_GET_VERSION_FULL = 0xC0FFEE1A;
constexpr int CMD_HOOK_TYPE = 101;

bool legacy_ctl(int cmd, void *arg1, void *arg2) {
    int32_t result = 0;
    int32_t rtn = prctl(KERNEL_SU_OPTION, cmd, arg1, arg2, &result);
    return rtn == 0 && result == KERNEL_SU_OPTION;
}

} // namespace

bool legacy_get_allow_list(int *uids, int *size) {
    return legacy_ctl(CMD_GET_SU_LIST, uids, size);
}

bool legacy_is_safe_mode() {
    return legacy_ctl(CMD_CHECK_SAFEMODE, nullptr, nullptr);
}

bool legacy_uid_should_umount(int uid) {
    int should = 0;
    return legacy_ctl(CMD_IS_UID_SHOULD_UMOUNT, reinterpret_cast<void *>(static_cast<intptr_t>(uid)), &should) && should != 0;
}

bool legacy_set_app_profile(const app_profile *profile) {
    return legacy_ctl(CMD_SET_APP_PROFILE, const_cast<app_profile *>(profile), nullptr);
}

bool legacy_get_app_profile(char *key, app_profile *profile) {
    (void) key;
    return legacy_ctl(CMD_GET_APP_PROFILE, profile, nullptr);
}

bool legacy_set_su_enabled(bool enabled) {
    return legacy_ctl(CMD_ENABLE_SU, reinterpret_cast<void *>(static_cast<intptr_t>(enabled)), nullptr);
}

bool legacy_is_su_enabled() {
    int enabled = 1;
    legacy_ctl(CMD_IS_SU_ENABLED, &enabled, nullptr);
    return enabled != 0;
}

bool legacy_get_hook_type(char *hook_type, std::size_t size) {
    if (hook_type == nullptr || size == 0) {
        return false;
    }

    static char cached_hook_type[16] = {0};
    if (cached_hook_type[0] == '\0') {
        if (!legacy_ctl(CMD_HOOK_TYPE, cached_hook_type, nullptr)) {
            strcpy(cached_hook_type, "Unknown");
        }
    }

    strncpy(hook_type, cached_hook_type, size - 1);
    hook_type[size - 1] = '\0';
    return true;
}

void legacy_get_full_version(char *buff) {
    legacy_ctl(CMD_GET_VERSION_FULL, buff, nullptr);
}
