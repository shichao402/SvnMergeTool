#!/bin/bash
# GitHub Actions Workflow 触发和监控脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

WORKFLOW=$1
VERSION=$2

if [ -z "$WORKFLOW" ]; then
    echo -e "${RED}用法: $0 <build|release> [version]${NC}"
    exit 1
fi

# 检查 GitHub CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}错误: 未找到 GitHub CLI (gh)${NC}"
    echo "请安装: https://cli.github.com/"
    exit 1
fi

# 检查登录状态
if ! gh auth status &> /dev/null; then
    echo -e "${YELLOW}GitHub CLI 未登录，请先登录:${NC}"
    echo "运行: gh auth login"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  触发 GitHub Actions Workflow${NC}"
echo -e "${GREEN}========================================${NC}\n"

if [ "$WORKFLOW" == "build" ]; then
    echo -e "${GREEN}触发构建 workflow...${NC}"
    
    if [ -n "$VERSION" ]; then
        gh workflow run build.yml -f version="$VERSION"
    else
        gh workflow run build.yml
    fi
    
    echo -e "${GREEN}✓ 构建 workflow 已触发${NC}"
    
elif [ "$WORKFLOW" == "release" ]; then
    echo -e "${GREEN}触发发布 workflow...${NC}"
    
    if [ -n "$VERSION" ]; then
        gh workflow run release.yml -f version="$VERSION"
    else
        # 从 VERSION.yaml 读取版本号
        if [ -f "VERSION.yaml" ] && command -v python3 &> /dev/null; then
            VERSION=$(python3 scripts/lib/version_manager.py extract app 2>/dev/null | cut -d'+' -f1)
            if [ -n "$VERSION" ]; then
                echo -e "${YELLOW}从 VERSION.yaml 读取版本号: $VERSION${NC}"
                gh workflow run release.yml -f version="$VERSION"
            else
                gh workflow run release.yml
            fi
        else
            gh workflow run release.yml
        fi
    fi
    
    echo -e "${GREEN}✓ 发布 workflow 已触发${NC}"
else
    echo -e "${RED}错误: 未知的 workflow: $WORKFLOW${NC}"
    echo "支持: build, release"
    exit 1
fi

# 等待 workflow 启动
echo -e "\n${YELLOW}等待 workflow 启动...${NC}"
sleep 3

# 获取最新的运行
echo -e "\n${GREEN}获取 workflow 运行信息...${NC}"

if [ "$WORKFLOW" == "build" ]; then
    RUN=$(gh run list --workflow=build.yml --limit=1 --json databaseId,status,conclusion,url --jq '.[0]')
else
    RUN=$(gh run list --workflow=release.yml --limit=1 --json databaseId,status,conclusion,url --jq '.[0]')
fi

if [ -z "$RUN" ] || [ "$RUN" == "null" ]; then
    echo -e "${RED}无法获取 workflow 运行信息${NC}"
    exit 1
fi

RUN_ID=$(echo "$RUN" | jq -r '.databaseId')
STATUS=$(echo "$RUN" | jq -r '.status')
URL=$(echo "$RUN" | jq -r '.url')

echo -e "${GREEN}Workflow 运行 ID: $RUN_ID${NC}"
echo -e "${GREEN}状态: $STATUS${NC}"
echo -e "${GREEN}URL: $URL${NC}"

# 监控 workflow
echo -e "\n${YELLOW}监控 workflow 执行...${NC}"
echo -e "${YELLOW}按 Ctrl+C 停止监控${NC}\n"

while true; do
    if [ "$WORKFLOW" == "build" ]; then
        RUN_INFO=$(gh run view $RUN_ID --workflow=build.yml --json status,conclusion,url 2>/dev/null)
    else
        RUN_INFO=$(gh run view $RUN_ID --workflow=release.yml --json status,conclusion,url 2>/dev/null)
    fi
    
    if [ -z "$RUN_INFO" ]; then
        echo -e "${RED}无法获取运行信息${NC}"
        break
    fi
    
    STATUS=$(echo "$RUN_INFO" | jq -r '.status')
    CONCLUSION=$(echo "$RUN_INFO" | jq -r '.conclusion // "运行中"')
    URL=$(echo "$RUN_INFO" | jq -r '.url')
    
    echo -e "\r${YELLOW}状态: $STATUS | 结论: $CONCLUSION${NC}" | tr -d '\n'
    
    if [ "$STATUS" == "completed" ]; then
        echo ""
        if [ "$CONCLUSION" == "success" ]; then
            echo -e "\n${GREEN}✅ Workflow 执行成功!${NC}"
            echo -e "${GREEN}查看详情: $URL${NC}"
            exit 0
        else
            echo -e "\n${RED}❌ Workflow 执行失败: $CONCLUSION${NC}"
            echo -e "${RED}查看详情: $URL${NC}"
            exit 1
        fi
    fi
    
    sleep 10
done

