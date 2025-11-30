#!/bin/bash
# GitHub Actions 运行脚本 (macOS/Linux)
#
# 组合脚本：触发 workflow 并自动监控
# 功能：
# - 触发指定的 workflow
# - 自动监控 workflow 执行状态
# - 成功或失败时自动退出
#
# 使用方法：
#   ./scripts/run_workflow.sh <workflow_file> [--ref <ref>] [--input <key=value>]...

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 触发 workflow
echo "=========================================="
echo "  步骤 1: 触发 Workflow"
echo "=========================================="
echo ""

"$SCRIPT_DIR/trigger_workflow.sh" "$@"

if [ $? -ne 0 ]; then
    echo "触发 workflow 失败，退出"
    exit 1
fi

# 获取 run ID
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_ID_FILE="$PROJECT_DIR/.github_run_id.txt"

if [ ! -f "$RUN_ID_FILE" ]; then
    echo "错误：无法找到 run ID 文件"
    exit 1
fi

RUN_ID=$(cat "$RUN_ID_FILE" | tr -d '\n\r ')

if [ -z "$RUN_ID" ]; then
    echo "错误：无法获取 run ID"
    exit 1
fi

echo ""
echo "=========================================="
echo "  步骤 2: 监控 Workflow"
echo "=========================================="
echo ""

# 监控 workflow
"$SCRIPT_DIR/monitor_workflow.sh" "$RUN_ID"

exit $?

