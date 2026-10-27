#!/bin/bash -e

# Winlator Pulse Turnip Driver Builder
# Based on whitebelyash/Banner build scripts, modified for tzst output

green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

BUILD_VERSION=${BUILD_VERSION:-"latest"}
MESASRC=${MESASRC:-"https://gitlab.freedesktop.org/mesa/mesa"}
VARIANT=${VARIANT:-"standard"}  # standard / a8xx / perf

deps="git meson ninja patchelf unzip curl pip flex bison zip glslang glslangValidator tar zstd python3"
workdir="$(pwd)/build"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
srcfolder="mesa"

echo "====== Winlator Pulse Turnip Builder ======"
echo "Version: $BUILD_VERSION"
echo "Variant: $VARIANT"
echo "Source: $MESASRC"
echo ""

check_deps() {
    echo "Checking dependencies..."
    deps_missing=0
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
    
    pip install mako &> /dev/null || true
}

prepare_workdir() {
    echo ""
    echo "Preparing work directory..."
    mkdir -p "$workdir" && cd "$workdir"
    
    echo "Downloading Android NDK r29..."
    curl -sL "https://dl.google.com/android/repository/$ndkver-linux.zip" -o "$ndkver-linux.zip"
    unzip -q "$ndkver-linux.zip"
    
    echo "Downloading Mesa source..."
    git clone --depth=1 -b main "$MESASRC" "$srcfolder"
    cd "$srcfolder"
}

apply_patches() {
    echo ""
    echo "Applying patches for variant: $VARIANT"
    
    # Common patches (from Banner)
    echo "  Applying common fixes..."
    
    # NDK r29 compatibility fixes (from Banner)
    sed -i 's/typedef const native_handle_t\* buffer_handle_t;/typedef void\* buffer_handle_t;/g' include/android_stub/cutils/native_handle.h || true
    sed -i 's/, hnd->handle/, (void \*)hnd->handle/g' src/util/u_gralloc/u_gralloc_fallback.c || true
    sed -i -E 's/([a-z_]+)->handle->/((const native_handle_t *)\1->handle)->/g' src/vulkan/runtime/vk_android.c || true
    
    # Variant-specific patches
    if [ "$VARIANT" == "a8xx" ] || [ "$VARIANT" == "perf" ]; then
        echo "  Applying A8XX patches..."
        # Download tu8_kgsl patch from whitebelyash
        wget -q "https://github.com/whitebelyash/mesa-tu8/releases/download/patchset-head-v2/tu8_kgsl.patch" -O /tmp/tu8_kgsl.patch || echo "  Warning: failed to download tu8_kgsl.patch"
        
        if [ -f /tmp/tu8_kgsl.patch ]; then
            if git apply --check /tmp/tu8_kgsl.patch 2>/dev/null; then
                git apply /tmp/tu8_kgsl.patch
                echo -e "$green  - tu8_kgsl.patch applied $nocolor"
            else
                echo -e "$red  - tu8_kgsl.patch failed, skipping $nocolor"
            fi
        fi
    fi
    
    if [ "$VARIANT" == "perf" ]; then
        echo "  Applying performance patches..."
        # Apply PWR_MAX patch (from Banner/WinNative)
        python3 /app/patches/apply_perf_variant.py || echo "  Warning: perf patch failed"
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
    export CFLAGS="-D__ANDROID__ -Wno-error -Wno-deprecated-declarations -Wno-incompatible-pointer-types-discards-qualifiers -Wno-incompatible-pointer-types"
    export CXXFLAGS="-D__ANDROID__ -Wno-error -Wno-deprecated-declarations -Wno-incompatible-pointer-types-discards-qualifiers -Wno-incompatible-pointer-types"
    
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
    
    cp /tmp/turnip-build/lib/libvulkan_freedreno.so "$PACKDIR/usr/lib/"
    
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
    
    OUTPUT_NAME="turnip-$BUILD_VERSION-$VARIANT-git$GITHASH.tzst"
    cd "$PACKDIR"
    tar --zstd -cf "/tmp/$OUTPUT_NAME" usr/
    
    echo -e "$green Packed: /tmp/$OUTPUT_NAME $nocolor"
    echo "  Size: $(du -h /tmp/$OUTPUT_NAME | cut -f1)"
    
    # Save hash for tracking
    echo "$GITHASH" > /tmp/mesa_hash.txt
}

# Run
check_deps
prepare_workdir
apply_patches
build_turnip

echo ""
echo "====== Done! ======"
