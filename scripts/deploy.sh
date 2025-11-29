#!/bin/bash
# SVN 自动合并工具 - 部署脚本 (macOS/Linux)
# 
# 用于部署 Flutter 应用到目标平台
# 功能：
# - 检查 Flutter 环境
# - 构建应用
# - 安装到设备
# - 启动应用
#
# 注意：Windows 用户请使用 scripts/deploy.bat

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  SVN 自动合并工具 - 部署脚本${NC}"
echo -e "${GREEN}========================================${NC}\n"

# 切换到项目目录
cd "$PROJECT_DIR"

# 检查 Flutter 环境
echo "检查 Flutter 环境..."
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}错误：未找到 Flutter CLI${NC}"
    echo "请确保 Flutter 已安装并添加到 PATH"
    exit 1
fi

FLUTTER_VERSION=$(flutter --version | head -n 1)
echo -e "${GREEN}✓ Flutter 环境正常${NC}"
echo "  $FLUTTER_VERSION"

# 检查 Flutter 设备
echo -e "\n检查可用设备..."
DEVICES=$(flutter devices --machine 2>/dev/null | grep -c '"deviceId"' || echo "0")

if [ "$DEVICES" -eq "0" ]; then
    echo -e "${YELLOW}警告：未检测到可用设备${NC}"
    echo "请确保设备已连接或模拟器已启动"
    echo ""
    echo "可用选项："
    echo "  1. 连接物理设备"
    echo "  2. 启动模拟器/仿真器"
    echo "  3. 继续构建（不安装和运行）"
    read -p "是否继续构建？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    BUILD_ONLY=true
else
    echo -e "${GREEN}✓ 检测到 $DEVICES 个可用设备${NC}"
    BUILD_ONLY=false
fi

# 获取平台（macOS 或 Windows）
PLATFORM=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="linux"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    PLATFORM="windows"
else
    echo -e "${YELLOW}警告：无法检测平台类型，默认使用 macOS${NC}"
    PLATFORM="macos"
fi

echo -e "\n目标平台: $PLATFORM"

# 清理之前的构建
echo -e "\n清理之前的构建..."
flutter clean > /dev/null 2>&1 || true
echo -e "${GREEN}✓ 清理完成${NC}"

# 获取依赖
echo -e "\n获取依赖..."
flutter pub get
echo -e "${GREEN}✓ 依赖获取完成${NC}"

# 构建应用
echo -e "\n构建应用..."
if [ "$PLATFORM" == "macos" ]; then
    flutter build macos --debug
    echo -e "${GREEN}✓ 构建完成${NC}"
    
    # 复制配置文件到 App Bundle
    APP_BUNDLE="build/macos/Build/Products/Debug/SvnMergeTool.app"
    CONFIG_DIR="$APP_BUNDLE/Contents/Resources/config"
    if [ -f "$PROJECT_DIR/config/source_urls.json" ]; then
        mkdir -p "$CONFIG_DIR"
        cp "$PROJECT_DIR/config/source_urls.json" "$CONFIG_DIR/"
        echo -e "${GREEN}✓ 配置文件已复制到 App Bundle${NC}"
    fi
    
    echo ""
    echo "应用位置："
    echo "  $APP_BUNDLE"
    echo "配置文件位置："
    echo "  $CONFIG_DIR/source_urls.json"
elif [ "$PLATFORM" == "windows" ]; then
    flutter build windows --debug
    echo -e "${GREEN}✓ 构建完成${NC}"
    
    # 复制配置文件到构建输出目录
    CONFIG_DIR="build/windows/x64/runner/Debug/config"
    if [ -f "$PROJECT_DIR/config/source_urls.json" ]; then
        mkdir -p "$CONFIG_DIR"
        cp "$PROJECT_DIR/config/source_urls.json" "$CONFIG_DIR/"
        echo -e "${GREEN}✓ 配置文件已复制到构建输出${NC}"
    fi
    
    echo ""
    echo "应用位置："
    echo "  build/windows/x64/runner/Debug/SvnMergeTool.exe"
    echo "配置文件位置："
    echo "  $CONFIG_DIR/source_urls.json"
else
    flutter build linux --debug
    echo -e "${GREEN}✓ 构建完成${NC}"
    
    # 复制配置文件到构建输出目录
    CONFIG_DIR="build/linux/x64/debug/bundle/config"
    if [ -f "$PROJECT_DIR/config/source_urls.json" ]; then
        mkdir -p "$CONFIG_DIR"
        cp "$PROJECT_DIR/config/source_urls.json" "$CONFIG_DIR/"
        echo -e "${GREEN}✓ 配置文件已复制到构建输出${NC}"
    fi
    
    echo ""
    echo "配置文件位置："
    echo "  $CONFIG_DIR/source_urls.json"
fi

# 如果只构建，则退出
if [ "$BUILD_ONLY" == "true" ]; then
    echo -e "\n${GREEN}构建完成！${NC}"
    exit 0
fi

# 安装到设备
echo -e "\n安装到设备..."
flutter install
echo -e "${GREEN}✓ 安装完成${NC}"

# 启动应用
echo -e "\n启动应用..."
flutter run
echo -e "${GREEN}✓ 应用已启动${NC}"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  部署完成！${NC}"
echo -e "${GREEN}========================================${NC}\n"

