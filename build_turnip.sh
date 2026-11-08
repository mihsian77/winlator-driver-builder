#!/bin/bash -e

# Winlator Pulse Turnip Driver Builder
# Linux Glibc native build for Winlator container
# Based on lfdevs/mesa-for-android-container

green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

BUILD_VERSION=${BUILD_VERSION:-"latest"}
MESASRC=${MESASRC:-"https://github.com/brunodev85/mesa3d-custom"}
VARIANT=${VARIANT:-"standard"}  # standard / a8xx / perf

echo "====== Winlator Pulse Turnip Builder (Glibc) ======"
echo "Version: $BUILD_VERSION"
echo "Variant: $VARIANT"
echo "Source: $MESASRC"
echo ""

check_deps() {
    echo "Checking dependencies..."
    deps_missing=0
    for dep in git ninja meson python3 zstd tar pkg-config; do
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
    echo -e "$green Dependencies OK $nocolor"
}

prepare_workdir() {
    echo ""
    echo "Preparing work directory..."
    workdir="$(pwd)/build"
    mkdir -p "$workdir" && cd "$workdir"
    
    echo "Downloading Mesa source..."
    git clone --depth=1 "$MESASRC" mesa
    cd mesa
    
    # brunodev85/mesa3d-custom stores each driver version in a subdirectory.
    # Pick the newest turnip-* directory so the build follows the official source;
    # when upstream adds turnip-26.2.x-devel this keeps working without code changes.
    turnip_dir=$(ls -d turnip-*/ 2>/dev/null | sort -V | tail -1)
    if [ -n "$turnip_dir" ]; then
        echo "Using official Winlator source: $turnip_dir"
        cd "$turnip_dir"
    fi
    
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
    
    export CCACHE_DIR="$HOME/.ccache"
    ccache --max-size=2G
    ccache --zero-stats
    
    GITHASH=$(git rev-parse --short HEAD)
    
    echo "Configuring meson..."
    meson setup build/ \
        --prefix=/usr \
        -Dstrip=true \
        -Dcpp_rtti=false \
        -Dplatforms=x11 \
        -Dgallium-drivers= \
        -Dgallium-va=disabled \
        -Dvulkan-drivers=freedreno \
        -Dvulkan-layers= \
        -Dgles1=disabled \
        -Dgles2=disabled \
        -Dopengl=false \
        -Dgbm=disabled \
        -Dglx=disabled \
        -Dxlib-lease=disabled \
        -Dfreedreno-kmds=kgsl,msm \
        -Dxmlconfig=disabled \
        -Degl=disabled \
        -Dglvnd=disabled \
        -Dintel-rt=disabled \
        -Dmicrosoft-clc=disabled \
        -Dllvm=disabled \
        -Dshared-llvm=disabled \
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
    
    # Read Mesa version from source
    MESA_VERSION=$(cat VERSION | sed 's/-devel.*//' | tr -d '[:space:]' || echo "unknown")
    
    PACKDIR="/tmp/turnip-tzst"
    rm -rf "$PACKDIR"
    mkdir -p "$PACKDIR/usr/lib"
    mkdir -p "$PACKDIR/usr/share/vulkan/icd.d"
    
    # Install to temp dir
    DESTDIR=/tmp/mesa-install meson install -C build/
    
    # Copy the driver
    cp /tmp/mesa-install/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so "$PACKDIR/usr/lib/"

    # Ubuntu 的 libc.so 是个 linker script，里面写着 AS_NEEDED(ld-linux-aarch64.so.1)，
    # 一旦链接时 --no-as-needed 生效，动态链接器就会被打进 NEEDED。
    # 运行时 dlopen 一个把 ld.so 当普通库依赖的 .so 会直接失败，所以打包前剔掉。
    if command -v patchelf >/dev/null 2>&1; then
        patchelf --remove-needed ld-linux-aarch64.so.1 "$PACKDIR/usr/lib/libvulkan_freedreno.so" 2>/dev/null || true
    fi
    
    # Create ICD json
    cat <<EOF >"$PACKDIR/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
{
    "ICD": {
        "api_version": "1.4.354",
        "library_arch": "64",
        "library_path": "/data/data/com.winlator/files/rootfs/usr/lib/libvulkan_freedreno.so"
    },
    "file_format_version": "1.0.1"
}
EOF
    
    # 自编译产物统一带 -dev 标记，和官方版本区分开：
    # 公开的组件列表（index.txt）只列官方包，自编译的只留在 release 里供手动下载测试
    if [ "$VARIANT" == "standard" ]; then
        VARIANT_SUFFIX=""
    else
        VARIANT_SUFFIX="-${VARIANT}"
    fi
    OUTPUT_NAME="turnip-${MESA_VERSION}-dev${VARIANT_SUFFIX}.tzst"
    cd "$PACKDIR"
    tar --zstd -cf "/tmp/$OUTPUT_NAME" usr/
    
    echo -e "$green Packed: /tmp/$OUTPUT_NAME $nocolor"
    echo "  Size: $(du -h /tmp/$OUTPUT_NAME | cut -f1)"
    echo "  Mesa version: $MESA_VERSION"
    
    echo "$GITHASH" > /tmp/mesa_hash.txt
    echo "$MESA_VERSION" > /tmp/mesa_version.txt
}

# Run
check_deps
prepare_workdir
apply_patches
build_turnip

echo ""
echo "====== Done! ======"
