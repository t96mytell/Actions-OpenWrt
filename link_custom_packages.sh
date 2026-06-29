#!/bin/bash
set -e

# 固件构建目录源路径 - 使用实际工作目录
OPENWRT_DIR="/workdir/$BUILD_DIR"
# 第三方 feed 仓库目录源路径
CUSTOM_FEED_DIR="$OPENWRT_DIR/feeds/custom"
# 备份目录
BACKUP_DIR="$OPENWRT_DIR/backup"
# 日志文件
LOG_FILE="$OPENWRT_DIR/replace_package.log"
# 备份保留时间（单位：秒），默认24小时（86400秒）
BACKUP_RETENTION_TIME=86400
# 恢复模式：none/all/select
RESTORE_MODE="${RESTORE_MODE:-none}"
# 指定要恢复的包列表（逗号分隔，如："pkg1,pkg2,pkg3"）
RESTORE_PACKAGES="${RESTORE_PACKAGES:-}"

SEARCH_PATHS=(
    "$OPENWRT_DIR/feeds/luci/applications"
    "$OPENWRT_DIR/package/network/utils"
    "$OPENWRT_DIR/feeds/packages/utils"
    "$OPENWRT_DIR/feeds/packages/net"
)

echo "========================================"
echo "第三方 feed 仓库软链接替换脚本"
echo "固件构建目录: $OPENWRT_DIR"
echo "搜索路径: ${SEARCH_PATHS[*]}"
echo "恢复模式: $RESTORE_MODE"
if [ -n "$RESTORE_PACKAGES" ]; then
    echo "指定恢复包: $RESTORE_PACKAGES"
fi
echo "========================================"

# 检查第三方 feed 仓库目录是否存在
if [ ! -d "$CUSTOM_FEED_DIR" ]; then
    echo "错误: 自定义 feed 目录不存在: $CUSTOM_FEED_DIR"
    exit 1
fi

echo "自定义 feed 内容:"
ls -l "$CUSTOM_FEED_DIR"
echo "----------------------------------------"

# 创建备份目录（如果不存在）
mkdir -p "$BACKUP_DIR"
# 创建日志文件（如果不存在）
touch "$LOG_FILE"

# 处理恢复包列表
declare -A restore_packages_map
if [ "$RESTORE_MODE" = "select" ] && [ -n "$RESTORE_PACKAGES" ]; then
    IFS=',' read -ra pkg_array <<< "$RESTORE_PACKAGES"
    for pkg in "${pkg_array[@]}"; do
        restore_packages_map[$(echo "$pkg" | xargs)]="true"
    done
fi

total_count=0
replace_count=0
skip_count=0
not_found_count=0
restore_count=0

echo "开始处理自定义 feed 中的包..."
echo "----------------------------------------"

# 函数：判断是否需要恢复该包的备份
should_restore_package() {
    local pkg_name="$1"
    
    case "$RESTORE_MODE" in
        none)
            return 1
            ;;
        all)
            return 0
            ;;
        select)
            if [ "${restore_packages_map[$pkg_name]}" = "true" ]; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# 函数：恢复最新的备份版本
restore_latest_backup() {
    local pkg_name="$1"
    local found_target="$2"
    
    # 查找该包的所有备份，按时间排序
    local backups=($(ls -d "$BACKUP_DIR/$pkg_name"-* 2>/dev/null | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo "  警告: 未找到该包的备份"
        return 1
    fi
    
    local latest_backup="${backups[0]}"
    echo "  恢复最新备份: $(basename "$latest_backup")"
    
    # 删除当前目录/链接
    rm -rf "$found_target"
    
    # 恢复备份
    cp -r "$latest_backup" "$found_target"
    echo "$(date) 恢复包 $pkg_name 从备份 $(basename "$latest_backup")" >> "$LOG_FILE"
    echo "  ✓ 恢复备份成功!"
    return 0
}

# 遍历自定义 feed 中的每个包
for pkg in "$CUSTOM_FEED_DIR"/*; do
    [ -d "$pkg" ] || continue
    pkg_name=$(basename "$pkg")
    total_count=$((total_count + 1))

    echo "处理包 [$total_count]: $pkg_name"
    echo "源路径: $pkg"

    # 在搜索路径中查找同名目录
    found_target=""
    for search_path in "${SEARCH_PATHS[@]}"; do
        if [ ! -d "$search_path" ]; then
            continue
        fi

        if [ -d "$search_path/$pkg_name" ]; then
            found_target="$search_path/$pkg_name"
            break
        fi

        for subdir in "$search_path"/*; do
            if [ -d "$subdir" ] && [ -d "$subdir/$pkg_name" ]; then
                found_target="$subdir/$pkg_name"
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
    pkg_real=$(realpath "$pkg")
    target_real=$(realpath "$found_target" 2>/dev/null || echo "")

    # 创建备份
    timestamp=$(date +%Y%m%d%H%M%S)
    backup_dir="$BACKUP_DIR/$pkg_name-$timestamp"
    
    echo "  创建备份: $backup_dir"
    cp -r "$found_target" "$backup_dir"
    echo "$(date) 备份包 $pkg_name 至 $backup_dir" >> "$LOG_FILE"

    # 检查是否需要恢复备份
    if should_restore_package "$pkg_name"; then
        if restore_latest_backup "$pkg_name" "$found_target"; then
            restore_count=$((restore_count + 1))
            echo "----------------------------------------"
            continue
        fi
    fi

    # 替换操作
    if [ -L "$found_target" ]; then
        # 处理软链接
        link_target=$(realpath "$found_target" 2>/dev/null || echo "")
        echo "  类型: 软链接"
        echo "  当前指向: $link_target"
        echo "  期望指向: $pkg_real"

        if [ "$link_target" = "$pkg_real" ]; then
            echo "  ✓ 跳过: 已是正确软链接"
            skip_count=$((skip_count + 1))
        else
            echo "  删除错误链接"
            rm -f "$found_target"
            echo "  创建新链接"
            ln -sf "$pkg" "$found_target"
            new_link=$(realpath "$found_target" 2>/dev/null || echo "")
            if [ "$new_link" = "$pkg_real" ]; then
                echo "  ✓ 替换成功"
                replace_count=$((replace_count + 1))
            else
                echo "  ✗ 错误: 链接创建失败"
                skip_count=$((skip_count + 1))
            fi
        fi
    elif [ -d "$found_target" ]; then
        # 处理普通目录
        echo "  类型: 普通目录"

        if [ "$target_real" = "$pkg_real" ]; then
            echo "  ✓ 跳过: 目标指向自定义 feed 自身"
            skip_count=$((skip_count + 1))
        else
            echo "  删除目录"
            rm -rf "$found_target"
            echo "  创建新链接"
            ln -sf "$pkg" "$found_target"
            new_link=$(realpath "$found_target" 2>/dev/null || echo "")
            if [ "$new_link" = "$pkg_real" ]; then
                echo "  ✓ 替换成功"
                replace_count=$((replace_count + 1))
            else
                echo "  ✗ 错误: 链接创建失败"
                skip_count=$((skip_count + 1))
            fi
        fi
    else
        echo "  ✗ 警告: 目标既不是目录也不是链接"
        skip_count=$((skip_count + 1))
    fi

    echo "----------------------------------------"
done

# 自动清理过期备份
echo "清理过期备份..."
backup_cleanup_count=0
current_time=$(date +%s)

# 第一步：按包名分组备份
declare -A pkg_backups_map
for backup_path in "$BACKUP_DIR"/*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]; do
    [ -d "$backup_path" ] || continue
    
    backup_name=$(basename "$backup_path")
    # 提取包名（去掉末尾的-时间戳部分）
    pkg_name="${backup_name%-[0-9]*}"
    
    if [ -z "${pkg_backups_map[$pkg_name]}" ]; then
        pkg_backups_map[$pkg_name]="$backup_path"
    else
        pkg_backups_map[$pkg_name]="${pkg_backups_map[$pkg_name]}|$backup_path"
    fi
done

# 第二步：对每个包的备份进行清理
for pkg_name in "${!pkg_backups_map[@]}"; do
    IFS='|' read -ra backups_array <<< "${pkg_backups_map[$pkg_name]}"
    
    # 按备份路径排序（因为时间戳在末尾，字典序 = 时间序）
    IFS=$'\n' sorted_backups=($(printf '%s\n' "${backups_array[@]}" | sort -r))
    unset IFS
    
    echo "  包 [$pkg_name] 有 ${#sorted_backups[@]} 个备份"
    
    # 第三步：遍历备份，保留最新的，清理过期的
    for i in "${!sorted_backups[@]}"; do
        backup_path="${sorted_backups[$i]}"
        backup_name=$(basename "$backup_path")
        
        # 获取备份时间戳（文件名末尾14位数字）
        backup_timestamp="${backup_name: -14}"
        
        # 计算备份年龄
        backup_age=$((current_time - backup_timestamp))
        
        if [ $i -eq 0 ]; then
            # 第一个（最新的）备份总是保留，即使超出时间限制
            if [ $backup_age -gt $BACKUP_RETENTION_TIME ]; then
                echo "    ✓ 保留最新备份（超期但保留）: $backup_name (${backup_age}秒前)"
            else
                echo "    ✓ 保留最新备份: $backup_name (${backup_age}秒前)"
            fi
        else
            # 非最新备份：只有超出时间限制才删除
            if [ $backup_age -gt $BACKUP_RETENTION_TIME ]; then
                rm -rf "$backup_path"
                echo "    ✗ 删除过期备份: $backup_name (${backup_age}秒前)"
                echo "$(date) 删除过期备份: $backup_path (年龄: ${backup_age}秒)" >> "$LOG_FILE"
                backup_cleanup_count=$((backup_cleanup_count + 1))
            else
                echo "    ✓ 保留备份（在保留期内）: $backup_name (${backup_age}秒前)"
            fi
        fi
    done
done

echo "清理完成 (删除备份数: $backup_cleanup_count)"

echo "----------------------------------------"
echo "处理完成"
echo "总包数:       $total_count"
echo "替换成功:     $replace_count"
echo "恢复成功:     $restore_count"
echo "跳过处理:     $skip_count"
echo "未找到目标:   $not_found_count"
echo "========================================"
