#!/usr/bin/env python3
"""
Apply PWR_MAX performance patch to Mesa Turnip.
Idempotent: can be run multiple times safely.
"""

import re
import sys
from pathlib import Path

# Find the tu_device.c file
TU_DEVICE = Path("src/freedreno/vulkan/tu_device.c")

if not TU_DEVICE.exists():
    print("tu_device.c not found, skipping perf patch")
    sys.exit(0)

content = TU_DEVICE.read_text()

# Check if already applied
if "TU_PERF_PWR_MAX" in content:
    print("Perf patch already applied, skipping")
    sys.exit(0)

# Find the anchor point
anchor = "static void"
pattern = re.compile(r'(static\s+void\s+tu_device_init)\s*\(')

match = pattern.search(content)
if not match:
    print("Anchor not found, upstream may have absorbed this patch")
    sys.exit(0)

# Apply the patch
patch_code = """
/* TU_PERF_PWR_MAX: Force max GPU frequency for performance */
#include <sys/ioctl.h>
#include <linux/kgsl.h>
"""

# Insert after the includes section
include_end = content.find("static void tu_device_init")
if include_end == -1:
    print("Could not find insertion point")
    sys.exit(1)

new_content = content[:include_end] + patch_code + "\n" + content[include_end:]

TU_DEVICE.write_text(new_content)
print("Perf patch applied successfully")
