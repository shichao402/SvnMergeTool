#!/bin/bash
# 版本号管理脚本 (macOS/Linux)
#
# 用于管理项目版本号
# 功能：
# - 获取版本号
# - 设置版本号
# - 递增版本号
# - 同步版本号到项目配置文件

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 切换到项目目录
cd "$PROJECT_DIR"

# 检查 Python 环境
if ! command -v python3 &> /dev/null; then
    echo "错误: 未找到 Python 3"
    echo "请确保 Python 3 已安装并添加到 PATH"
    exit 1
fi

# 检查 PyYAML
if ! python3 -c "import yaml" 2>/dev/null; then
    echo "错误: 需要安装 PyYAML 库"
    echo "请运行: pip3 install pyyaml"
    exit 1
fi

# 执行 Python 版本管理工具
python3 "$SCRIPT_DIR/lib/version_manager.py" "$@"



