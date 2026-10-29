#!/bin/bash
set -e

# Box64 编译脚本
# 编译 Linux ARM64 的 box64 二进制，打包成 tzst 格式

echo "=== Box64 Build Script ==="

# 版本号（用 git commit hash 作为版本）
BOX64_VERSION="${BUILD_VERSION:-$(date +%Y%m%d)}"
echo "Version: $BOX64_VERSION"

# 安装依赖
echo "=== Installing dependencies ==="
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    git cmake build-essential gcc-aarch64-linux-gnu \
    zstd tar

# 克隆 Box64 源码
echo "=== Cloning Box64 source ==="
git clone --depth 1 https://github.com/ptitSeb/box64.git /tmp/box64
cd /tmp/box64

# 获取最新 commit hash
BOX64_COMMIT=$(git rev-parse --short HEAD)
echo "Box64 commit: $BOX64_COMMIT"

# 创建 build 目录
echo "=== Building Box64 ==="
mkdir -p build
cd build

# 配置 CMake
cmake .. \
    -DARM_DYNAREC=ON \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr/local

# 编译
make -j$(nproc)

# 安装到临时目录
echo "=== Installing to temp dir ==="
mkdir -p /tmp/box64-install
make DESTDIR=/tmp/box64-install install

# 打包成 tzst 格式
echo "=== Packaging tzst ==="
cd /tmp/box64-install

# 创建包名
PACKAGE_NAME="box64-${BOX64_COMMIT}.tzst"
echo "Package: $PACKAGE_NAME"

# 打包
tar --use-compress-program='zstd -T0' -cf "/tmp/$PACKAGE_NAME" usr/

# 显示包信息
echo "=== Package info ==="
ls -lh "/tmp/$PACKAGE_NAME"
echo "Contents:"
tar -tf "/tmp/$PACKAGE_NAME" | head -20

echo "=== Build complete ==="
echo "Output: /tmp/$PACKAGE_NAME"
