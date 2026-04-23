#!/bin/sh
set -eu

GKI_ROOT=$(pwd)
KSU_MANAGER_PACKAGE_DEFAULT="com.google.android.keys"
KSU_EXPECTED_SIZE_DEFAULT="0x410"
KSU_EXPECTED_HASH_DEFAULT="4441f77a2cb231419baedba91fc175d0635b4d485c8d792f31381a3cbc6007e6"

display_usage() {
    echo "Usage: $0 [--cleanup | <commit-or-tag>]"
    echo "  --cleanup:              Cleans up previous modifications made by the script."
    echo "  <commit-or-tag>:        Sets up or updates the KernelSU to specified tag or commit."
    echo "  -h, --help:             Displays this usage information."
    echo "  (no args):              Sets up or updates the KernelSU environment to the latest tagged version."
}

ensure_manager_identity_defaults() {
    KBUILD_FILE="$GKI_ROOT/KernelSU/kernel/Kbuild"
    if [ ! -f "$KBUILD_FILE" ]; then
        echo "[-] Skip manager identity patch: kernel/Kbuild not found."
        return 0
    fi

    python3 - "$KBUILD_FILE" "$KSU_EXPECTED_SIZE_DEFAULT" "$KSU_EXPECTED_HASH_DEFAULT" "$KSU_MANAGER_PACKAGE_DEFAULT" <<'PY'
from pathlib import Path
import re
import sys

kbuild_path = Path(sys.argv[1])
expected_size = sys.argv[2]
expected_hash = sys.argv[3]
manager_package = sys.argv[4]

content = kbuild_path.read_text(encoding="utf-8")
original = content

patterns = [
    (
        r"(ifndef KSU_EXPECTED_SIZE\s*\n)KSU_EXPECTED_SIZE := .*(\nendif)",
        rf"\1KSU_EXPECTED_SIZE := {expected_size}\2",
    ),
    (
        r"(ifndef KSU_EXPECTED_HASH\s*\n)KSU_EXPECTED_HASH := .*(\nendif)",
        rf"\1KSU_EXPECTED_HASH := {expected_hash}\2",
    ),
]

for pattern, replacement in patterns:
    content, count = re.subn(pattern, replacement, content, count=1, flags=re.MULTILINE)
    if count == 0:
        raise SystemExit(f"Failed to patch pattern: {pattern}")

if "ifndef KSU_MANAGER_PACKAGE" in content:
    content, count = re.subn(
        r"(ifndef KSU_MANAGER_PACKAGE\s*\n)KSU_MANAGER_PACKAGE := .*(\nendif)",
        rf"\1KSU_MANAGER_PACKAGE := {manager_package}\2",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count == 0:
        raise SystemExit("Failed to patch KSU_MANAGER_PACKAGE block")
else:
    anchor = "ifdef KSU_MANAGER_PACKAGE\n"
    insert = (
        f"ifndef KSU_MANAGER_PACKAGE\n"
        f"KSU_MANAGER_PACKAGE := {manager_package}\n"
        f"endif\n\n"
    )
    if anchor not in content:
        raise SystemExit("Failed to find KSU_MANAGER_PACKAGE anchor")
    content = content.replace(anchor, insert + anchor, 1)

if content != original:
    kbuild_path.write_text(content, encoding="utf-8")
PY
    echo "[+] Patched manager identity defaults in KernelSU/kernel/Kbuild."
}

initialize_variables() {
    if test -d "$GKI_ROOT/common/drivers"; then
         DRIVER_DIR="$GKI_ROOT/common/drivers"
    elif test -d "$GKI_ROOT/drivers"; then
         DRIVER_DIR="$GKI_ROOT/drivers"
    else
         echo '[ERROR] "drivers/" directory not found.'
         exit 127
    fi

    DRIVER_MAKEFILE=$DRIVER_DIR/Makefile
    DRIVER_KCONFIG=$DRIVER_DIR/Kconfig
}

# Reverts modifications made by this script
perform_cleanup() {
    echo "[+] Cleaning up..."
    [ -L "$DRIVER_DIR/kernelsu" ] && rm "$DRIVER_DIR/kernelsu" && echo "[-] Symlink removed."
    grep -q "kernelsu" "$DRIVER_MAKEFILE" && sed -i '/kernelsu/d' "$DRIVER_MAKEFILE" && echo "[-] Makefile reverted."
    grep -q "drivers/kernelsu/Kconfig" "$DRIVER_KCONFIG" && sed -i '/drivers\/kernelsu\/Kconfig/d' "$DRIVER_KCONFIG" && echo "[-] Kconfig reverted."
    if [ -d "$GKI_ROOT/KernelSU" ]; then
        rm -rf "$GKI_ROOT/KernelSU" && echo "[-] KernelSU directory deleted."
    fi
}

# Sets up or update KernelSU environment
setup_kernelsu() {
    echo "[+] Setting up KernelSU..."
    test -d "$GKI_ROOT/KernelSU" || git clone https://github.com/SukiSU-Ultra/SukiSU-Ultra KernelSU && echo "[+] Repository cloned."
    cd "$GKI_ROOT/KernelSU"
    git stash && echo "[-] Stashed current changes."
    if [ "$(git status | grep -Po 'v\d+(\.\d+)*' | head -n1)" ]; then
        git checkout main && echo "[-] Switched to main branch."
    fi
    git pull && echo "[+] Repository updated."
    if [ -z "${1-}" ]; then
        git checkout "$(git describe --abbrev=0 --tags)" && echo "[-] Checked out latest tag."
    else
        git checkout "$1" && echo "[-] Checked out $1." || echo "[-] Checkout default branch"
    fi
    ensure_manager_identity_defaults
    cd "$DRIVER_DIR"
    ln -sf "$(realpath --relative-to="$DRIVER_DIR" "$GKI_ROOT/KernelSU/kernel")" "kernelsu" && echo "[+] Symlink created."

    # Add entries in Makefile and Kconfig if not already existing
    grep -q "kernelsu" "$DRIVER_MAKEFILE" || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$DRIVER_MAKEFILE" && echo "[+] Modified Makefile."
    grep -q "source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" || sed -i "/endmenu/i\source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" && echo "[+] Modified Kconfig."
    echo '[+] Done.'
}

# Process command-line arguments
if [ "$#" -eq 0 ]; then
    initialize_variables
    setup_kernelsu
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    display_usage
elif [ "$1" = "--cleanup" ]; then
    initialize_variables
    perform_cleanup
else
    initialize_variables
    setup_kernelsu "$@"
fi
