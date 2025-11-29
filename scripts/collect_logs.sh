#!/bin/bash
# SVN 自动合并工具 - 日志收集脚本 (macOS/Linux)
#
# 收集所有相关日志文件到统一目录
# 包括：
# - 应用日志文件（logs/app_*.log）
# - Flutter 输出日志
# - 配置文件
#
# 注意：Windows 用户请使用 scripts/collect_logs.bat

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 生成时间戳
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$PROJECT_DIR/logs/app_${TIMESTAMP}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  日志收集脚本${NC}"
echo -e "${GREEN}========================================${NC}\n"

# 创建日志目录
mkdir -p "$LOG_DIR"
echo -e "${GREEN}✓ 创建日志目录: $LOG_DIR${NC}"

# 收集应用日志文件
echo -e "\n收集应用日志文件..."
if [ -d "$PROJECT_DIR/logs" ]; then
    # 查找所有日志文件
    LOG_FILES=$(find "$PROJECT_DIR/logs" -name "app_*.log" -type f 2>/dev/null | head -20)
    
    if [ -n "$LOG_FILES" ]; then
        echo "$LOG_FILES" | while read -r log_file; do
            if [ -f "$log_file" ]; then
                cp "$log_file" "$LOG_DIR/" 2>/dev/null || true
                echo "  ✓ $(basename "$log_file")"
            fi
        done
    else
        echo -e "${YELLOW}  未找到应用日志文件${NC}"
    fi
else
    echo -e "${YELLOW}  日志目录不存在${NC}"
fi

# 收集配置文件
echo -e "\n收集配置文件..."
if [ -f "$PROJECT_DIR/assets/config/source_urls.json" ]; then
    cp "$PROJECT_DIR/assets/config/source_urls.json" "$LOG_DIR/config.json" 2>/dev/null || true
    echo "  ✓ config.json (来自 assets/config/)"
fi

if [ -f "$PROJECT_DIR/config/source_urls.json" ]; then
    cp "$PROJECT_DIR/config/source_urls.json" "$LOG_DIR/config_runtime.json" 2>/dev/null || true
    echo "  ✓ config_runtime.json (来自 config/)"
fi

# 收集系统信息
echo -e "\n收集系统信息..."
{
    echo "=== 系统信息 ==="
    echo "时间: $(date)"
    echo "操作系统: $(uname -a)"
    echo ""
    echo "=== Flutter 信息 ==="
    flutter --version 2>/dev/null || echo "Flutter 未安装或不在 PATH"
    echo ""
    echo "=== Dart 信息 ==="
    dart --version 2>/dev/null || echo "Dart 未安装或不在 PATH"
} > "$LOG_DIR/system_info.txt"
echo "  ✓ system_info.txt"

# 生成日志摘要
echo -e "\n生成日志摘要..."
{
    echo "=== 日志收集摘要 ==="
    echo "收集时间: $(date)"
    echo "日志目录: $LOG_DIR"
    echo ""
    echo "=== 收集的文件 ==="
    ls -lh "$LOG_DIR" | tail -n +2 | awk '{print $9, "(" $5 ")"}'
    echo ""
    echo "=== 日志文件统计 ==="
    LOG_COUNT=$(find "$LOG_DIR" -name "*.log" -type f | wc -l)
    echo "日志文件数量: $LOG_COUNT"
    TOTAL_SIZE=$(du -sh "$LOG_DIR" | cut -f1)
    echo "总大小: $TOTAL_SIZE"
} > "$LOG_DIR/SUMMARY.txt"
echo "  ✓ SUMMARY.txt"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  日志收集完成！${NC}"
echo -e "${GREEN}========================================${NC}\n"
echo "日志目录: $LOG_DIR"
echo ""
echo "查看日志："
echo "  cat $LOG_DIR/SUMMARY.txt"
echo "  tail -f $LOG_DIR/app_*.log"

