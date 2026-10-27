# Winlator Pulse Turnip Driver Builder

Turnip 驱动自动编译仓库。从 Mesa 上游源码编译，打包成 Winlator 可用的 .tzst 格式。

## 编译输出

- `turnip-<version>-git<hash>.tzst`
- 格式：tar.zst 压缩，包含 usr/lib/ 和 usr/share/vulkan/icd.d/
- 直接放到 Winlator 的 graphics_driver 目录即可

## 编译参数

基于 whitebelyash/AdrenoToolsDrivers 的 turnip_builder_upstream.sh：

- Android NDK r29
- Meson 编译
- -Dvulkan-drivers=freedreno
- -Dfreedreno-kmds=kgsl
- -Dvulkan-beta=true

## 补丁

默认加 tu8_kgsl.patch（支持 Adreno 8XX 新 GPU）。

## 使用

1. 手动触发 workflow_dispatch
2. 输入版本号、Mesa 源码地址、补丁地址
3. 编译完成后下载 artifact
4. 上传到 winlator-components 仓库的 turnip Release

## 参考

- [whitebelyash/AdrenoToolsDrivers](https://github.com/whitebelyash/AdrenoToolsDrivers) - 编译脚本参考
- [lfdevs/mesa-for-android-container](https://github.com/lfdevs/mesa-for-android-container) - Mesa Android 容器编译
- [whitebelyash/mesa-tu8](https://github.com/whitebelyash/mesa-tu8) - tu8_kgsl.patch 补丁来源
