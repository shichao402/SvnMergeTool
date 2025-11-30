#!/bin/bash
# SVN 自动合并工具 - 全量提交脚本 (macOS/Linux)
# 
# 用于全量提交本地所有可提交文件并推送到远程仓库
# 功能：
# - 添加所有更改的文件
# - 创建提交（使用环境变量 COMMIT_MESSAGE 或默认消息）
# - 推送到远程仓库
#
# 注意：Windows 用户请使用 scripts/commit.bat
#
# 使用方法：
#   ./scripts/commit.sh                    # 使用默认提交消息
#   COMMIT_MESSAGE="修复bug" ./scripts/commit.sh  # 使用自定义提交消息

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  SVN 自动合并工具 - 全量提交脚本${NC}"
echo -e "${GREEN}========================================${NC}\n"

# 切换到项目目录
cd "$PROJECT_DIR"

# 检查 Git 环境
echo "检查 Git 环境..."
if ! command -v git &> /dev/null; then
    echo -e "${RED}错误：未找到 Git CLI${NC}"
    echo "请确保 Git 已安装并添加到 PATH"
    exit 1
fi

GIT_VERSION=$(git --version)
echo -e "${GREEN}✓ Git 环境正常${NC}"
echo "  $GIT_VERSION"

# 检查是否在 Git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}错误：当前目录不是 Git 仓库${NC}"
    exit 1
fi

# 检查是否有更改的文件
echo -e "\n检查更改的文件..."
git add -A
CHANGED_FILES=$(git diff --cached --name-only)

if [ -z "$CHANGED_FILES" ]; then
    echo -e "${YELLOW}警告：没有可提交的文件${NC}"
    echo "工作目录是干净的，无需提交"
    exit 0
fi

echo -e "${GREEN}✓ 检测到以下文件将被提交：${NC}"
echo "$CHANGED_FILES" | while read -r file; do
    echo "  - $file"
done

# 生成提交消息
if [ -n "$COMMIT_MESSAGE" ]; then
    MESSAGE="$COMMIT_MESSAGE"
    echo -e "\n使用自定义提交消息：${BLUE}$MESSAGE${NC}"
else
    # 生成默认提交消息（包含时间戳）
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    MESSAGE="Auto commit: $TIMESTAMP"
    echo -e "\n使用默认提交消息：${BLUE}$MESSAGE${NC}"
fi

# 创建提交
echo -e "\n创建提交..."
if git commit -m "$MESSAGE" --no-verify; then
    echo -e "${GREEN}✓ 提交创建成功${NC}"
else
    echo -e "${RED}错误：提交创建失败${NC}"
    exit 1
fi

# 获取当前分支
CURRENT_BRANCH=$(git branch --show-current)
echo -e "\n当前分支: ${BLUE}$CURRENT_BRANCH${NC}"

# 检查远程仓库
echo -e "\n检查远程仓库..."
REMOTE=$(git remote | head -n 1)
if [ -z "$REMOTE" ]; then
    echo -e "${YELLOW}警告：未配置远程仓库${NC}"
    echo "跳过推送操作"
    exit 0
fi

REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null || echo "未配置")
echo -e "${GREEN}✓ 远程仓库: ${BLUE}$REMOTE${NC} ($REMOTE_URL)"

# 推送到远程仓库
echo -e "\n推送到远程仓库..."
if git push "$REMOTE" "$CURRENT_BRANCH"; then
    echo -e "${GREEN}✓ 推送成功${NC}"
else
    echo -e "${RED}错误：推送失败${NC}"
    echo "请检查网络连接和远程仓库权限"
    exit 1
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  提交并推送完成！${NC}"
echo -e "${GREEN}========================================${NC}\n"





