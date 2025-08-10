#!/bin/bash
set -e

# 固件构建目录源路径
OPENWRT_DIR="$GITHUB_WORKSPACE/$BUILD_DIR"
# 第三方 feed 仓库目录源路径
CUSTOM_FEED_DIR="$OPENWRT_DIR/feeds/custom"

SEARCH_PATHS=(
    "$OPENWRT_DIR/package/network/utils"
    "$OPENWRT_DIR/feeds/packages/utils"
	"$OPENWRT_DIR/feeds/packages/net"
)

echo "========================================"
echo "第三方 feed 仓库软链接替换脚本"
echo "固件构建目录: $OPENWRT_DIR"
echo "搜索路径: ${SEARCH_PATHS[*]}"
echo "========================================"

# 检查关键目录是否存在
if [ ! -d "$CUSTOM_FEED_DIR" ]; then
    echo "错误: 自定义 feed 目录不存在: $CUSTOM_FEED_DIR"
    exit 1
fi

# 显示自定义 feed 内容
echo "自定义 feed 内容:"
ls -l "$CUSTOM_FEED_DIR"
echo "----------------------------------------"

total_count=0
replace_count=0
skip_count=0
not_found_count=0

echo "开始处理自定义 feed 中的包..."
echo "----------------------------------------"

# 遍历自定义 feed 中的每个包
for pkg in "$CUSTOM_FEED_DIR"/*; do
    [ -d "$pkg" ] || continue
    pkg_name=$(basename "$pkg")
    total_count=$((total_count + 1))
    
    echo "处理包 [$total_count]: $pkg_name"
    echo "源路径: $pkg"
    echo "包名: $pkg_name"

    # 在搜索路径中查找同名目录
    found_target=""
    for search_path in "${SEARCH_PATHS[@]}"; do
        # 跳过不存在的搜索路径
        if [ ! -d "$search_path" ]; then
            echo "  警告: 搜索路径不存在: $search_path"
            continue
        fi
        
        echo "  搜索路径: $search_path"
        
        # 尝试在搜索路径的直接子目录中查找
        if [ -d "$search_path/$pkg_name" ]; then
            candidate="$search_path/$pkg_name"
            echo "  找到直接匹配: $candidate"
            found_target="$candidate"
            break
        fi
        
        # 尝试在搜索路径的二级子目录中查找（如 utils/ 等）
        for subdir in "$search_path"/*; do
            if [ -d "$subdir" ] && [ -d "$subdir/$pkg_name" ]; then
                candidate="$subdir/$pkg_name"
                echo "  在子目录 $subdir 中找到匹配: $candidate"
                found_target="$candidate"
                break 2
            fi
        done
    done

    if [ -z "$found_target" ]; then
        echo "  未找到匹配的目录"
        not_found_count=$((not_found_count + 1))
        skip_count=$((skip_count + 1))
        echo "----------------------------------------"
        continue
    fi

    echo "  找到目标: $found_target"
    
    # 获取绝对路径用于比较
    pkg_abs=$(cd "$pkg" && pwd)
    target_abs=$(cd "$(dirname "$found_target")" && pwd)/$(basename "$found_target")
    
    # 检查目标类型
    if [ -L "$found_target" ]; then
        # 处理软链接
        link_target=$(readlink -f "$found_target")
        echo "  类型: 软链接"
        echo "  当前指向: $link_target"
        echo "  期望指向: $pkg_abs"
        
        if [ "$link_target" = "$pkg_abs" ]; then
            echo "  跳过: 已是正确软链接"
            skip_count=$((skip_count + 1))
        else
            echo "  删除错误链接"
            rm -f "$found_target"
            
            echo "  创建新链接: $pkg -> $found_target"
            ln -sf "$pkg" "$found_target"
            
            # 验证链接
            new_link=$(readlink -f "$found_target")
            if [ "$new_link" = "$pkg_abs" ]; then
                echo "  替换成功!"
                replace_count=$((replace_count + 1))
            else
                echo "  错误: 链接创建失败!"
                skip_count=$((skip_count + 1))
            fi
        fi
    elif [ -d "$found_target" ]; then
        # 处理普通目录
        echo "  类型: 普通目录"
        
        # 检查是否指向自定义 feed 自身
        target_real=$(cd "$found_target" && pwd)
        if [ "$target_real" = "$pkg_abs" ]; then
            echo "  跳过: 目标路径指向自定义 feed 自身"
            skip_count=$((skip_count + 1))
        else
            echo "  删除目录"
            rm -rf "$found_target"
            
            echo "  创建链接: $pkg -> $found_target"
            ln -sf "$pkg" "$found_target"
            
            # 验证链接
            new_link=$(readlink -f "$found_target")
            if [ "$new_link" = "$pkg_abs" ]; then
                echo "  替换成功!"
                replace_count=$((replace_count + 1))
            else
                echo "  错误: 链接创建失败!"
                skip_count=$((skip_count + 1))
            fi
        fi
    else
        echo "  警告: 目标既不是目录也不是链接"
        skip_count=$((skip_count + 1))
    fi
    
    echo "----------------------------------------"
done

echo "----------------------------------------"
echo "处理完成"
echo "总包数:       $total_count"
echo "替换成功:     $replace_count"
echo "跳过处理:         $skip_count"
echo "未找到目标:   $not_found_count"
echo "========================================"
