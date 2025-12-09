@echo off
REM SVN Auto Merge Tool - Commit Script Entry (Windows)
REM 
REM 入口脚本：仅调用 Python 核心脚本

setlocal

REM 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"

REM 使用虚拟环境的 Python 或系统 Python
if exist "%SCRIPT_DIR%..\.venv\Scripts\python.exe" (
    set "PYTHON=%SCRIPT_DIR%..\.venv\Scripts\python.exe"
) else if exist "%SCRIPT_DIR%..\.venv\Scripts\pythonw.exe" (
    set "PYTHON=%SCRIPT_DIR%..\.venv\Scripts\pythonw.exe"
) else (
    REM 尝试使用系统 Python
    where python >nul 2>&1
    if %errorlevel% equ 0 (
        set "PYTHON=python"
    ) else (
        echo 错误: 未找到 Python 解释器
        exit /b 1
    )
)

REM 执行 Python 脚本
"%PYTHON%" "%SCRIPT_DIR%commit.py" %*

endlocal
