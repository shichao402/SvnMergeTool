#!/bin/bash
# GitHub Actions Workflow 日志收集脚本 (macOS/Linux)
#
# 收集 GitHub Actions workflow 的详细日志
# 功能：
# - 收集 workflow run 的详细信息
# - 收集所有 jobs 的日志
# - 保存到统一的日志文件
#
# 使用方法：
#   ./scripts/collect_workflow_logs.sh [run_id]
#
# 如果不提供 run_id，将从 .github_run_id.txt 文件读取

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 确定 Python 解释器
if [ -f "$PROJECT_DIR/.venv/bin/python" ]; then
    PYTHON="$PROJECT_DIR/.venv/bin/python"
elif command -v python3 &> /dev/null; then
    PYTHON="python3"
elif command -v python &> /dev/null; then
    PYTHON="python"
else
    echo "错误: 未找到 Python 解释器"
    echo "请安装 Python 3 或创建虚拟环境: python -m venv .venv"
    exit 1
fi

# 使用 Python 运行核心脚本
exec "$PYTHON" "$SCRIPT_DIR/lib/workflow_manager.py" collect-logs "$@"




