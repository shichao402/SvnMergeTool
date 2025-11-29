@echo off
REM 版本号管理脚本 (Windows)
REM
REM 用于管理项目版本号
REM 功能：
REM - 获取版本号
REM - 设置版本号
REM - 递增版本号
REM - 同步版本号到项目配置文件

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."

REM 切换到项目目录
cd /d "%PROJECT_DIR%"

REM 检查 Python 环境
where python >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found
    echo Please ensure Python is installed and added to PATH
    exit /b 1
)

REM 检查 PyYAML
python -c "import yaml" 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] PyYAML library required
    echo Please run: pip install pyyaml
    exit /b 1
)

REM 执行 Python 版本管理工具
python "%SCRIPT_DIR%lib\version_manager.py" %*



