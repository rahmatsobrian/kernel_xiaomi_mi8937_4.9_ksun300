#!/usr/bin/env bash

# =========================================================
#        ReLIFE Kernel CI - Ultimate Build Script
# =========================================================

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
white='\033[0m'

# ================= PATH =================
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

# ================= TOOLCHAIN =================
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

# ================= INFO =================
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"

# ================= TELEGRAM =================
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

# ================= DATE =================
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y %H:%M WIB")

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
TC_INFO="unknown"
IMG_USED="unknown"
MD5_HASH="unknown"
SHA1_HASH="unknown"
ZIP_NAME=""

# ================= MACHINE INFO =================
HOST_KERNEL=$(uname -r)
HOST_OS=$(uname -o)
HOST_ARCH=$(uname -m)
HOST_CPU=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d ":" -f2 | xargs)
HOST_CORES=$(nproc)
HOST_RAM=$(free -h | awk '/Mem:/ {print $2}')
HOST_DISK=$(df -h / | awk 'NR==2 {print $4}')

# ================= GIT INFO =================
KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
KERNEL_COMMIT=$(git log --pretty=format:'%h' -n 1 2>/dev/null)
KERNEL_COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null)

# =========================================================
#                 FUNCTIONS
# =========================================================

clone_anykernel() {

if [ ! -d "$ANYKERNEL_DIR" ]; then

echo -e "$yellow[+] Cloning AnyKernel3...$white"

git clone -b mi8937 https://github.com/rahmatsobrian/AnyKernel3.git "$ANYKERNEL_DIR" || exit 1

fi
}

# =========================================================

get_toolchain_info() {

if command -v "${TC64}gcc" >/dev/null 2>&1; then

TC_INFO=$("${TC64}gcc" --version | head -n1)

elif command -v gcc >/dev/null 2>&1; then

TC_INFO=$(gcc --version | head -n1)

else

TC_INFO="Unknown"

fi
}

# =========================================================

get_kernel_version() {

if [ -f "Makefile" ]; then

VERSION=$(grep '^VERSION =' Makefile | awk '{print $3}')
PATCHLEVEL=$(grep '^PATCHLEVEL =' Makefile | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL =' Makefile | awk '{print $3}')

KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"

fi
}

# =========================================================

get_kernelsu_info() {

if [ -d "KernelSU" ]; then

KSU_VERSION=$(grep "KSU_VERSION" KernelSU/kernel/Makefile 2>/dev/null | awk '{print $3}')

if [ -z "$KSU_VERSION" ]; then
KSU_VERSION="Detected"
fi

else

KSU_VERSION="Not Present"

fi
}

# =========================================================

send_telegram_start() {

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
-d chat_id="${TG_CHAT_ID}" \
-d parse_mode=Markdown \
-d text="🚀 *Kernel Build Started*

📱 Device : \`${DEVICE}\`
🌿 Kernel : \`${KERNEL_NAME}\`

🧬 Branch : \`${KERNEL_BRANCH}\`
🔧 Commit : \`${KERNEL_COMMIT}\`

🖥 Machine :
• OS : \`${HOST_OS}\`
• Kernel : \`${HOST_KERNEL}\`
• CPU : \`${HOST_CPU}\`
• Cores : \`${HOST_CORES}\`
• RAM : \`${HOST_RAM}\`
• Free Disk : \`${HOST_DISK}\`
"
}

# =========================================================

send_telegram_error() {

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
-d chat_id="${TG_CHAT_ID}" \
-d parse_mode=Markdown \
-d text="❌ *Kernel Build Failed*

📱 Device : \`${DEVICE}\`
🌿 Kernel : \`${KERNEL_NAME}\`
🔧 Commit : \`${KERNEL_COMMIT}\`
"
}

# =========================================================

build_kernel() {

echo -e "$yellow[+] Building kernel...$white"

rm -rf out

make O=out ARCH=arm64 rahmatmsm8937hos_defconfig || {

send_telegram_error
exit 1
}

get_toolchain_info
get_kernel_version
get_kernelsu_info

BUILD_START=$(date +%s)

send_telegram_start

make -j$(nproc) O=out ARCH=arm64 \
CROSS_COMPILE=$TC64 \
CROSS_COMPILE_ARM32=$TC32 \
CROSS_COMPILE_COMPAT=$TC32 || {

send_telegram_error
exit 1
}

BUILD_END=$(date +%s)

DIFF=$((BUILD_END - BUILD_START))

BUILD_TIME="$((DIFF / 60)) min $((DIFF % 60)) sec"

ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"
}

# =========================================================

pack_kernel() {

echo -e "$yellow[+] Packing AnyKernel...$white"

clone_anykernel

cd "$ANYKERNEL_DIR" || exit 1

rm -f Image* *.zip

if [ -f "$KIMG_DTB" ]; then

cp "$KIMG_DTB" Image.gz-dtb
IMG_USED="Image.gz-dtb"

elif [ -f "$KIMG" ]; then

cp "$KIMG" Image.gz
IMG_USED="Image.gz"

else

send_telegram_error
exit 1

fi

zip -r9 "$ZIP_NAME" . -x ".git*" "README.md"

MD5_HASH=$(md5sum "$ZIP_NAME" | awk '{print $1}')
SHA1_HASH=$(sha1sum "$ZIP_NAME" | awk '{print $1}')

ZIP_SIZE=$(du -h "$ZIP_NAME" | awk '{print $1}')
}

# =========================================================

upload_telegram() {

ZIP_PATH="$ANYKERNEL_DIR/$ZIP_NAME"

[ ! -f "$ZIP_PATH" ] && return

echo -e "$yellow[+] Uploading to Telegram...$white"

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
-F chat_id="${TG_CHAT_ID}" \
-F document=@"${ZIP_PATH}" \
-F parse_mode=Markdown \
-F caption="🔥 *Kernel Build Success*

📱 Device : \`${DEVICE}\`
🌿 Kernel : \`${KERNEL_NAME}\`
🍃 Version : \`${KERNEL_VERSION}\`

🌱 KernelSU : \`${KSU_VERSION}\`

🧬 Branch : \`${KERNEL_BRANCH}\`
🔧 Commit : \`${KERNEL_COMMIT}\`

🛠 Toolchain :
\`${TC_INFO}\`

📦 Image :
\`${IMG_USED}\`

📁 Zip Size :
\`${ZIP_SIZE}\`

⏱ Build Time :
\`${BUILD_TIME}\`

📅 Date :
\`${BUILD_DATETIME}\`

🖥 Machine :
• CPU : \`${HOST_CPU}\`
• Cores : \`${HOST_CORES}\`
• RAM : \`${HOST_RAM}\`

🔐 MD5
\`${MD5_HASH}\`

🔑 SHA1
\`${SHA1_HASH}\`

✅ Flash via Recovery"
}

# =========================================================
#                       RUN
# =========================================================

START=$(date +%s)

build_kernel
pack_kernel
upload_telegram

END=$(date +%s)

echo -e "$green[✓] Done in $((END - START)) seconds$white"
