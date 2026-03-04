#!/usr/bin/env bash

# =========================================================
# 🚀 ReLIFE Kernel CI - Ultimate Telegram Build Script
# =========================================================

ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"
LOGFILE="$ROOTDIR/build.log"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

KERNEL_NAME="ReLIFE"
DEVICE="mi8937"
DEVICE_FULL="Xiaomi Snapdragon 430/435"
DEFCONFIG="rahmatmsm8937hos_defconfig"

TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

DATE=$(date +"%d %B %Y %H:%M")

# =========================================================
# MACHINE INFO
# =========================================================

HOST_NAME=$(hostname)
HOST_OS=$(uname -sr)
HOST_CPU=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
HOST_CORES=$(nproc)
RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
RAM_FREE=$(free -h | awk '/Mem:/ {print $7}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')

# =========================================================
# GIT INFO
# =========================================================

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)
COMMIT_AUTHOR=$(git log -1 --pretty=%an)
COMMIT_DATE=$(git log -1 --date=format:"%d %b %Y %H:%M" --pretty=%cd)
TOTAL_COMMITS=$(git rev-list --count HEAD)
DIRTY_COUNT=$(git status --porcelain | wc -l)

# =========================================================
# TELEGRAM
# =========================================================

send_msg() {

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
-d chat_id="${TG_CHAT_ID}" \
--data-urlencode text="$1" >/dev/null

}

upload_file() {

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
-F chat_id="${TG_CHAT_ID}" \
-F document=@"$1" \
--form-string caption="$2" >/dev/null

}

# =========================================================
# DETECT COMPILER
# =========================================================

detect_compiler() {

if command -v clang >/dev/null; then

COMPILER="Clang"
COMPILER_VER=$(clang --version | head -1)

else

COMPILER="GCC"
COMPILER_VER=$(${TC64}gcc --version | head -1)

fi

LINKER=$(${TC64}ld --version | head -1)

}

# =========================================================
# KERNEL VERSION
# =========================================================

get_kernel_version() {

VERSION=$(grep '^VERSION =' Makefile | awk '{print $3}')
PATCHLEVEL=$(grep '^PATCHLEVEL =' Makefile | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL =' Makefile | awk '{print $3}')

KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"

}

# =========================================================
# LOCALVERSION
# =========================================================

get_localversion() {

if [ -f out/.config ]; then

LOCALVERSION=$(grep "^CONFIG_LOCALVERSION=" out/.config \
| sed 's/CONFIG_LOCALVERSION="//' \
| sed 's/"//')

fi

}

# =========================================================
# KERNELSU DETECTION
# =========================================================

detect_kernelsu() {

KSU_ENABLED="❌ Tidak ada"
KSU_VERSION="N/A"
KSU_MANAGER="N/A"
KSU_TAG="N/A"

for d in KernelSU kernelsu drivers/kernelsu fs/kernelsu; do

if [ -d "$ROOTDIR/$d" ]; then

KSU_ENABLED="✅ Aktif"
KSU_DIR="$ROOTDIR/$d"

if git -C "$KSU_DIR" rev-parse --git-dir >/dev/null 2>&1; then

KSU_TAG=$(git -C "$KSU_DIR" describe --tags --abbrev=0 2>/dev/null)
KSU_COMMIT=$(git -C "$KSU_DIR" rev-parse --short HEAD)

fi

KSU_MANAGER=$(grep -r MANAGER_MIN_VERSION "$KSU_DIR" 2>/dev/null \
| grep -oE '[0-9]{4,}' \
| head -1)

break

fi

done

}

# =========================================================
# SUSFS
# =========================================================

detect_susfs() {

SUSFS="❌ Tidak ada"

for d in susfs fs/susfs drivers/susfs security/susfs; do

if [ -d "$ROOTDIR/$d" ]; then

SUSFS="✅ Aktif ($d)"

fi

done

}

# =========================================================
# START MESSAGE
# =========================================================

send_start() {

TREE="✅ Bersih"

if [ "$DIRTY_COUNT" -gt 0 ]; then
TREE="⚠️ Dirty ($DIRTY_COUNT file)"
fi

MSG="🚀 ReLIFE Kernel — Build Dimulai
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📱 Device : $DEVICE — $DEVICE_FULL
🍃 Kernel : $KERNEL_VERSION
🏷 Localversion : $LOCALVERSION

🔑 KernelSU : $KSU_ENABLED
🧬 Tag : $KSU_TAG
📱 Manager Min : $KSU_MANAGER

🛡 SUSFS : $SUSFS

📂 Source
🌿 Branch : $BRANCH
🔖 Commit : $COMMIT_HASH
💬 Msg : $COMMIT_MSG
👤 Author : $COMMIT_AUTHOR
📅 Date : $COMMIT_DATE
📊 Commits : $TOTAL_COMMITS
🗂 Tree : $TREE

🛠 Build
⚙️ Compiler : $COMPILER_VER
🔗 Linker : $LINKER
🔧 Defconfig : $DEFCONFIG
🖥 Jobs : $HOST_CORES

💻 Host
🖥 Hostname : $HOST_NAME
⚙️ CPU : $HOST_CPU
🧠 Cores : $HOST_CORES
💾 RAM : $RAM_FREE / $RAM_TOTAL
💿 Disk : $DISK_FREE / $DISK_TOTAL
🐧 OS : $HOST_OS

🕒 Start : $DATE"

send_msg "$MSG"

}

# =========================================================
# BUILD
# =========================================================

build_kernel() {

rm -rf out

make O=out ARCH=arm64 $DEFCONFIG

send_start

START=$(date +%s)

make -j$(nproc) O=out ARCH=arm64 \
CROSS_COMPILE=$TC64 \
CROSS_COMPILE_ARM32=$TC32 \
CROSS_COMPILE_COMPAT=$TC32 2>&1 | tee $LOGFILE

END=$(date +%s)

BUILD_TIME="$((END-START)) sec"

}

# =========================================================
# ANALYZE LOG
# =========================================================

analyze_log() {

WARNINGS=$(grep -i "warning:" $LOGFILE | wc -l)
ERRORS=$(grep -i "error:" $LOGFILE | wc -l)

}

# =========================================================
# PACK
# =========================================================

pack_kernel() {

if [ ! -d "$ANYKERNEL_DIR" ]; then
git clone https://github.com/rahmatsobrian/AnyKernel3.git "$ANYKERNEL_DIR"
fi

cd "$ANYKERNEL_DIR"

rm -f *.zip Image*

if [ -f "$KIMG_DTB" ]; then
cp "$KIMG_DTB" Image.gz-dtb
IMG="Image.gz-dtb"
else
cp "$KIMG" Image.gz
IMG="Image.gz"
fi

IMG_SIZE=$(du -h $IMG | awk '{print $1}')

ZIP="ReLIFE-${DEVICE}-${KERNEL_VERSION}.zip"

zip -r9 $ZIP *

MD5=$(md5sum $ZIP | awk '{print $1}')
SHA1=$(sha1sum $ZIP | awk '{print $1}')
SIZE=$(du -h $ZIP | awk '{print $1}')

}

# =========================================================
# SUCCESS
# =========================================================

send_success() {

MSG="✅ ReLIFE Kernel Build Sukses

📱 Device : $DEVICE
🍃 Kernel : $KERNEL_VERSION

📦 Image : $IMG ($IMG_SIZE)
📁 Zip : $SIZE

⏱ Build Time : $BUILD_TIME

📊 Warning : $WARNINGS
❌ Error : $ERRORS

🔐 MD5
$MD5

🔑 SHA1
$SHA1"

upload_file "$ANYKERNEL_DIR/$ZIP" "$MSG"

upload_file "$LOGFILE" "📋 Build Log"

}

# =========================================================
# ERROR
# =========================================================

send_error() {

MSG="❌ Build Gagal

📱 Device : $DEVICE
🌿 Branch : $BRANCH
🔖 Commit : $COMMIT_HASH

⚠️ Warning : $WARNINGS
❌ Error : $ERRORS

📋 Log akan dikirim"

send_msg "$MSG"

upload_file "$LOGFILE" "❌ Build Error Log"

}

# =========================================================
# RUN
# =========================================================

detect_compiler
get_kernel_version
detect_kernelsu
detect_susfs

build_kernel

analyze_log

if [ "$ERRORS" -gt 0 ]; then
send_error
exit 1
fi

pack_kernel
send_success
