#!/bin/bash
set -e

OPENWRT_DIR="$GITHUB_WORKSPACE/$BUILD_DIR"
CUSTOM_FEED_DIR="$OPENWRT_DIR/feeds/custom"

# 多个查找根目录，空格分隔
SEARCH_PATHS=(
    "$OPENWRT_DIR/package"
    "$OPENWRT_DIR/feeds/packages"
)

echo "[INFO] Linking same-name packages from custom to source tree"

for pkg in "$CUSTOM_FEED_DIR"/*; do
    [ -d "$pkg" ] || continue
    pkg_name=$(basename "$pkg")

    old_pkg_path=""
    for path in "${SEARCH_PATHS[@]}"; do
        old_pkg_path=$(find "$path" -type d -name "$pkg_name" | head -n 1)
        if [ -n "$old_pkg_path" ]; then
            break
        fi
    done

    if [ -n "$old_pkg_path" ]; then
        echo "[INFO] Replacing package $pkg_name at $old_pkg_path with symlink to $pkg"
        rm -rf "$old_pkg_path"
        ln -sf "$pkg" "$old_pkg_path"
    else
        echo "[INFO] No matching package for $pkg_name in source tree, skipping"
    fi
done
