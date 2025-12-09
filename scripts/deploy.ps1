# SVN Auto Merge Tool - Deploy Script Entry (PowerShell)
# 
# 入口脚本：仅调用 Python 核心脚本

$ErrorActionPreference = "Stop"

# 获取脚本所在目录
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# 使用虚拟环境的 Python 或系统 Python
if (Test-Path "$SCRIPT_DIR\..\.venv\Scripts\python.exe") {
    $PYTHON = "$SCRIPT_DIR\..\.venv\Scripts\python.exe"
} elseif (Test-Path "$SCRIPT_DIR\..\.venv\Scripts\pythonw.exe") {
    $PYTHON = "$SCRIPT_DIR\..\.venv\Scripts\pythonw.exe"
} else {
    # 尝试使用系统 Python
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $PYTHON = "python"
    } else {
        Write-Host "错误: 未找到 Python 解释器" -ForegroundColor Red
        exit 1
    }
}

# 执行 Python 脚本
& $PYTHON "$SCRIPT_DIR\deploy.py" $args
