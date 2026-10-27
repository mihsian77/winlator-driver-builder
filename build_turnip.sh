#!/bin/bash -e

# Winlator Pulse Turnip Driver Builder
# Linux Glibc native build for Winlator container
# Based on lfdevs/mesa-for-android-container

green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

BUILD_VERSION=${BUILD_VERSION:-"latest"}
MESASRC=${MESASRC:-"https://gitlab.freedesktop.org/mesa/mesa"}
VARIANT=${VARIANT:-"standard"}  # standard / a8xx / perf

echo "====== Winlator Pulse Turnip Builder (Glibc) ======"
echo "Version: $BUILD_VERSION"
echo "Variant: $VARIANT"
echo "Source: $MESASRC"
echo ""

check_deps() {
    echo "Checking dependencies..."
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        git ccache ninja-build python3-pip pkg-config \
        libdrm-dev libxcb1-dev libxcb-dri3-dev libxcb-present-dev \
        libxcb-randr-dev libxcb-shm0-dev libx11-xcb-dev \
        flex bison glslang-tools zstd tar
    pip3 install --break-system-packages "meson>=1.4" mako
    echo -e "$green Dependencies installed $nocolor"
}

prepare_workdir() {
    echo ""
    echo "Preparing work directory..."
    workdir="$(pwd)/build"
    mkdir -p "$workdir" && cd "$workdir"
    
    echo "Downloading Mesa source..."
    git clone --depth=1 -b main "$MESASRC" mesa
    cd mesa
    
    echo "Mesa version: $(cat VERSION)"
}

apply_patches() {
    echo ""
    echo "Applying patches for variant: $VARIANT"
    
    if [ "$VARIANT" == "a8xx" ] || [ "$VARIANT" == "perf" ]; then
        echo "  A8XX variant - using upstream main (no extra patches needed for now)"
        # TODO: add tu8_kgsl patch for A8XX support
    fi
    
    if [ "$VARIANT" == "perf" ]; then
        echo "  Perf variant - applying performance tweaks"
        # TODO: add PWR_MAX patch
    fi
}

build_turnip() {
    echo ""
    echo "Building Turnip driver (Glibc native)..."
    
    export CCACHE_DIR="/root/.ccache"
    ccache --max-size=2G
    ccache --zero-stats
    
    GITHASH=$(git rev-parse --short HEAD)
    
    echo "Configuring meson..."
    meson setup build/ \
        --prefix=/usr \
        -Dplatforms=x11,wayland \
        -Dgallium-drivers= \
        -Dgallium-va=disabled \
        -Dgallium-mediafoundation=disabled \
        -Dvulkan-drivers=freedreno \
        -Dvulkan-layers= \
        -Dgles1=disabled \
        -Dgles2=disabled \
        -Dopengl=false \
        -Dgbm=disabled \
        -Dglx=disabled \
        -Dxlib-lease=disabled \
        -Dfreedreno-kmds=kgsl \
        -Degl=disabled \
        -Dglvnd=disabled \
        -Dintel-rt=disabled \
        -Dmicrosoft-clc=disabled \
        -Dllvm=disabled \
        -Dvalgrind=disabled \
        -Dbuild-tests=false \
        -Dlibunwind=disabled \
        -Dlmsensors=disabled \
        -Dandroid-libbacktrace=disabled \
        -Dbuildtype=release
    
    echo "Compiling..."
    ninja -C build/
    
    ccache --show-stats
    
    if [ ! -f "build/src/freedreno/vulkan/libvulkan_freedreno.so" ]; then
        echo -e "$red Build failed! $nocolor"
        exit 1
    fi
    
    echo -e "$green Build success! $nocolor"
    echo "  SO size: $(du -h build/src/freedreno/vulkan/libvulkan_freedreno.so | cut -f1)"
    
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
    
    # Install to temp dir
    DESTDIR=/tmp/mesa-install meson install -C build/
    
    # Copy the driver
    cp /tmp/mesa-install/usr/lib/libvulkan_freedreno.so "$PACKDIR/usr/lib/"
    
    # Create ICD json
    cat <<EOF >"$PACKDIR/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
{
    "ICD": {
        "api_version": "1.4.354",
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
    
    echo "$GITHASH" > /tmp/mesa_hash.txt
}

# Run
check_deps
prepare_workdir
apply_patches
build_turnip

echo ""
echo "====== Done! ======"
