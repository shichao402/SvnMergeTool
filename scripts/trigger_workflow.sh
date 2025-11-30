#!/bin/bash
# GitHub Actions 触发脚本 (macOS/Linux)
#
# 用于触发 GitHub Actions workflow 并获取 run ID
# 功能：
# - 触发指定的 workflow
# - 传递输入参数
# - 获取并保存 run ID
#
# 使用方法：
#   ./scripts/trigger_workflow.sh <workflow_file> [--ref <ref>] [--input <key=value>]...
#
# 示例：
#   ./scripts/trigger_workflow.sh .github/workflows/build.yml --ref main --input version=1.0.7

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 切换到项目目录
cd "$PROJECT_DIR"

# 检查 GitHub CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}错误：未找到 GitHub CLI (gh)${NC}"
    echo "请安装 GitHub CLI: https://cli.github.com/"
    exit 1
fi

# 检查是否已登录
if ! gh auth status &> /dev/null; then
    echo -e "${RED}错误：GitHub CLI 未登录${NC}"
    echo "请运行: gh auth login"
    exit 1
fi

# 解析参数
WORKFLOW_FILE=""
REF=""
INPUTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --ref)
            REF="$2"
            shift 2
            ;;
        --input)
            INPUTS+=("--input" "$2")
            shift 2
            ;;
        *)
            if [ -z "$WORKFLOW_FILE" ]; then
                WORKFLOW_FILE="$1"
            else
                echo -e "${RED}错误：未知参数: $1${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查必需参数
if [ -z "$WORKFLOW_FILE" ]; then
    echo -e "${RED}错误：必须指定 workflow 文件${NC}"
    echo ""
    echo "使用方法："
    echo "  $0 <workflow_file> [--ref <ref>] [--input <key=value>]..."
    echo ""
    echo "示例："
    echo "  $0 .github/workflows/build.yml --ref main --input version=1.0.7"
    exit 1
fi

# 检查 workflow 文件是否存在
if [ ! -f "$WORKFLOW_FILE" ]; then
    echo -e "${RED}错误：workflow 文件不存在: $WORKFLOW_FILE${NC}"
    exit 1
fi

# 获取仓库信息
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ -z "$REPO" ]; then
    echo -e "${RED}错误：无法获取仓库信息${NC}"
    echo "请确保当前目录是一个 Git 仓库，并且已配置 GitHub remote"
    exit 1
fi

# 获取 workflow ID（从文件名提取）
WORKFLOW_ID=$(basename "$WORKFLOW_FILE" .yml)
WORKFLOW_ID=$(basename "$WORKFLOW_ID" .yaml)

# 如果没有指定 ref，使用当前分支
if [ -z "$REF" ]; then
    REF=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  触发 GitHub Actions Workflow${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "仓库: $REPO"
echo "Workflow: $WORKFLOW_FILE"
echo "Workflow ID: $WORKFLOW_ID"
echo "Ref: $REF"
if [ ${#INPUTS[@]} -gt 0 ]; then
    echo "输入参数:"
    for ((i=1; i<${#INPUTS[@]}; i+=2)); do
        echo "  ${INPUTS[$i]}"
    done
fi
echo ""

# 构建 gh workflow run 命令
CMD="gh workflow run \"$WORKFLOW_ID\" --ref \"$REF\""
for input in "${INPUTS[@]}"; do
    CMD="$CMD $input"
done

# 触发 workflow
echo "正在触发 workflow..."
if eval "$CMD"; then
    echo -e "${GREEN}✓ Workflow 已触发${NC}"
else
    echo -e "${RED}错误：触发 workflow 失败${NC}"
    exit 1
fi

# 等待几秒让 workflow 启动
echo "等待 workflow 启动..."
sleep 3

# 获取最新的 run ID
echo "正在获取 run ID..."
MAX_ATTEMPTS=10
ATTEMPT=0
RUN_ID=""

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    RUN_ID=$(gh run list --workflow="$WORKFLOW_ID" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")
    
    if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ]; then
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo "  尝试 $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 2
done

if [ -z "$RUN_ID" ] || [ "$RUN_ID" == "null" ]; then
    echo -e "${YELLOW}警告：无法获取 run ID${NC}"
    echo "请手动查看 GitHub Actions 页面获取 run ID"
    exit 1
fi

# 保存 run ID 到文件
RUN_ID_FILE="$PROJECT_DIR/.github_run_id.txt"
echo "$RUN_ID" > "$RUN_ID_FILE"
echo -e "${GREEN}✓ Run ID 已保存: $RUN_ID${NC}"
echo "Run ID 文件: $RUN_ID_FILE"

# 显示 run 信息
echo ""
echo "Run 信息:"
gh run view "$RUN_ID" --json status,conclusion,url -q '"状态: \(.status)\n结论: \(.conclusion // "运行中")\nURL: \(.url)"' 2>/dev/null || echo "  无法获取 run 信息"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  触发完成！${NC}"
echo -e "${GREEN}========================================${NC}\n"
echo "使用以下命令监控 workflow:"
echo "  ./scripts/monitor_workflow.sh $RUN_ID"
echo ""

