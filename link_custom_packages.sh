#!/bin/bash
set -e

# 固件构建目录源路径
OPENWRT_DIR="$GITHUB_WORKSPACE/$BUILD_DIR"
# 第三方 feed 仓库目录源路径
CUSTOM_FEED_DIR="$OPENWRT_DIR/feeds/custom"

# 遍历查找目标目录，按优先级排列
SEARCH_PATHS=(
    "$OPENWRT_DIR/package"
    "$OPENWRT_DIR/feeds/packages"
)

echo "开始遍历列表匹配并使用软链替换掉目标目录的同名包"

total_count=0
replace_count=0
skip_count=0

for pkg in "$CUSTOM_FEED_DIR"/*; do
    [ -d "$pkg" ] || continue
    pkg_name=$(basename "$pkg")
    total_count=$((total_count+1))

    old_pkg_path=""
    for path in "${SEARCH_PATHS[@]}"; do
        old_pkg_path=$(find "$path" -type d -name "$pkg_name" | head -n 1)
        if [ -n "$old_pkg_path" ]; then
            break
        fi
    done

    if [ -n "$old_pkg_path" ]; then
        # 判断是否已是正确软链
        if [ -L "$old_pkg_path" ] && [ "$(readlink -f "$old_pkg_path")" = "$(readlink -f "$pkg")" ]; then
            echo "跳过 $pkg_name - 目标目录已是正确软链"
            skip_count=$((skip_count+1))
            continue
        fi

        rm -rf "$old_pkg_path"
        ln -sf "$pkg" "$old_pkg_path"

        src_rel=$(realpath --relative-to="$OPENWRT_DIR" "$pkg")
        dst_rel=$(realpath --relative-to="$OPENWRT_DIR" "$old_pkg_path")
        echo "$src_rel → $dst_rel"
        echo "  → 替换成功!"
        replace_count=$((replace_count+1))
    else
        echo "跳过 $pkg_name - 目标目录中未匹配到该包"
        skip_count=$((skip_count+1))
    fi
done

echo "----------------------------------------"
echo "共检查 $total_count 个包"
echo "替换 $replace_count 个包"
echo "跳过 $skip_count 个包"
echo "----------------------------------------"
