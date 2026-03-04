#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║        ReLIFE Kernel Build Script — Telegram Ultra Detail       ║
# ╚══════════════════════════════════════════════════════════════════╝

set -Eeuo pipefail

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
cyan='\033[0;36m'
white='\033[0m'

# ================= PATH =================
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"
LOG_DIR="$ROOTDIR/build_logs"
TIMESTAMP=$(TZ=Asia/Jakarta date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/build_${TIMESTAMP}.log"
ERR_LOG="$LOG_DIR/errors_${TIMESTAMP}.log"
WARN_LOG="$LOG_DIR/warnings_${TIMESTAMP}.log"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG_GZ="$OUTDIR/Image.gz"
KIMG_RAW="$OUTDIR/Image"

# ================= TOOLCHAIN =================
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"
CLANG_BIN=""   # isi path clang jika pakai, misal: "/opt/clang/bin/clang"

# ================= DEFCONFIG =================
DEFCONFIG="rahmatmsm8937hos_defconfig"
# DEFCONFIG="rahmatmsm8937_defconfig"

# ================= INFO =================
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"
DEVICE_FULL="Xiaomi Snapdragon 430/435"

BRANCH=$(git rev-parse --abbrev-ref HEAD                2>/dev/null || echo "unknown")
COMMIT_HASH=$(git rev-parse --short HEAD                2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log --format="%s" -1                   2>/dev/null || echo "unknown")
COMMIT_AUTHOR=$(git log --format="%an" -1               2>/dev/null || echo "unknown")
COMMIT_EMAIL=$(git log --format="%ae" -1                2>/dev/null || echo "unknown")
COMMIT_DATE=$(git log --format="%cd" \
    --date=format:"%d %b %Y, %H:%M" -1                 2>/dev/null || echo "unknown")
TOTAL_COMMITS=$(git rev-list --count HEAD               2>/dev/null || echo "?")
DIRTY_COUNT=$(git status --short 2>/dev/null | wc -l | xargs || echo "0")
DIRTY_LIST=$(git status --short 2>/dev/null | head -5 | awk '{print "  "$0}' | \
    tr '\n' '\n' || echo "")

# ================= DATE (WIB) =================
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")

# ================= TELEGRAM =================
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
KERNEL_LOCALVERSION=""
JOBS=$(nproc --all)

GCC_VER="unknown"
GCC_VER_FULL="unknown"
GCC32_VER="unknown"
GCC32_VER_FULL="unknown"
CLANG_VER="unknown"
CLANG_VER_FULL="tidak digunakan"
LD_VER="unknown"
LD_VER_FULL="unknown"
COMPILER_STRING="unknown"

IMG_USED="unknown"
IMG_SIZE="unknown"
MD5_HASH="unknown"
SHA1_HASH="unknown"
ZIP_SIZE="unknown"
ZIP_NAME=""

KSU_ENABLED="false"
KSU_VERSION="N/A"
KSU_GIT_TAG="N/A"
KSU_GIT_COMMIT="N/A"
KSU_LAST_COMMIT_MSG="N/A"
KSU_MANAGER_VER="N/A"
KSU_CONFIG_STATUS="N/A"
KSU_INTEGRATION="N/A"

TG_MSG_ID=""
ERROR_STAGE=""
WARNINGS=0
ERRORS_COUNT=0

# Host info
HOST_NAME=$(uname -n 2>/dev/null || echo "unknown")
HOST_OS=$(uname -sr 2>/dev/null || echo "unknown")
HOST_ARCH=$(uname -m 2>/dev/null || echo "unknown")
HOST_CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | \
    cut -d: -f2 | xargs || echo "unknown")
HOST_CORES=$(nproc --all 2>/dev/null || echo "?")
RAM_TOTAL=$(awk '/MemTotal/{printf "%.1f", $2/1024/1024}' \
    /proc/meminfo 2>/dev/null || echo "?")
RAM_FREE=$(awk '/MemAvailable/{printf "%.1f", $2/1024/1024}' \
    /proc/meminfo 2>/dev/null || echo "?")
SWAP_TOTAL=$(awk '/SwapTotal/{printf "%.1f", $2/1024/1024}' \
    /proc/meminfo 2>/dev/null || echo "0")
DISK_FREE=$(df -h "$ROOTDIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "?")
DISK_TOTAL=$(df -h "$ROOTDIR" 2>/dev/null | awk 'NR==2{print $2}' || echo "?")
DISK_PCT=$(df "$ROOTDIR" 2>/dev/null | awk 'NR==2{print $5}' || echo "?")

# ================= LOGGING =================
mkdir -p "$LOG_DIR"
exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) \
     2> >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE") >&2)

_ts() { date +"%H:%M:%S"; }
log()     { echo -e "${cyan}[$(_ts)]${white} $*"; }
log_ok()  { echo -e "${green}[$(_ts)] ✓${white} $*"; }
log_w()   { echo -e "${yellow}[$(_ts)] !${white} $*"; }
log_e()   { echo -e "${red}[$(_ts)] ✗${white} $*"; }
log_tg()  { echo -e "${cyan}[$(_ts)] →TG${white} $*"; }
log_sec() { echo -e "\n${yellow}══ $* ══${white}\n"; }

# ════════════════════════════════════════════════════════
#  TELEGRAM — metode sama persis dengan kode referensi
#  sendMessage  → pakai -d text="..."
#  sendDocument → pakai -F caption="..."
#  editMessage  → pakai -d text="..."
# ════════════════════════════════════════════════════════

# Kirim pesan teks → return message_id
tg_send() {
    local text="$1"
    local resp
    resp=$(curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode=Markdown \
        -d disable_web_page_preview=true \
        -d text="${text}")
    # Ambil message_id dari response JSON
    echo "$resp" | python3 -c \
        "import sys,json
d=json.load(sys.stdin)
print(d['result']['message_id'] if d.get('ok') else '')" 2>/dev/null || echo ""
}

# Edit pesan yang sudah ada (gunakan TG_MSG_ID)
tg_edit() {
    [[ -z "${TG_MSG_ID:-}" ]] && return 0
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/editMessageText" \
        -d chat_id="${TG_CHAT_ID}" \
        -d message_id="${TG_MSG_ID}" \
        -d parse_mode=Markdown \
        -d disable_web_page_preview=true \
        -d text="${text}" > /dev/null
}

# Upload file → pakai -F seperti kode referensi
tg_upload() {
    local file="$1"
    local caption="${2:-}"
    if [[ ! -f "$file" ]]; then
        log_w "Upload skip: $file tidak ada"
        return 1
    fi
    local fsize; fsize=$(du -sh "$file" | awk '{print $1}')
    log_tg "Upload: $(basename "$file") ($fsize)"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"${file}" \
        -F parse_mode=Markdown \
        -F caption="${caption}" > /dev/null \
        && log_ok "Upload OK: $(basename "$file")" \
        || log_w "Upload GAGAL: $(basename "$file")"
}

# ════════════════════════════════════════════════════════
#  INFO COLLECTORS
# ════════════════════════════════════════════════════════

get_compiler_info() {
    log_sec "Compiler Info"
    # GCC 64-bit
    if command -v "${TC64}gcc" >/dev/null 2>&1; then
        GCC_VER_FULL=$("${TC64}gcc" --version | head -1)
        GCC_VER=$("${TC64}gcc" -dumpversion)
        log_ok "GCC64: $GCC_VER_FULL"
    else
        GCC_VER_FULL="tidak ditemukan"
        GCC_VER="N/A"
        log_w "GCC 64-bit tidak ditemukan"
    fi
    # GCC 32-bit
    if command -v "${TC32}gcc" >/dev/null 2>&1; then
        GCC32_VER_FULL=$("${TC32}gcc" --version | head -1)
        GCC32_VER=$("${TC32}gcc" -dumpversion)
        log_ok "GCC32: $GCC32_VER_FULL"
    else
        GCC32_VER_FULL="tidak ditemukan"
        GCC32_VER="N/A"
        log_w "GCC 32-bit tidak ditemukan"
    fi
    # Clang (opsional)
    local clang_cmd=""
    [[ -n "$CLANG_BIN" && -f "$CLANG_BIN" ]] && clang_cmd="$CLANG_BIN"
    command -v clang >/dev/null 2>&1 && [[ -z "$clang_cmd" ]] && clang_cmd="clang"
    if [[ -n "$clang_cmd" ]]; then
        CLANG_VER_FULL=$("$clang_cmd" --version | head -1)
        CLANG_VER=$("$clang_cmd" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        log_ok "Clang: $CLANG_VER_FULL"
    else
        CLANG_VER_FULL="tidak digunakan"
        CLANG_VER="N/A"
    fi
    # Linker
    if command -v "${TC64}ld" >/dev/null 2>&1; then
        LD_VER_FULL=$("${TC64}ld" --version 2>/dev/null | head -1 || echo "unknown")
        LD_VER=$(echo "$LD_VER_FULL" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "?")
        log_ok "LD: $LD_VER_FULL"
    fi
    # Ringkasan
    if [[ "$CLANG_VER" != "N/A" ]]; then
        COMPILER_STRING="Clang ${CLANG_VER} + GCC ${GCC_VER}"
    else
        COMPILER_STRING="GCC ${GCC_VER}"
    fi
}

get_kernel_version() {
    if [[ -f "Makefile" ]]; then
        local v p s e
        v=$(awk '/^VERSION\s*=/{print $3; exit}'      Makefile 2>/dev/null || echo "0")
        p=$(awk '/^PATCHLEVEL\s*=/{print $3; exit}'   Makefile 2>/dev/null || echo "0")
        s=$(awk '/^SUBLEVEL\s*=/{print $3; exit}'     Makefile 2>/dev/null || echo "0")
        e=$(awk '/^EXTRAVERSION\s*=/{print $3; exit}' Makefile 2>/dev/null || echo "")
        KERNEL_VERSION="${v}.${p}.${s}${e}"
        if [[ -f "out/.config" ]]; then
            KERNEL_LOCALVERSION=$(grep '^CONFIG_LOCALVERSION=' out/.config 2>/dev/null | \
                cut -d'"' -f2 || echo "")
        fi
        log_ok "Kernel version: $KERNEL_VERSION${KERNEL_LOCALVERSION}"
    else
        KERNEL_VERSION="unknown"
        log_w "Makefile tidak ditemukan"
    fi
}

get_kernelsu_info() {
    log_sec "KernelSU Next Detection"
    local ksu_root=""
    for d in "KernelSU" "kernelsu" "drivers/kernelsu" "fs/kernelsu" "security/kernelsu"; do
        [[ -d "$ROOTDIR/$d" ]] && { ksu_root="$ROOTDIR/$d"; break; }
    done

    if [[ -z "$ksu_root" ]]; then
        if grep -qrE "KERNELSU|KernelSU|kernelsu" \
            "$ROOTDIR/drivers" "$ROOTDIR/fs" "$ROOTDIR/security" \
            --include="Kconfig" --include="Makefile" 2>/dev/null; then
            KSU_ENABLED="true"
            KSU_INTEGRATION="Inline patch"
            log_ok "KernelSU ditemukan via Kconfig/Makefile"
        fi
    fi

    if [[ -n "$ksu_root" ]]; then
        KSU_ENABLED="true"
        log_ok "KernelSU dir: $ksu_root"

        if [[ -f "$ROOTDIR/.gitmodules" ]] && \
           grep -q "KernelSU" "$ROOTDIR/.gitmodules" 2>/dev/null; then
            KSU_INTEGRATION="Git submodule"
        else
            KSU_INTEGRATION="Direktori manual"
        fi

        # Versi dari Makefile KSU
        if [[ -f "$ksu_root/kernel/Makefile" ]]; then
            local v
            v=$(grep -E '^VERSION\s*[:?]?=' "$ksu_root/kernel/Makefile" 2>/dev/null | \
                awk -F'=' '{print $NF}' | xargs | head -1 || echo "")
            [[ -n "$v" ]] && KSU_VERSION="$v"
        fi

        # Git info di direktori KSU
        if git -C "$ksu_root" rev-parse --git-dir &>/dev/null 2>/dev/null; then
            KSU_GIT_TAG=$(git -C "$ksu_root" describe --tags --abbrev=0 2>/dev/null || echo "N/A")
            KSU_GIT_COMMIT=$(git -C "$ksu_root" rev-parse --short HEAD 2>/dev/null || echo "N/A")
            KSU_LAST_COMMIT_MSG=$(git -C "$ksu_root" log --format="%s" -1 2>/dev/null || echo "N/A")
            [[ "$KSU_VERSION" == "N/A" ]] && \
                KSU_VERSION=$(echo "$KSU_GIT_TAG" | grep -oE '[0-9]+' | head -1 || echo "N/A")
        fi

        # Manager min version
        local mgr
        mgr=$(grep -r "MANAGER_MIN_VERSION\|MIN_MANAGER_VERSION" \
            "$ksu_root" --include="*.h" --include="*.c" 2>/dev/null | \
            grep -oE '[0-9]{4,}' | head -1 || echo "N/A")
        KSU_MANAGER_VER="$mgr"
    fi

    # Status di config
    local cfg=""
    [[ -f "$ROOTDIR/out/.config" ]] && cfg="$ROOTDIR/out/.config"
    [[ -z "$cfg" ]] && cfg="$ROOTDIR/arch/arm64/configs/$DEFCONFIG"
    if [[ -f "$cfg" ]]; then
        if grep -qE "^CONFIG_KSU=y|^CONFIG_KERNELSU=y" "$cfg" 2>/dev/null; then
            KSU_CONFIG_STATUS="Aktif (CONFIG_KSU=y)"
        elif grep -qE "CONFIG_KSU|CONFIG_KERNELSU" "$cfg" 2>/dev/null; then
            KSU_CONFIG_STATUS="Ada tapi tidak aktif"
        else
            KSU_CONFIG_STATUS="Tidak ada di config"
        fi
    else
        KSU_CONFIG_STATUS="Config belum tersedia"
    fi

    if [[ "$KSU_ENABLED" == "true" ]]; then
        log_ok "KernelSU Next: DITEMUKAN | Versi: $KSU_VERSION | Tag: $KSU_GIT_TAG"
    else
        log_w "KernelSU Next: tidak ditemukan"
    fi
}

# ════════════════════════════════════════════════════════
#  TELEGRAM NOTIFIKASI
# ════════════════════════════════════════════════════════

notify_start() {
    log_tg "Kirim notif START..."

    local dirty_status
    if [[ "$DIRTY_COUNT" -gt 0 ]]; then
        dirty_status="⚠️ ${DIRTY_COUNT} file belum di-commit"
    else
        dirty_status="✅ Bersih"
    fi

    local ksu_status
    if [[ "$KSU_ENABLED" == "true" ]]; then
        ksu_status="✅ Aktif — v${KSU_VERSION} (${KSU_GIT_TAG})"
    else
        ksu_status="❌ Tidak ada"
    fi

    # Bangun teks pesan — pakai metode -d text= seperti kode referensi
    # Markdown Telegram: *bold*, \`code\`, _italic_
    local msg
    msg="🚀 *ReLIFE Kernel — Build Dimulai*

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*         : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*         : ${KERNEL_NAME}
🍃 *Versi Kernel*   : \`${KERNEL_VERSION}\`
🏷 *Localversion*   : \`${KERNEL_LOCALVERSION:-tidak ada}\`

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔑 *KernelSU Next*  : ${ksu_status}
   └ Git Commit   : \`${KSU_GIT_COMMIT}\`
   └ Last Commit  : ${KSU_LAST_COMMIT_MSG}
   └ Min Manager  : \`${KSU_MANAGER_VER}\`
   └ Integrasi    : ${KSU_INTEGRATION}
   └ Config       : ${KSU_CONFIG_STATUS}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 *Source*
🌿 *Branch*         : \`${BRANCH}\`
🔖 *Commit*         : \`${COMMIT_HASH}\`
💬 *Pesan Commit*   : ${COMMIT_MSG}
👤 *Author*         : ${COMMIT_AUTHOR}
📧 *Email*          : ${COMMIT_EMAIL}
📅 *Tgl Commit*     : ${COMMIT_DATE}
📊 *Total Commit*   : ${TOTAL_COMMITS}
🗂 *Dirty Tree*     : ${dirty_status}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛠 *Compiler*
🔧 *GCC 64-bit*     : \`${GCC_VER_FULL}\`
🔧 *GCC 32-bit*     : \`${GCC32_VER_FULL}\`
🔵 *Clang*          : \`${CLANG_VER_FULL}\`
🔗 *Linker*         : \`${LD_VER_FULL}\`
⚙️ *Defconfig*      : \`${DEFCONFIG}\`
🔨 *Jobs*           : ${JOBS} thread

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💻 *Host*
🖥 *Hostname*       : ${HOST_NAME}
🐧 *OS*             : ${HOST_OS}
⚙️ *CPU*            : ${HOST_CPU}
🧠 *Cores*          : ${HOST_CORES}
💾 *RAM*            : ${RAM_FREE} GB bebas / ${RAM_TOTAL} GB total
🔃 *Swap*           : ${SWAP_TOTAL} GB
💿 *Disk*           : ${DISK_FREE} bebas / ${DISK_TOTAL} (${DISK_PCT} terpakai)

🕒 *Mulai*          : ${BUILD_DATETIME}"

    TG_MSG_ID=$(tg_send "$msg")
    log_ok "Notif START terkirim (ID: ${TG_MSG_ID:-GAGAL})"
}

notify_compiling() {
    log_tg "Edit pesan → COMPILING..."
    tg_edit "🔨 *ReLIFE Kernel — Sedang Dikompilasi...*

📱 *Device*     : \`${DEVICE}\` — ${DEVICE_FULL}
🍃 *Versi*      : \`${KERNEL_VERSION}\`
🌿 *Branch*     : \`${BRANCH}\`
🔖 *Commit*     : \`${COMMIT_HASH}\`
💬 *Msg*        : ${COMMIT_MSG}
👤 *Author*     : ${COMMIT_AUTHOR}

🔧 *GCC 64*     : \`${GCC_VER}\`
🔧 *GCC 32*     : \`${GCC32_VER}\`
🔵 *Clang*      : \`${CLANG_VER}\`
🔗 *LD*         : \`${LD_VER}\`
⚙️ *Defconfig*  : \`${DEFCONFIG}\`
🔨 *Jobs*       : ${JOBS} thread

💾 *RAM bebas*  : ${RAM_FREE} GB
💿 *Disk bebas* : ${DISK_FREE}

⏳ Kompilasi berjalan, harap tunggu...
🕒 Mulai : ${BUILD_DATETIME}"
}

notify_packing() {
    log_tg "Edit pesan → PACKING..."
    tg_edit "📦 *ReLIFE Kernel — Membuat Zip...*

📱 *Device*          : \`${DEVICE}\`
🍃 *Versi*           : \`${KERNEL_VERSION}\`
⏱ *Waktu Compile*   : ${BUILD_TIME}
🖼 *Image*           : \`${IMG_USED}\` (${IMG_SIZE})
⚠️ *Warnings*        : ${WARNINGS}
🔢 *Errors*          : ${ERRORS_COUNT}

⏳ Membuat flashable zip..."
}

notify_uploading() {
    log_tg "Edit pesan → UPLOADING..."
    tg_edit "📤 *ReLIFE Kernel — Mengupload ke Telegram...*

📱 *Device*          : \`${DEVICE}\`
📁 *File*            : \`${ZIP_NAME}\`
📏 *Ukuran Zip*      : ${ZIP_SIZE}
🖼 *Image*           : \`${IMG_USED}\` (${IMG_SIZE})
⏱ *Waktu Compile*   : ${BUILD_TIME}

⏳ Mengupload..."
}

notify_success() {
    local zip_path="$ANYKERNEL_DIR/$ZIP_NAME"

    local ksu_cap
    if [[ "$KSU_ENABLED" == "true" ]]; then
        ksu_cap="✅ Aktif — v${KSU_VERSION} (${KSU_GIT_TAG})
   Commit KSU   : \`${KSU_GIT_COMMIT}\`
   Min Manager  : \`${KSU_MANAGER_VER}\`
   Config       : ${KSU_CONFIG_STATUS}"
    else
        ksu_cap="❌ Tidak ada"
    fi

    local warn_note=""
    [[ "$WARNINGS" -gt 0 ]] && \
        warn_note="⚠️ *Warnings*        : ${WARNINGS} (lihat warning log terlampir)"

    # Caption untuk zip — pakai -F caption= seperti kode referensi
    local caption
    caption="✅ *ReLIFE Kernel — Build Berhasil!*

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*          : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*          : ${KERNEL_NAME}
🍃 *Versi Kernel*    : \`${KERNEL_VERSION}\`
🏷 *Localversion*    : \`${KERNEL_LOCALVERSION:-tidak ada}\`

🔑 *KernelSU Next*   : ${ksu_cap}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 *Source*
🌿 *Branch*          : \`${BRANCH}\`
🔖 *Commit*          : \`${COMMIT_HASH}\`
💬 *Pesan Commit*    : ${COMMIT_MSG}
👤 *Author*          : ${COMMIT_AUTHOR}
📅 *Tgl Commit*      : ${COMMIT_DATE}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛠 *Compiler*
🔧 *GCC 64-bit*      : \`${GCC_VER_FULL}\`
🔧 *GCC 32-bit*      : \`${GCC32_VER_FULL}\`
🔵 *Clang*           : \`${CLANG_VER_FULL}\`
🔗 *Linker*          : \`${LD_VER_FULL}\`
⚙️ *Defconfig*       : \`${DEFCONFIG}\`
🖼 *Image*           : \`${IMG_USED}\` (${IMG_SIZE})
🔨 *Jobs*            : ${JOBS} thread
⏱ *Waktu Compile*   : ${BUILD_TIME}
🕒 *Tanggal Build*   : ${BUILD_DATETIME}
${warn_note}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 *File*            : \`${ZIP_NAME}\`
📏 *Ukuran Zip*      : ${ZIP_SIZE}
🔐 *MD5*             :
\`${MD5_HASH}\`
🔑 *SHA1*            :
\`${SHA1_HASH}\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ *Flash via TWRP / Custom Recovery*"

    # 1. Upload kernel zip (sama persis dengan kode referensi)
    log_tg "Upload kernel zip..."
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"${zip_path}" \
        -F parse_mode=Markdown \
        -F caption="${caption}" > /dev/null
    log_ok "Kernel zip terkirim"

    # 2. Upload full build log
    tg_upload "$LOG_FILE" \
"📋 *Full Build Log — Berhasil*
${KERNEL_NAME} \`${KERNEL_VERSION}\` | \`${BRANCH}\` | \`${COMMIT_HASH}\`
Compiler: ${COMPILER_STRING}
KernelSU: $([ "$KSU_ENABLED" == "true" ] && echo "✅ v${KSU_VERSION}" || echo "❌")
Warnings: ${WARNINGS} | Waktu: ${BUILD_TIME}"

    # 3. Upload warning log jika ada
    if [[ "$WARNINGS" -gt 0 ]] && [[ -f "$WARN_LOG" ]] && [[ -s "$WARN_LOG" ]]; then
        tg_upload "$WARN_LOG" \
"⚠️ *Warning Summary* — ${WARNINGS} warnings
${KERNEL_NAME} \`${KERNEL_VERSION}\` | \`${COMMIT_HASH}\`"
    fi

    # 4. Edit pesan awal → summary final
    tg_edit "✅ *Build Selesai — ${KERNEL_NAME} \`${KERNEL_VERSION}\`*

📦 \`${ZIP_NAME}\`
🖼 Image         : \`${IMG_USED}\` (${IMG_SIZE})
📏 Ukuran Zip    : ${ZIP_SIZE}
⏱ Waktu Compile : ${BUILD_TIME}
⚠️ Warnings      : ${WARNINGS}
🔑 KernelSU Next : $([ "$KSU_ENABLED" == "true" ] && echo "✅ v${KSU_VERSION} | ${KSU_GIT_TAG}" || echo "❌")
🔐 MD5           : \`${MD5_HASH}\`
🕒 Selesai       : $(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")"
}

notify_error() {
    local stage="${ERROR_STAGE:-unknown}"
    local line="${1:-?}"

    # Preview error inline dari log
    local last_err="Tidak ada error yang tertangkap"
    if [[ -f "$LOG_FILE" ]]; then
        local raw
        raw=$(grep -aE "(error:|Error|FAILED|undefined reference|multiple definition|fatal:)" \
            "$LOG_FILE" 2>/dev/null | \
            grep -v "^Binary\|Werror\|^--" | tail -15 | \
            sed 's/\x1b\[[0-9;]*m//g' | sed "s/\`/'/g" | \
            awk '{print NR". "$0}' || true)
        [[ -n "$raw" ]] && last_err="$raw"
        [[ ${#last_err} -gt 900 ]] && \
            last_err="${last_err:0:900}
..._(terpotong — lihat log)_"
    fi

    # 1. Edit pesan awal → status GAGAL
    log_tg "Edit pesan → GAGAL..."
    tg_edit "❌ *Build GAGAL — \`${stage}\`*

📱 Device    : \`${DEVICE}\`
🌿 Branch    : \`${BRANCH}\`
🔖 Commit    : \`${COMMIT_HASH}\`
💬 Msg       : ${COMMIT_MSG}
💥 Gagal di  : \`${stage}\`
📍 Baris     : ${line}
⚠️ Warnings  : ${WARNINGS}
🔢 Errors    : ${ERRORS_COUNT}
🕒 Waktu     : $(TZ=Asia/Jakarta date +"%H:%M WIB")

📋 Log + preview error di bawah..."

    # 2. Pesan baru — preview error inline
    log_tg "Kirim preview error inline..."
    local err_msg
    err_msg="❌ *ReLIFE Kernel — Build GAGAL*

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*        : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*        : ${KERNEL_NAME}
🍃 *Versi*         : \`${KERNEL_VERSION}\`
🌿 *Branch*        : \`${BRANCH}\`
🔖 *Commit*        : \`${COMMIT_HASH}\`
💬 *Pesan Commit*  : ${COMMIT_MSG}
👤 *Author*        : ${COMMIT_AUTHOR}

🔧 *GCC 64*        : \`${GCC_VER}\`
🔧 *GCC 32*        : \`${GCC32_VER}\`
🔵 *Clang*         : \`${CLANG_VER}\`
🔗 *LD*            : \`${LD_VER}\`
⚙️ *Defconfig*     : \`${DEFCONFIG}\`

💥 *Gagal di*      : \`${stage}\`
📍 *Baris Script*  : ${line}
⚠️ *Warnings*      : ${WARNINGS}
🔢 *Errors*        : ${ERRORS_COUNT}
🕒 *Waktu*         : ${BUILD_DATETIME}

🔴 *Preview Error (15 baris terakhir):*
\`\`\`
${last_err}
\`\`\`"
    tg_send "$err_msg" > /dev/null

    # 3. Upload full build log
    log_tg "Upload full log..."
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"${LOG_FILE}" \
        -F parse_mode=Markdown \
        -F caption="❌ *Full Build Log — GAGAL*
Stage: \`${stage}\` | Baris: ${line}
${KERNEL_NAME} \`${KERNEL_VERSION}\` | \`${BRANCH}\` | \`${COMMIT_HASH}\`
GCC: ${GCC_VER} | Clang: ${CLANG_VER}
Warnings: ${WARNINGS} | Errors: ${ERRORS_COUNT}" > /dev/null
    log_ok "Full log terkirim"

    # 4. Buat & upload filtered error log
    grep -aE "(error:|Error|FAILED|undefined reference|multiple definition|fatal:)" \
        "$LOG_FILE" 2>/dev/null | \
        grep -v "^Binary\|Werror\|^--" | \
        sed 's/\x1b\[[0-9;]*m//g' > "$ERR_LOG" || true

    if [[ -s "$ERR_LOG" ]]; then
        local err_lines; err_lines=$(wc -l < "$ERR_LOG")
        log_tg "Upload filtered error log ($err_lines baris)..."
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
            -F chat_id="${TG_CHAT_ID}" \
            -F document=@"${ERR_LOG}" \
            -F parse_mode=Markdown \
            -F caption="🔴 *Filtered Error Log* — ${err_lines} baris error
Stage: \`${stage}\` | Baris: ${line}
${KERNEL_NAME} | \`${COMMIT_HASH}\`
(Hanya baris yang mengandung error)" > /dev/null
        log_ok "Error log terkirim"
    fi
}

# ════════════════════════════════════════════════════════
#  ERROR TRAP
# ════════════════════════════════════════════════════════

on_error() {
    local exit_code=$?
    local line="$1"
    log_e "Gagal di baris ${line} (exit ${exit_code})"
    log_e "Stage: ${ERROR_STAGE:-unknown}"
    notify_error "$line"
    exit "$exit_code"
}

trap 'on_error $LINENO' ERR

# ════════════════════════════════════════════════════════
#  CLONE ANYKERNEL
# ════════════════════════════════════════════════════════

clone_anykernel() {
    if [[ ! -d "$ANYKERNEL_DIR" ]]; then
        log "Cloning AnyKernel3..."
        git clone -b mi8937 \
            https://github.com/rahmatsobrian/AnyKernel3.git \
            "$ANYKERNEL_DIR" || exit 1
        log_ok "AnyKernel3 cloned"
    else
        log "AnyKernel3 sudah ada, update..."
        git -C "$ANYKERNEL_DIR" pull --rebase --autostash 2>/dev/null \
            && log_ok "Updated" \
            || log_w "Pull gagal, pakai lokal"
    fi
}

# ════════════════════════════════════════════════════════
#  BUILD
# ════════════════════════════════════════════════════════

build_kernel() {
    echo -e "${yellow}[+] Building kernel...${white}"

    [[ ! -f "Makefile" ]] && {
        ERROR_STAGE="Sanity Check"
        log_e "Bukan di root kernel source!"
        exit 1
    }

    ERROR_STAGE="Clean"
    rm -rf out
    log_ok "out/ dibersihkan"

    # Defconfig
    ERROR_STAGE="Defconfig"
    echo -e "${yellow}[+] Applying defconfig: $DEFCONFIG${white}"
    make O=out ARCH=arm64 "$DEFCONFIG" 2>&1 | tee -a "$LOG_FILE"
    log_ok "Defconfig OK"

    # Kumpulkan info setelah defconfig
    get_compiler_info
    get_kernel_version
    get_kernelsu_info

    # Kirim notif START ke Telegram
    notify_start

    # Compile
    ERROR_STAGE="Compile"
    echo -e "${yellow}[+] Kompilasi dimulai ($JOBS jobs)...${white}"
    notify_compiling

    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    make -j$(nproc) O=out ARCH=arm64 \
        CROSS_COMPILE=$TC64 \
        CROSS_COMPILE_ARM32=$TC32 \
        CROSS_COMPILE_COMPAT=$TC32 \
        2>&1 | tee -a "$LOG_FILE"

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    DIFF=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((DIFF / 60)) min $((DIFF % 60)) sec"

    WARNINGS=$(grep -c " warning:" "$LOG_FILE" 2>/dev/null || echo 0)
    ERRORS_COUNT=$(grep -c " error:" "$LOG_FILE" 2>/dev/null || echo 0)

    # Simpan warning log
    if [[ "$WARNINGS" -gt 0 ]]; then
        grep " warning:" "$LOG_FILE" 2>/dev/null | \
            sed 's/\x1b\[[0-9;]*m//g' | sort | uniq -c | sort -rn \
            > "$WARN_LOG" || true
    fi

    get_kernel_version
    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"

    echo -e "${green}[✓] Kompilasi selesai: ${BUILD_TIME}${white}"
    echo -e "${green}[✓] Warnings: ${WARNINGS} | Errors: ${ERRORS_COUNT}${white}"
}

# ════════════════════════════════════════════════════════
#  PACK
# ════════════════════════════════════════════════════════

pack_kernel() {
    echo -e "${yellow}[+] Packing AnyKernel...${white}"

    clone_anykernel
    cd "$ANYKERNEL_DIR" || exit 1

    rm -f Image* *.zip

    ERROR_STAGE="Detect Image"
    if [[ -f "$KIMG_DTB" ]]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
        IMG_SIZE=$(du -sh "$KIMG_DTB" | awk '{print $1}')
    elif [[ -f "$KIMG_GZ" ]]; then
        cp "$KIMG_GZ" Image.gz
        IMG_USED="Image.gz"
        IMG_SIZE=$(du -sh "$KIMG_GZ" | awk '{print $1}')
    elif [[ -f "$KIMG_RAW" ]]; then
        cp "$KIMG_RAW" Image
        IMG_USED="Image"
        IMG_SIZE=$(du -sh "$KIMG_RAW" | awk '{print $1}')
    else
        log_e "Tidak ada kernel image ditemukan!"
        log_e "Expected: Image.gz-dtb | Image.gz | Image"
        ERROR_STAGE="No Kernel Image"
        exit 1
    fi
    log_ok "Image: $IMG_USED ($IMG_SIZE)"

    notify_packing

    ERROR_STAGE="Create Zip"
    zip -r9 "$ZIP_NAME" . -x ".git*" "README.md" "*.log" "*.sh"
    MD5_HASH=$(md5sum "$ZIP_NAME" | awk '{print $1}')
    SHA1_HASH=$(sha1sum "$ZIP_NAME" | awk '{print $1}')
    ZIP_SIZE=$(du -sh "$ZIP_NAME" | awk '{print $1}')

    echo -e "${green}[✓] Zip created: $ZIP_NAME ($ZIP_SIZE)${white}"
    echo -e "${green}[✓] MD5: $MD5_HASH${white}"

    cd "$ROOTDIR" || exit 1
}

# ════════════════════════════════════════════════════════
#  UPLOAD
# ════════════════════════════════════════════════════════

upload_telegram() {
    local zip_path="$ANYKERNEL_DIR/$ZIP_NAME"
    [[ ! -f "$zip_path" ]] && { log_w "Zip tidak ada, skip upload"; return; }

    echo -e "${yellow}[+] Uploading to Telegram...${white}"
    ERROR_STAGE="Upload Telegram"

    notify_uploading
    notify_success

    echo -e "${green}[✓] Upload selesai!${white}"
}

# ════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════

START=$(TZ=Asia/Jakarta date +%s)

echo -e "${yellow}[+] ReLIFE Kernel Build Script${white}"
echo -e "${yellow}[+] Log: $LOG_FILE${white}"

build_kernel
pack_kernel
upload_telegram

END=$(TZ=Asia/Jakarta date +%s)
echo -e "${green}[✓] Done in $((END - START)) seconds${white}"
