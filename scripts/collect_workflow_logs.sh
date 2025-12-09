#!/bin/bash
# GitHub Actions Workflow 日志收集脚本入口 (macOS/Linux)
#
# 入口脚本：仅调用 Python 核心脚本

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 使用系统 Python 或虚拟环境 Python
if [ -f "$SCRIPT_DIR/../.venv/bin/python" ]; then
    PYTHON="$SCRIPT_DIR/../.venv/bin/python"
elif command -v python3 &> /dev/null; then
    PYTHON=python3
elif command -v python &> /dev/null; then
    PYTHON=python
else
    echo "错误: 未找到 Python 解释器" >&2
    exit 1
fi

# 执行 Python 脚本
exec "$PYTHON" "$SCRIPT_DIR/collect_workflow_logs.py" "$@"
