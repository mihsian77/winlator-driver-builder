#!/bin/bash -e

# Winlator Pulse Turnip Driver Builder
# Based on whitebelyash/AdrenoToolsDrivers turnip_builder_upstream.sh
# Modified to output .tzst format for Winlator

green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

BUILD_VERSION=${BUILD_VERSION:-"latest"}
MESASRC=${MESASRC:-"https://gitlab.freedesktop.org/mesa/mesa"}
PATCH_URL=${PATCH_URL:-"https://github.com/whitebelyash/mesa-tu8/releases/download/patchset-head-v2/tu8_kgsl.patch"}

deps="git meson ninja patchelf unzip curl pip flex bison zip glslang glslangValidator tar zstd"
workdir="$(pwd)/build"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
srcfolder="mesa"

clear

echo "====== Winlator Pulse Turnip Builder V$BUILD_VERSION ======"
echo "Source: $MESASRC"
echo "Patch: $PATCH_URL"
echo ""

check_deps() {
    echo "Checking dependencies..."
    for dep in $deps; do
        if command -v "$dep" >/dev/null 2>&1; then
            echo -e "$green - $dep found $nocolor"
        else
            echo -e "$red - $dep not found $nocolor"
            deps_missing=1
        fi
    done
    
    if [ "$deps_missing" == "1" ]; then
        echo "Please install missing dependencies"
        exit 1
    fi
    
    pip install mako &> /dev/null
}

prepare_workdir() {
    echo ""
    echo "Preparing work directory..."
    mkdir -p "$workdir" && cd "$workdir"
    
    echo "Downloading Android NDK..."
    curl -sL "https://dl.google.com/android/repository/$ndkver-linux.zip" -o "$ndkver-linux.zip"
    unzip -q "$ndkver-linux.zip"
    
    echo "Downloading Mesa source..."
    git clone --depth=1 -b main "$MESASRC" "$srcfolder"
    cd "$srcfolder"
}

apply_patch() {
    echo ""
    echo "Applying patches..."
    if [ -n "$PATCH_URL" ]; then
        wget -q "$PATCH_URL" -O tu8_kgsl.patch
        if git apply --check tu8_kgsl.patch 2>/dev/null; then
            git apply tu8_kgsl.patch
            echo -e "$green - tu8_kgsl.patch applied $nocolor"
        else
            echo -e "$red - Failed to apply tu8_kgsl.patch, skipping $nocolor"
        fi
    fi
}

build_turnip() {
    echo ""
    echo "Building Turnip driver..."
    
    mkdir -p "$workdir/bin"
    ln -sf "$ndk/clang" "$workdir/bin/cc"
    ln -sf "$ndk/clang++" "$workdir/bin/c++"
    export PATH="$workdir/bin:$ndk:$PATH"
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export RANLIB=llvm-ranlib
    export STRIP=llvm-strip
    export OBJDUMP=llvm-objdump
    export OBJCOPY=llvm-objcopy
    export LDFLAGS="-fuse-ld=lld"
    
    GITHASH=$(git rev-parse --short HEAD)
    
    echo "Generating build files..."
    
    cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '$ndk/ld.lld'
cpp_ld = '$ndk/ld.lld'
strip = '$ndk/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$ndk/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

    cat <<EOF >"native.txt"
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

    meson setup build-android-aarch64 \
        --cross-file "android-aarch64.txt" \
        --native-file "native.txt" \
        --prefix /tmp/turnip-build \
        -Dbuildtype=release \
        -Dstrip=true \
        -Dplatforms=android \
        -Dvideo-codecs= \
        -Dplatform-sdk-version="$sdkver" \
        -Dandroid-stub=true \
        -Dgallium-drivers= \
        -Dvulkan-drivers=freedreno \
        -Dvulkan-beta=true \
        -Dfreedreno-kmds=kgsl \
        -Degl=disabled \
        -Dandroid-libbacktrace=disabled \
        --reconfigure
    
    echo "Compiling..."
    ninja -C build-android-aarch64 install
    
    if [ ! -f /tmp/turnip-build/lib/libvulkan_freedreno.so ]; then
        echo -e "$red Build failed! $nocolor"
        exit 1
    fi
    
    echo -e "$green Build success! $nocolor"
    echo "  SO size: $(du -h /tmp/turnip-build/lib/libvulkan_freedreno.so | cut -f1)"
    
    pack_tzst "$GITHASH"
}

pack_tzst() {
    GITHASH=$1
    echo ""
    echo "Packing as .tzst for Winlator..."
    
    PACKDIR="/tmp/turnip-tzst"
    rm -rf "$PACKDIR"
    mkdir -p "$PACKDIR/usr/lib"
    mkdir -p "$PACKDIR/usr/share/vulkan/icd.d"
    
    # Copy the driver
    cp /tmp/turnip-build/lib/libvulkan_freedreno.so "$PACKDIR/usr/lib/"
    
    # Create ICD json
    cat <<EOF >"$PACKDIR/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
{
    "ICD": {
        "api_version": "1.4.335",
        "library_arch": "64",
        "library_path": "/data/data/com.winlator/files/rootfs/lib/libvulkan_freedreno.so"
    },
    "file_format_version": "1.0.1"
}
EOF
    
    # Create tzst archive
    OUTPUT_NAME="turnip-$BUILD_VERSION-git$GITHASH.tzst"
    cd "$PACKDIR"
    tar --zstd -cf "/tmp/$OUTPUT_NAME" usr/
    
    echo -e "$green Packed: /tmp/$OUTPUT_NAME $nocolor"
    echo "  Size: $(du -h /tmp/$OUTPUT_NAME | cut -f1)"
}

# Run
check_deps
prepare_workdir
apply_patch
build_turnip

echo ""
echo "====== Done! ======"
