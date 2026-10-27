#!/bin/bash
# Verify patches were applied correctly

echo "Verifying patches..."

cd build/mesa

# Check for NDK r29 fixes
if grep -q "typedef void\* buffer_handle_t" include/android_stub/cutils/native_handle.h; then
    echo "  [OK] NDK r29 buffer_handle_t fix"
else
    echo "  [WARN] NDK r29 buffer_handle_t fix not found"
fi

# Check for tu8_kgsl patch if a8xx/perf variant
if [ "$VARIANT" == "a8xx" ] || [ "$VARIANT" == "perf" ]; then
    if grep -q "tu8" src/freedreno/vulkan/tu_device.c 2>/dev/null; then
        echo "  [OK] A8XX tu8 patch"
    else
        echo "  [WARN] A8XX tu8 patch not found"
    fi
fi

# Check for perf patch
if [ "$VARIANT" == "perf" ]; then
    if grep -q "TU_PERF_PWR_MAX" src/freedreno/vulkan/tu_device.c 2>/dev/null; then
        echo "  [OK] Perf PWR_MAX patch"
    else
        echo "  [WARN] Perf PWR_MAX patch not found"
    fi
fi

echo ""
echo "Verification complete"
