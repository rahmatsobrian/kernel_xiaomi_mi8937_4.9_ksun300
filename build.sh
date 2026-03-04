#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║        ReLIFE Kernel Build Script — Telegram Ultra Detail       ║
# ║  Semua info penting dikirim ke Telegram secara real-time        ║
# ║  Termasuk: KernelSU info, hardware host, compiler detail, dll   ║
# ╚══════════════════════════════════════════════════════════════════╝

# ─── ERROR SAFETY ────────────────────────────────────────────────────
set -Eeuo pipefail

# ─── COLOR ───────────────────────────────────────────────────────────
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
cyan='\033[0;36m'
white='\033[0m'

# ─── PATH ────────────────────────────────────────────────────────────
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"
LOG_DIR="$ROOTDIR/build_logs"
TIMESTAMP=$(TZ=Asia/Jakarta date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/build_${TIMESTAMP}.log"
ERR_LOG="$LOG_DIR/errors_${TIMESTAMP}.log"
WARN_LOG="$LOG_DIR/warnings_${TIMESTAMP}.log"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"
KIMG_RAW="$OUTDIR/Image"

# ─── TOOLCHAIN ───────────────────────────────────────────────────────
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

# ─── DEFCONFIG ───────────────────────────────────────────────────────
DEFCONFIG="rahmatmsm8937hos_defconfig"
# DEFCONFIG="rahmatmsm8937_defconfig"

# ─── KERNEL INFO ─────────────────────────────────────────────────────
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"
DEVICE_FULL="Xiaomi Snapdragon 430/435"

# Git info
BRANCH=$(git rev-parse --abbrev-ref HEAD                   2>/dev/null || echo "unknown")
COMMIT_HASH=$(git rev-parse --short HEAD                   2>/dev/null || echo "unknown")
COMMIT_HASH_LONG=$(git rev-parse HEAD                      2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log --format="%s" -1                      2>/dev/null || echo "unknown")
COMMIT_AUTHOR=$(git log --format="%an" -1                  2>/dev/null || echo "unknown")
COMMIT_EMAIL=$(git log --format="%ae" -1                   2>/dev/null || echo "unknown")
COMMIT_DATE=$(git log --format="%cd" \
    --date=format:"%d %b %Y %H:%M" -1                     2>/dev/null || echo "unknown")
TOTAL_COMMITS=$(git rev-list --count HEAD                  2>/dev/null || echo "?")
DIRTY_COUNT=$(git status --short 2>/dev/null | wc -l | xargs || echo "0")
DIRTY_FILES=$(git status --short 2>/dev/null | head -5 | \
    sed 's/^/  /' | tr '\n' '|' | sed 's/|$//' || echo "")

# ─── DATE / TIME (WIB) ───────────────────────────────────────────────
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")

# ─── TELEGRAM ────────────────────────────────────────────────────────
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

# ─── GLOBAL STATE ────────────────────────────────────────────────────
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
KERNEL_LOCALVERSION="unknown"
TC_INFO="unknown"
TC_VER_FULL="unknown"
LD_INFO="unknown"
LD_VER="unknown"
IMG_USED="unknown"
IMG_SIZE="unknown"
MD5_HASH="unknown"
SHA1_HASH="unknown"
ZIP_SIZE="unknown"
ZIP_BYTES="unknown"
ZIP_NAME=""
TG_MSG_ID=""
ERROR_STAGE=""
WARNINGS=0
ERRORS_COUNT=0
JOBS=$(nproc --all)

# Host info
RAM_TOTAL=$(awk '/MemTotal/{printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?")
RAM_FREE=$(awk '/MemAvailable/{printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?")
HOST_CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
HOST_CORES=$(nproc --all 2>/dev/null || echo "?")
HOST_OS=$(uname -sr 2>/dev/null || echo "unknown")
HOST_NAME=$(uname -n 2>/dev/null || echo "unknown")
DISK_FREE=$(df -h "$ROOTDIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "?")
DISK_TOTAL=$(df -h "$ROOTDIR" 2>/dev/null | awk 'NR==2{print $2}' || echo "?")

# KernelSU info (akan diisi oleh get_kernelsu_info)
KSU_ENABLED="false"
KSU_VERSION="unknown"
KSU_VARIANT="unknown"
KSU_MANAGER_VERSION="unknown"
KSU_GIT_VERSION="unknown"

# ════════════════════════════════════════════════════════════════════
#  LOGGING
# ════════════════════════════════════════════════════════════════════
mkdir -p "$LOG_DIR"

# stdout+stderr → terminal AND log file (ANSI stripped di log)
exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) \
     2> >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE") >&2)

_ts() { date +"%H:%M:%S"; }
log()      { echo -e "${cyan}[$(_ts)]${white} $*"; }
log_ok()   { echo -e "${green}[$(_ts)] ✓${white} $*"; }
log_warn() { echo -e "${yellow}[$(_ts)] !${white} $*"; }
log_err()  { echo -e "${red}[$(_ts)] ✗${white} $*"; }
log_tg()   { echo -e "${cyan}[$(_ts)] →TG${white} $*"; }
log_sec()  { echo -e "\n${yellow}══ $* ══${white}\n"; }

# ════════════════════════════════════════════════════════════════════
#  TELEGRAM CORE
# ════════════════════════════════════════════════════════════════════

# Kirim pesan baru → return message_id
tg_send() {
    local text="$1"
    local resp
    resp=$(curl -s --max-time 30 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${text}" 2>/dev/null || echo '{"ok":false}')
    echo "$resp" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['result']['message_id'] if d.get('ok') else '')" \
        2>/dev/null || echo ""
}

# Edit pesan (gunakan TG_MSG_ID)
tg_edit() {
    [[ -z "${TG_MSG_ID:-}" ]] && return 0
    local text="$1"
    curl -s --max-time 30 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/editMessageText" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "message_id=${TG_MSG_ID}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${text}" > /dev/null 2>/dev/null || true
}

# Upload file/dokumen
tg_upload() {
    local file="$1"
    local caption="${2:-}"
    if [[ ! -f "$file" ]]; then
        log_warn "Upload skip: file tidak ada → $file"
        return 1
    fi
    local fsize; fsize=$(du -sh "$file" | awk '{print $1}')
    log_tg "Upload: $(basename "$file") ($fsize)"
    curl -s --max-time 180 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${TG_CHAT_ID}" \
        -F "document=@${file};filename=$(basename "$file")" \
        -F "parse_mode=Markdown" \
        ${caption:+--form-string "caption=${caption}"} > /dev/null 2>/dev/null \
        && log_ok "Upload OK: $(basename "$file")" \
        || log_warn "Upload GAGAL: $(basename "$file")"
}

# ════════════════════════════════════════════════════════════════════
#  INFO COLLECTORS
# ════════════════════════════════════════════════════════════════════

get_toolchain_info() {
    log_sec "Toolchain Info"

    # GCC 64-bit
    if command -v "${TC64}gcc" >/dev/null 2>&1; then
        TC_VER_FULL=$("${TC64}gcc" --version | head -1)
        local ver; ver=$("${TC64}gcc" -dumpversion)
        TC_INFO="GCC ${ver}"
        log_ok "GCC 64: $TC_VER_FULL"
    elif command -v gcc >/dev/null 2>&1; then
        TC_VER_FULL=$(gcc --version | head -1)
        local ver; ver=$(gcc -dumpversion)
        TC_INFO="GCC ${ver} (host)"
        log_warn "Pakai GCC host fallback: $TC_VER_FULL"
    else
        TC_INFO="unknown"
        log_warn "GCC tidak ditemukan!"
    fi

    # Linker
    if command -v "${TC64}ld" >/dev/null 2>&1; then
        LD_VER=$("${TC64}ld" --version 2>/dev/null | head -1 || echo "unknown")
        LD_INFO="$LD_VER"
        log_ok "LD: $LD_INFO"
    elif command -v ld >/dev/null 2>&1; then
        LD_VER=$(ld --version 2>/dev/null | head -1 || echo "unknown")
        LD_INFO="$LD_VER (host)"
        log_warn "Pakai LD host: $LD_INFO"
    fi
}

get_kernel_version() {
    if [[ -f "Makefile" ]]; then
        local v p s e
        v=$(awk '/^VERSION\s*=/{print $3; exit}'     Makefile 2>/dev/null || echo "0")
        p=$(awk '/^PATCHLEVEL\s*=/{print $3; exit}'  Makefile 2>/dev/null || echo "0")
        s=$(awk '/^SUBLEVEL\s*=/{print $3; exit}'    Makefile 2>/dev/null || echo "0")
        e=$(awk '/^EXTRAVERSION\s*=/{print $3; exit}' Makefile 2>/dev/null || echo "")
        KERNEL_VERSION="${v}.${p}.${s}${e}"
        KERNEL_LOCALVERSION=$(grep -r 'CONFIG_LOCALVERSION=' \
            "out/.config" 2>/dev/null | cut -d'"' -f2 || echo "")
        log_ok "Kernel version: $KERNEL_VERSION${KERNEL_LOCALVERSION}"
    else
        KERNEL_VERSION="unknown"
        log_warn "Makefile tidak ditemukan"
    fi
}

get_kernelsu_info() {
    log_sec "KernelSU Detection"

    # Cek berbagai cara KernelSU bisa ada di kernel
    local ksu_dir=""
    local ksu_found=false

    # 1. Cek direktori KernelSU di root source
    for d in "KernelSU" "kernelsu" "drivers/kernelsu" "fs/kernelsu"; do
        if [[ -d "$ROOTDIR/$d" ]]; then
            ksu_dir="$ROOTDIR/$d"
            ksu_found=true
            log_ok "KernelSU dir: $d"
            break
        fi
    done

    # 2. Cek via Kconfig / Makefile
    if ! $ksu_found; then
        if grep -qr "KERNELSU\|KernelSU\|kernelsu" \
            "$ROOTDIR/drivers" "$ROOTDIR/fs" \
            --include="Kconfig" --include="Makefile" 2>/dev/null; then
            ksu_found=true
            log_ok "KernelSU ditemukan via Kconfig/Makefile"
        fi
    fi

    # 3. Cek header
    if ! $ksu_found; then
        if find "$ROOTDIR" -name "kernelsu.h" -o -name "ksu.h" 2>/dev/null | grep -q .; then
            ksu_found=true
            log_ok "KernelSU header ditemukan"
        fi
    fi

    if ! $ksu_found; then
        KSU_ENABLED="false"
        KSU_VARIANT="Tidak ada"
        KSU_VERSION="N/A"
        log_warn "KernelSU tidak ditemukan di source"
        return
    fi

    KSU_ENABLED="true"

    # Deteksi variant
    # KernelSU-Next
    if [[ -f "$ROOTDIR/KernelSU/kernel/Makefile" ]] || \
       grep -qr "KernelSU-Next\|rifsxd" "$ROOTDIR" \
           --include="*.md" --include="*.txt" 2>/dev/null | head -1 | grep -q .; then
        KSU_VARIANT="KernelSU-Next (rifsxd)"
    # KernelSU official
    elif [[ -f "$ROOTDIR/KernelSU/README.md" ]] || \
         grep -qr "tiann/KernelSU" "$ROOTDIR" \
             --include="*.md" 2>/dev/null; then
        KSU_VARIANT="KernelSU Official (tiann)"
    else
        KSU_VARIANT="KernelSU (unknown variant)"
    fi

    # Ambil versi dari berbagai sumber
    # 1. Dari define VERSION di source
    local ksu_ver_h=""
    ksu_ver_h=$(find "$ROOTDIR" \
        -name "ksu.h" -o -name "kernelsu.h" 2>/dev/null | head -1)

    if [[ -n "$ksu_ver_h" ]]; then
        local ver_def
        ver_def=$(grep -E "KERNELSU_VERSION|KSU_VERSION|VERSION" \
            "$ksu_ver_h" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "")
        [[ -n "$ver_def" ]] && KSU_VERSION="$ver_def"
    fi

    # 2. Dari Makefile KernelSU
    if [[ "$KSU_VERSION" == "unknown" ]] && [[ -n "$ksu_dir" ]]; then
        local ver_mk
        ver_mk=$(grep -E "^VERSION\s*[:?]?=\s*[0-9]+" \
            "$ksu_dir/kernel/Makefile" 2>/dev/null | awk '{print $NF}' | head -1 || echo "")
        [[ -n "$ver_mk" ]] && KSU_VERSION="$ver_mk"
    fi

    # 3. Dari git tag di submodule KernelSU
    if [[ "$KSU_VERSION" == "unknown" ]] && [[ -n "$ksu_dir" ]]; then
        KSU_GIT_VERSION=$(git -C "$ksu_dir" describe --tags --abbrev=0 2>/dev/null || echo "unknown")
        [[ "$KSU_GIT_VERSION" != "unknown" ]] && KSU_VERSION="$KSU_GIT_VERSION"
    fi

    # 4. Manager version dari source
    local manager_ver
    manager_ver=$(grep -r "MANAGER_MIN_VERSION\|MIN_MANAGER_VERSION" \
        "$ROOTDIR" --include="*.h" --include="*.c" 2>/dev/null | \
        grep -oE '[0-9]+' | head -1 || echo "unknown")
    KSU_MANAGER_VERSION="$manager_ver"

    # 5. Cek apakah enabled di defconfig / .config
    local ksu_config="disabled in config"
    if [[ -f "$ROOTDIR/out/.config" ]]; then
        if grep -q "CONFIG_KSU=y\|CONFIG_KERNELSU=y" "$ROOTDIR/out/.config" 2>/dev/null; then
            ksu_config="✅ enabled (CONFIG_KSU=y)"
        elif grep -q "CONFIG_KSU\|CONFIG_KERNELSU" "$ROOTDIR/out/.config" 2>/dev/null; then
            ksu_config="⚠️ ada tapi tidak aktif"
        fi
    elif [[ -f "$ROOTDIR/arch/arm64/configs/$DEFCONFIG" ]]; then
        if grep -q "CONFIG_KSU=y\|CONFIG_KERNELSU=y" \
               "$ROOTDIR/arch/arm64/configs/$DEFCONFIG" 2>/dev/null; then
            ksu_config="✅ enabled di defconfig"
        fi
    fi
    KSU_VARIANT="$KSU_VARIANT | $ksu_config"

    log_ok "KernelSU enabled: $KSU_VARIANT"
    log_ok "KernelSU version: $KSU_VERSION"
}

# ════════════════════════════════════════════════════════════════════
#  TELEGRAM NOTIFIKASI
# ════════════════════════════════════════════════════════════════════

notify_start() {
    log_tg "Kirim notif START..."

    local dirty_info="✅ Bersih (no changes)"
    if [[ "$DIRTY_COUNT" -gt 0 ]]; then
        dirty_info="⚠️ ${DIRTY_COUNT} file belum di-commit"
        [[ -n "$DIRTY_FILES" ]] && dirty_info+="
  $(echo "$DIRTY_FILES" | tr '|' '\n' | head -3 | sed 's/^/    • /' | tr '\n' '§' | sed 's/§/\n/g')"
    fi

    local ksu_line=""
    if [[ "$KSU_ENABLED" == "true" ]]; then
        ksu_line="
🔑 *KernelSU*       : ✅ Aktif
   └ *Variant*      : ${KSU_VARIANT}
   └ *Versi*        : ${KSU_VERSION}
   └ *Min Manager*  : ${KSU_MANAGER_VERSION}"
    else
        ksu_line="
🔑 *KernelSU*       : ❌ Tidak ada"
    fi

    TG_MSG_ID=$(tg_send "🚀 *ReLIFE Kernel — Build Dimulai*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*          : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*          : ${KERNEL_NAME}
🍃 *Versi Kernel*    : \`${KERNEL_VERSION}\`
🏷 *Localversion*    : \`${KERNEL_LOCALVERSION:-tidak ada}\`
${ksu_line}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 *Source Info*
🌿 *Branch*          : \`${BRANCH}\`
🔖 *Commit*          : \`${COMMIT_HASH}\`
💬 *Pesan Commit*    : ${COMMIT_MSG}
👤 *Author*          : ${COMMIT_AUTHOR}
📧 *Email*           : ${COMMIT_EMAIL}
📅 *Tanggal Commit*  : ${COMMIT_DATE}
📊 *Total Commit*    : ${TOTAL_COMMITS}
🗂 *Status Tree*     : ${dirty_info}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛠 *Build Config*
🔧 *Defconfig*       : \`${DEFCONFIG}\`
⚙️ *Compiler*        : ${TC_VER_FULL}
🔗 *Linker*          : ${LD_INFO}
🖥 *Jobs*            : ${JOBS} thread

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💻 *Host Machine*
🖥 *Hostname*        : ${HOST_NAME}
⚙️ *CPU*             : ${HOST_CPU}
🧠 *Cores*           : ${HOST_CORES}
💾 *RAM*             : ${RAM_FREE} GB free / ${RAM_TOTAL} GB total
💿 *Disk*            : ${DISK_FREE} free / ${DISK_TOTAL} total
🐧 *OS*              : ${HOST_OS}

🕒 *Mulai*           : ${BUILD_DATETIME}")

    log_ok "Notif START terkirim (ID: ${TG_MSG_ID:-gagal})"
}

notify_compiling() {
    tg_edit "🔨 *ReLIFE Kernel — Sedang Dikompilasi...*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*      : \`${DEVICE}\` — ${DEVICE_FULL}
🍃 *Versi*       : \`${KERNEL_VERSION}\`
🌿 *Branch*      : \`${BRANCH}\`
🔖 *Commit*      : \`${COMMIT_HASH}\`
💬 *Commit Msg*  : ${COMMIT_MSG}

🛠 *Compiler*    : ${TC_VER_FULL}
🔗 *Linker*      : ${LD_INFO}
🔧 *Defconfig*   : \`${DEFCONFIG}\`
⚙️ *Jobs*        : ${JOBS} thread

💻 *CPU Host*    : ${HOST_CPU} (${HOST_CORES} cores)
💾 *RAM*         : ${RAM_FREE} GB bebas

⏳ *Status*      : Kompilasi berjalan...
🕒 *Mulai*       : ${BUILD_DATETIME}"
}

notify_packing() {
    tg_edit "📦 *ReLIFE Kernel — Packing Zip...*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*         : \`${DEVICE}\`
🍃 *Versi*          : \`${KERNEL_VERSION}\`
⏱ *Waktu Compile*  : ${BUILD_TIME}
🖼 *Image*          : \`${IMG_USED}\` (${IMG_SIZE})
⚠️ *Warnings*       : ${WARNINGS}
🔢 *Errors*         : ${ERRORS_COUNT}

⏳ *Status*         : Membuat flashable zip..."
}

notify_uploading() {
    tg_edit "📤 *ReLIFE Kernel — Mengupload ke Telegram...*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*         : \`${DEVICE}\`
📁 *File*           : \`${ZIP_NAME}\`
📏 *Ukuran*         : ${ZIP_SIZE}
⏱ *Waktu Compile*  : ${BUILD_TIME}

⏳ *Status*         : Mengupload..."
}

notify_success() {
    local zip_path="$ANYKERNEL_DIR/$ZIP_NAME"

    local ksu_caption=""
    if [[ "$KSU_ENABLED" == "true" ]]; then
        ksu_caption="
🔑 *KernelSU*       : ✅ Aktif
   └ Variant        : ${KSU_VARIANT}
   └ Versi          : ${KSU_VERSION}"
    else
        ksu_caption="
🔑 *KernelSU*       : ❌ Tidak ada"
    fi

    local warn_note=""
    [[ "$WARNINGS" -gt 0 ]] && warn_note="
⚠️ *Warnings*       : ${WARNINGS} (lihat warning log)"

    local caption="✅ *ReLIFE Kernel — Build Berhasil!*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*         : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*         : ${KERNEL_NAME}
🍃 *Versi Kernel*   : \`${KERNEL_VERSION}\`
🏷 *Localversion*   : \`${KERNEL_LOCALVERSION:-tidak ada}\`
${ksu_caption}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 *Source*
🌿 *Branch*         : \`${BRANCH}\`
🔖 *Commit*         : \`${COMMIT_HASH}\`
💬 *Commit Msg*     : ${COMMIT_MSG}
👤 *Author*         : ${COMMIT_AUTHOR}
📅 *Tgl Commit*     : ${COMMIT_DATE}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛠 *Build*
⚙️ *Compiler*       : ${TC_VER_FULL}
🔗 *Linker*         : ${LD_INFO}
🔧 *Defconfig*      : \`${DEFCONFIG}\`
🖼 *Image*          : \`${IMG_USED}\` (${IMG_SIZE})
⚙️ *Jobs*           : ${JOBS} thread
⏱ *Waktu Compile* : ${BUILD_TIME}
🕒 *Tanggal Build*  : ${BUILD_DATETIME}
${warn_note}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 *File*           : \`${ZIP_NAME}\`
📏 *Ukuran*         : ${ZIP_SIZE}
🔐 *MD5*            :
\`${MD5_HASH}\`
🔑 *SHA1*           :
\`${SHA1_HASH}\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ *Flash via TWRP / Custom Recovery*"

    # 1. Upload kernel zip dengan caption lengkap
    tg_upload "$zip_path" "$caption"

    # 2. Upload full build log
    tg_upload "$LOG_FILE" \
"📋 *Full Build Log*
${KERNEL_NAME} \`${KERNEL_VERSION}\` | Branch: \`${BRANCH}\`
Commit: \`${COMMIT_HASH}\` | Jobs: ${JOBS}
Warnings: ${WARNINGS} | Waktu: ${BUILD_TIME}"

    # 3. Upload warning log jika ada
    if [[ "$WARNINGS" -gt 0 ]] && [[ -f "$WARN_LOG" ]] && [[ -s "$WARN_LOG" ]]; then
        tg_upload "$WARN_LOG" \
"⚠️ *Warning Summary* — ${WARNINGS} warnings
${KERNEL_NAME} \`${KERNEL_VERSION}\` | \`${COMMIT_HASH}\`"
    fi

    # 4. Edit pesan awal jadi ringkasan final
    tg_edit "✅ *Build Selesai — ${KERNEL_NAME} \`${KERNEL_VERSION}\`*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 \`${ZIP_NAME}\`
📏 Ukuran        : ${ZIP_SIZE}
⏱ Waktu Compile : ${BUILD_TIME}
⚠️ Warnings      : ${WARNINGS}
🔑 KernelSU      : $([ "$KSU_ENABLED" == "true" ] && echo "✅ v${KSU_VERSION}" || echo "❌")
🔐 MD5           : \`${MD5_HASH}\`
🕒 Selesai       : $(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")"
}

notify_error() {
    local stage="${ERROR_STAGE:-unknown}"
    local line="${1:-?}"

    # Ambil 15 baris error terakhir
    local last_err="Tidak ada error yang tertangkap"
    if [[ -f "$LOG_FILE" ]]; then
        local raw
        raw=$(grep -aE "(error:|Error|FAILED|undefined reference|multiple definition|fatal:)" \
            "$LOG_FILE" 2>/dev/null | grep -v "^Binary" | tail -15 | \
            sed 's/\x1b\[[0-9;]*m//g' | sed "s/\`/'/g" | \
            awk '{print NR". "$0}' || true)
        [[ -n "$raw" ]] && last_err="$raw"
        if [[ ${#last_err} -gt 900 ]]; then
            last_err="${last_err:0:900}
..._(terpotong, lihat log lengkap)_"
        fi
    fi

    # Edit pesan awal → status GAGAL
    tg_edit "❌ *Build GAGAL — \`${stage}\`*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 Device    : \`${DEVICE}\`
🌿 Branch    : \`${BRANCH}\`
🔖 Commit    : \`${COMMIT_HASH}\`
💥 Gagal di  : \`${stage}\`
📍 Baris     : ${line}
⚠️ Warnings  : ${WARNINGS}
🔢 Errors    : ${ERRORS_COUNT}
🕒 Waktu     : $(TZ=Asia/Jakarta date +"%H:%M WIB")
📋 Log lengkap terlampir di bawah..."

    # Pesan error detail (pesan baru)
    tg_send "❌ *ReLIFE Kernel — Build GAGAL*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*       : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*       : ${KERNEL_NAME}
🍃 *Versi*        : \`${KERNEL_VERSION}\`
🌿 *Branch*       : \`${BRANCH}\`
🔖 *Commit*       : \`${COMMIT_HASH}\`
💬 *Commit Msg*   : ${COMMIT_MSG}
👤 *Author*       : ${COMMIT_AUTHOR}

🛠 *Compiler*     : ${TC_VER_FULL}
🔗 *Linker*       : ${LD_INFO}
🔧 *Defconfig*    : \`${DEFCONFIG}\`

💥 *Gagal di*     : \`${stage}\`
📍 *Baris Script* : ${line}
⚠️ *Warnings*     : ${WARNINGS}
🔢 *Errors*       : ${ERRORS_COUNT}
🕒 *Waktu*        : ${BUILD_DATETIME}

🔴 *Baris Error Terakhir:*
\`\`\`
${last_err}
\`\`\`" > /dev/null

    # Upload full log
    if [[ -f "$LOG_FILE" ]]; then
        tg_upload "$LOG_FILE" \
"❌ *Full Build Log — GAGAL*
Stage: \`${stage}\` | Baris: ${line}
${KERNEL_NAME} \`${KERNEL_VERSION}\` | \`${BRANCH}\` | \`${COMMIT_HASH}\`
Warnings: ${WARNINGS} | Errors: ${ERRORS_COUNT}"
    fi

    # Buat & upload filtered error log
    grep -aE "(error:|Error|FAILED|undefined reference|multiple definition|fatal:)" \
        "$LOG_FILE" 2>/dev/null | grep -v "^Binary" | \
        sed 's/\x1b\[[0-9;]*m//g' > "$ERR_LOG" || true
    if [[ -s "$ERR_LOG" ]]; then
        tg_upload "$ERR_LOG" \
"🔴 *Filtered Error Log* — $(wc -l < "$ERR_LOG") baris error
Stage: \`${stage}\` | ${KERNEL_NAME} | \`${COMMIT_HASH}\`"
    fi
}

# ════════════════════════════════════════════════════════════════════
#  ERROR TRAP
# ════════════════════════════════════════════════════════════════════

on_error() {
    local exit_code=$?
    local line="$1"
    log_err "Script gagal di baris ${line} (exit ${exit_code})"
    log_err "Stage: ${ERROR_STAGE:-unknown}"
    notify_error "$line"
    exit "$exit_code"
}

trap 'on_error $LINENO' ERR

# ════════════════════════════════════════════════════════════════════
#  CLONE ANYKERNEL
# ════════════════════════════════════════════════════════════════════

clone_anykernel() {
    log_sec "AnyKernel3"
    if [[ ! -d "$ANYKERNEL_DIR" ]]; then
        log "Cloning AnyKernel3..."
        git clone --depth=1 -b mi8937 \
            https://github.com/rahmatsobrian/AnyKernel3.git \
            "$ANYKERNEL_DIR"
        log_ok "AnyKernel3 cloned"
    else
        log "Updating AnyKernel3..."
        git -C "$ANYKERNEL_DIR" pull --rebase --autostash 2>/dev/null \
            && log_ok "AnyKernel3 updated" \
            || log_warn "Pull gagal, pakai lokal"
    fi
    log_ok "AnyKernel3 commit: $(git -C "$ANYKERNEL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
}

# ════════════════════════════════════════════════════════════════════
#  BUILD
# ════════════════════════════════════════════════════════════════════

build_kernel() {
    log_sec "BUILD KERNEL"

    [[ ! -f "Makefile" ]] && {
        ERROR_STAGE="Sanity Check"
        log_err "Bukan di root kernel source! (tidak ada Makefile)"
        exit 1
    }

    # Clean
    ERROR_STAGE="Clean"
    log "Membersihkan out/..."
    rm -rf out
    log_ok "out/ bersih"

    # Defconfig
    ERROR_STAGE="Defconfig"
    log "Applying defconfig: $DEFCONFIG"
    make O=out ARCH=arm64 "$DEFCONFIG" 2>&1 | tee -a "$LOG_FILE"
    log_ok "Defconfig OK"

    # Kumpulkan semua info
    get_toolchain_info
    get_kernel_version
    get_kernelsu_info

    # Kirim notif START
    notify_start

    # Mulai compile
    ERROR_STAGE="Compile"
    log "Mulai kompilasi ($JOBS jobs)..."
    notify_compiling

    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    make -j"$JOBS" O=out ARCH=arm64 \
        CROSS_COMPILE="$TC64" \
        CROSS_COMPILE_ARM32="$TC32" \
        CROSS_COMPILE_COMPAT="$TC32" \
        2>&1 | tee -a "$LOG_FILE"

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    local diff=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((diff / 60)) min $((diff % 60)) sec"

    # Hitung stats
    WARNINGS=$(grep -c " warning:" "$LOG_FILE" 2>/dev/null || echo 0)
    ERRORS_COUNT=$(grep -c " error:" "$LOG_FILE" 2>/dev/null || echo 0)

    # Simpan warning log (unique + sorted by frequency)
    if [[ "$WARNINGS" -gt 0 ]]; then
        grep " warning:" "$LOG_FILE" 2>/dev/null | \
            sed 's/\x1b\[[0-9;]*m//g' | sort | uniq -c | sort -rn \
            > "$WARN_LOG" || true
    fi

    get_kernel_version  # re-read post-build
    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"

    log_ok "Kompilasi selesai: ${BUILD_TIME}"
    log_ok "Warnings: ${WARNINGS} | Errors: ${ERRORS_COUNT}"
    log_ok "ZIP: ${ZIP_NAME}"
}

# ════════════════════════════════════════════════════════════════════
#  PACK
# ════════════════════════════════════════════════════════════════════

pack_kernel() {
    log_sec "PACK KERNEL"

    clone_anykernel
    cd "$ANYKERNEL_DIR" || exit 1

    log "Membersihkan file lama..."
    rm -f Image* *.zip

    # Deteksi image
    ERROR_STAGE="Detect Image"
    if [[ -f "$KIMG_DTB" ]]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
        IMG_SIZE=$(du -sh "$KIMG_DTB" | awk '{print $1}')
    elif [[ -f "$KIMG" ]]; then
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
        IMG_SIZE=$(du -sh "$KIMG" | awk '{print $1}')
    elif [[ -f "$KIMG_RAW" ]]; then
        cp "$KIMG_RAW" Image
        IMG_USED="Image"
        IMG_SIZE=$(du -sh "$KIMG_RAW" | awk '{print $1}')
    else
        log_err "Tidak ada kernel image ditemukan di $OUTDIR"
        log_err "Expected: Image.gz-dtb | Image.gz | Image"
        ERROR_STAGE="No Kernel Image"
        exit 1
    fi
    log_ok "Image: $IMG_USED ($IMG_SIZE)"

    notify_packing

    # Buat zip
    ERROR_STAGE="Create Zip"
    log "Membuat zip: $ZIP_NAME"
    zip -r9 "$ZIP_NAME" . -x ".git*" "README.md" "*.log" "*.sh" > /dev/null

    MD5_HASH=$(md5sum  "$ZIP_NAME" | awk '{print $1}')
    SHA1_HASH=$(sha1sum "$ZIP_NAME" | awk '{print $1}')
    ZIP_SIZE=$(du -sh  "$ZIP_NAME" | awk '{print $1}')

    log_ok "Zip: $ZIP_NAME"
    log_ok "Size: $ZIP_SIZE | MD5: $MD5_HASH"
    log_ok "SHA1: $SHA1_HASH"

    cd "$ROOTDIR" || exit 1
}

# ════════════════════════════════════════════════════════════════════
#  UPLOAD
# ════════════════════════════════════════════════════════════════════

upload_kernel() {
    log_sec "UPLOAD KE TELEGRAM"
    ERROR_STAGE="Upload Telegram"

    [[ ! -f "$ANYKERNEL_DIR/$ZIP_NAME" ]] && {
        log_warn "Zip tidak ditemukan, skip upload"
        return 1
    }

    notify_uploading
    notify_success
    log_ok "Semua upload selesai!"
}

# ════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════

# Setup log dir + dual output
mkdir -p "$LOG_DIR"
exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) \
     2> >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE") >&2)

GLOBAL_START=$(TZ=Asia/Jakarta date +%s)

echo -e "${yellow}"
echo "╔══════════════════════════════════════════════╗"
echo "║      ReLIFE Kernel Build — Telegram Mode     ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${white}"
log "Log: $LOG_FILE"
log "Host: $HOST_NAME | $HOST_OS"
log "CPU: $HOST_CPU ($HOST_CORES cores)"
log "RAM: ${RAM_FREE}GB free / ${RAM_TOTAL}GB"
log "Disk: ${DISK_FREE} free / ${DISK_TOTAL}"

build_kernel
pack_kernel
upload_kernel

GLOBAL_END=$(TZ=Asia/Jakarta date +%s)
log_ok "Total waktu: $((GLOBAL_END - GLOBAL_START)) detik"
