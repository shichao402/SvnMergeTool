#!/bin/bash
# SVN 合并助手 - 构建脚本入口 (macOS/Linux)
#
# 入口脚本：仅调用 Python 核心脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

exec "$PYTHON" "$SCRIPT_DIR/build.py" "$@"
