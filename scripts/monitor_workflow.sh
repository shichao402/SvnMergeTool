#!/bin/bash
# GitHub Actions 监控脚本 (macOS/Linux)
#
# 用于监控 GitHub Actions workflow 运行状态
# 功能：
# - 持续监控 workflow 状态
# - 每5秒查询一次状态
# - 成功时退出
# - 失败时获取错误日志
#
# 使用方法：
#   ./scripts/monitor_workflow.sh [run_id]
#
# 如果不提供 run_id，将从 .github_run_id.txt 文件读取

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 获取 run ID
RUN_ID="$1"
if [ -z "$RUN_ID" ]; then
    RUN_ID_FILE="$PROJECT_DIR/.github_run_id.txt"
    if [ -f "$RUN_ID_FILE" ]; then
        RUN_ID=$(cat "$RUN_ID_FILE" | tr -d '\n\r ')
    fi
fi

if [ -z "$RUN_ID" ]; then
    echo -e "${RED}错误：必须提供 run ID${NC}"
    echo ""
    echo "使用方法："
    echo "  $0 [run_id]"
    echo ""
    echo "如果不提供 run_id，将从 .github_run_id.txt 文件读取"
    exit 1
fi

# 创建日志目录
LOG_DIR="$PROJECT_DIR/workflow_logs"
mkdir -p "$LOG_DIR"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  监控 GitHub Actions Workflow${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "Run ID: $RUN_ID"
echo "日志目录: $LOG_DIR"
echo ""

# 获取 run 信息
echo "正在获取 run 信息..."
RUN_INFO=$(gh run view "$RUN_ID" --json status,conclusion,url,workflowName,headBranch,event,createdAt 2>/dev/null || echo "")

if [ -z "$RUN_INFO" ]; then
    echo -e "${RED}错误：无法获取 run 信息${NC}"
    echo "请检查 run ID 是否正确: $RUN_ID"
    exit 1
fi

WORKFLOW_NAME=$(echo "$RUN_INFO" | grep -o '"workflowName":"[^"]*"' | cut -d'"' -f4 || echo "Unknown")
HEAD_BRANCH=$(echo "$RUN_INFO" | grep -o '"headBranch":"[^"]*"' | cut -d'"' -f4 || echo "Unknown")
EVENT=$(echo "$RUN_INFO" | grep -o '"event":"[^"]*"' | cut -d'"' -f4 || echo "Unknown")
URL=$(echo "$RUN_INFO" | grep -o '"url":"[^"]*"' | cut -d'"' -f4 || echo "")

echo "Workflow: $WORKFLOW_NAME"
echo "分支: $HEAD_BRANCH"
echo "事件: $EVENT"
if [ -n "$URL" ]; then
    echo "URL: $URL"
fi
echo ""

# 监控循环
POLL_INTERVAL=5
MAX_ITERATIONS=0  # 0 表示无限循环
ITERATION=0

echo -e "${BLUE}开始监控 workflow 状态（每 ${POLL_INTERVAL} 秒查询一次）...${NC}"
echo "按 Ctrl+C 可以停止监控（不会取消 workflow）"
echo ""

while true; do
    ITERATION=$((ITERATION + 1))
    
    # 获取当前状态
    STATUS_INFO=$(gh run view "$RUN_ID" --json status,conclusion,updatedAt 2>/dev/null || echo "")
    
    if [ -z "$STATUS_INFO" ]; then
        echo -e "${YELLOW}[$ITERATION] 无法获取状态信息${NC}"
        sleep $POLL_INTERVAL
        continue
    fi
    
    STATUS=$(echo "$STATUS_INFO" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    CONCLUSION=$(echo "$STATUS_INFO" | grep -o '"conclusion":"[^"]*"' | cut -d'"' -f4 || echo "")
    UPDATED_AT=$(echo "$STATUS_INFO" | grep -o '"updatedAt":"[^"]*"' | cut -d'"' -f4 || echo "")
    
    # 显示状态
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    case "$STATUS" in
        "queued")
            echo -e "[$TIMESTAMP] ${YELLOW}[$ITERATION] 状态: 排队中...${NC}"
            ;;
        "in_progress")
            echo -e "[$TIMESTAMP] ${BLUE}[$ITERATION] 状态: 运行中...${NC}"
            ;;
        "completed")
            if [ "$CONCLUSION" == "success" ]; then
                echo -e "[$TIMESTAMP] ${GREEN}[$ITERATION] 状态: 完成 - 成功！${NC}"
                echo ""
                echo -e "${GREEN}========================================${NC}"
                echo -e "${GREEN}  Workflow 执行成功！${NC}"
                echo -e "${GREEN}========================================${NC}\n"
                exit 0
            else
                echo -e "[$TIMESTAMP] ${RED}[$ITERATION] 状态: 完成 - 失败！${NC}"
                echo ""
                echo -e "${RED}========================================${NC}"
                echo -e "${RED}  Workflow 执行失败！${NC}"
                echo -e "${RED}========================================${NC}\n"
                
                # 获取失败日志
                echo "正在获取错误日志..."
                LOG_FILE="$LOG_DIR/workflow_${RUN_ID}_error.log"
                
                # 获取所有失败的 jobs
                FAILED_JOBS=$(gh run view "$RUN_ID" --json jobs --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "cancelled") | .name' 2>/dev/null || echo "")
                
                if [ -n "$FAILED_JOBS" ]; then
                    echo "失败的 Jobs:" > "$LOG_FILE"
                    echo "$FAILED_JOBS" >> "$LOG_FILE"
                    echo "" >> "$LOG_FILE"
                    echo "========================================" >> "$LOG_FILE"
                    echo "" >> "$LOG_FILE"
                    
                    # 获取每个失败 job 的日志
                    while IFS= read -r JOB_NAME; do
                        if [ -n "$JOB_NAME" ]; then
                            echo "正在获取 Job '$JOB_NAME' 的日志..."
                            echo "" >> "$LOG_FILE"
                            echo "========================================" >> "$LOG_FILE"
                            echo "Job: $JOB_NAME" >> "$LOG_FILE"
                            echo "========================================" >> "$LOG_FILE"
                            echo "" >> "$LOG_FILE"
                            
                            # 获取 job 的日志
                            gh run view "$RUN_ID" --log-failed --job "$JOB_NAME" >> "$LOG_FILE" 2>&1 || echo "无法获取 Job '$JOB_NAME' 的日志" >> "$LOG_FILE"
                            echo "" >> "$LOG_FILE"
                        fi
                    done <<< "$FAILED_JOBS"
                else
                    # 如果没有找到失败的 jobs，尝试获取所有日志
                    echo "未找到失败的 Jobs，尝试获取完整日志..." >> "$LOG_FILE"
                    gh run view "$RUN_ID" --log >> "$LOG_FILE" 2>&1 || echo "无法获取完整日志" >> "$LOG_FILE"
                fi
                
                echo -e "${GREEN}✓ 错误日志已保存到: $LOG_FILE${NC}"
                echo ""
                
                # 显示简要错误信息
                echo "简要错误信息:"
                gh run view "$RUN_ID" --json jobs --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "cancelled") | "  - \(.name): \(.conclusion)"' 2>/dev/null || echo "  无法获取错误信息"
                
                exit 1
            fi
            ;;
        *)
            echo -e "[$TIMESTAMP] ${YELLOW}[$ITERATION] 状态: $STATUS${NC}"
            ;;
    esac
    
    # 等待下一次查询
    sleep $POLL_INTERVAL
done

