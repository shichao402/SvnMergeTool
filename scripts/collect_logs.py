#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN 自动合并工具 - 日志收集脚本（跨平台 Python 实现）

收集所有相关日志文件到统一目录
包括：
- 应用日志文件（logs/app_*.log）
- Flutter 输出日志
- 配置文件
- 系统信息

路径处理规则：
- 必须使用 pathlib.Path 处理所有路径
- 严禁手动拼装路径分隔符（/ 或 \）
- 严禁手动处理盘符或绝对路径前缀
- 使用 Path.joinpath() 或 / 操作符拼接路径
"""

import sys
import subprocess
import shutil
import os
from pathlib import Path
from datetime import datetime
from typing import List, Optional


def get_project_root() -> Path:
    """获取项目根目录"""
    # 获取脚本所在目录
    script_dir = Path(__file__).parent.resolve()
    # 项目根目录是脚本目录的父目录
    project_root = script_dir.parent
    return project_root


def create_log_directory(project_root: Path) -> Path:
    """创建日志收集目录"""
    # 使用 pathlib 拼接路径
    logs_dir = project_root / "logs"
    logs_dir.mkdir(exist_ok=True)
    
    # 生成时间戳
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_dir = logs_dir / f"app_{timestamp}"
    log_dir.mkdir(exist_ok=True)
    
    return log_dir


def get_app_support_log_dir() -> Optional[Path]:
    """获取应用支持目录中的日志目录（打包环境）
    
    Flutter 的 getApplicationSupportDirectory() 返回的路径：
    - Windows: %APPDATA%/com.example.SvnMergeTool/
    - macOS: ~/Library/Application Support/com.example.SvnMergeTool/
    - Linux: ~/.local/share/com.example.SvnMergeTool/
    
    日志存放在该目录下的 logs/ 子目录
    """
    try:
        if sys.platform == 'win32':
            # Windows: %APPDATA%/com.example.SvnMergeTool/logs
            appdata = os.getenv('APPDATA')
            if appdata:
                app_support_dir = Path(appdata) / 'com.example.SvnMergeTool' / 'logs'
                if app_support_dir.exists():
                    return app_support_dir
        elif sys.platform == 'darwin':
            # macOS: ~/Library/Application Support/com.example.SvnMergeTool/logs
            home = os.path.expanduser('~')
            app_support_dir = Path(home) / 'Library' / 'Application Support' / 'com.example.SvnMergeTool' / 'logs'
            if app_support_dir.exists():
                return app_support_dir
        elif sys.platform.startswith('linux'):
            # Linux: ~/.local/share/com.example.SvnMergeTool/logs
            home = os.path.expanduser('~')
            app_support_dir = Path(home) / '.local' / 'share' / 'com.example.SvnMergeTool' / 'logs'
            if app_support_dir.exists():
                return app_support_dir
    except Exception:
        pass
    return None


def collect_log_files(project_root: Path, log_dir: Path) -> int:
    """收集应用日志文件（从所有可能的位置）"""
    print("\n收集应用日志文件...")
    
    all_log_files = []
    checked_paths = []
    
    # 1. 收集项目目录中的日志文件（开发环境）
    project_logs_dir = project_root / "logs"
    checked_paths.append(("项目根目录", project_logs_dir))
    if project_logs_dir.exists():
        project_log_files = list(project_logs_dir.glob("app_*.log"))
        if project_log_files:
            print(f"  [找到] 项目目录: {len(project_log_files)} 个日志文件")
            all_log_files.extend(project_log_files)
    
    # 2. 收集应用支持目录中的日志文件（打包环境）
    app_support_log_dir = get_app_support_log_dir()
    if app_support_log_dir:
        checked_paths.append(("应用支持目录", app_support_log_dir))
        if app_support_log_dir.exists():
            app_support_log_files = list(app_support_log_dir.glob("app_*.log"))
            if app_support_log_files:
                print(f"  [找到] 应用支持目录: {len(app_support_log_files)} 个日志文件")
                all_log_files.extend(app_support_log_files)
    else:
        # 即使 get_app_support_log_dir() 返回 None，也记录检查的路径
        if sys.platform == 'win32':
            appdata = os.getenv('APPDATA')
            if appdata:
                app_support_log_dir = Path(appdata) / 'com.example.SvnMergeTool' / 'logs'
                checked_paths.append(("应用支持目录", app_support_log_dir))
        elif sys.platform == 'darwin':
            home = os.path.expanduser('~')
            app_support_log_dir = Path(home) / 'Library' / 'Application Support' / 'com.example.SvnMergeTool' / 'logs'
            checked_paths.append(("应用支持目录", app_support_log_dir))
    
    # 3. 检查可执行文件所在目录下的 logs（如果直接运行exe，工作目录是exe所在目录）
    exe_path = project_root / "build" / "windows" / "x64" / "runner" / "Debug" / "SvnMergeTool.exe"
    if exe_path.exists():
        exe_dir = exe_path.parent
        exe_dir_logs = exe_dir / "logs"
        checked_paths.append(("exe所在目录下的logs", exe_dir_logs))
        if exe_dir_logs.exists():
            exe_log_files = list(exe_dir_logs.glob("app_*.log"))
            if exe_log_files:
                print(f"  [找到] exe所在目录下的logs: {len(exe_log_files)} 个日志文件")
                all_log_files.extend(exe_log_files)
        
        # 3.1 也检查exe所在目录本身（可能日志直接在这里）
        checked_paths.append(("exe所在目录（直接）", exe_dir))
        exe_dir_logs_direct = list(exe_dir.glob("app_*.log"))
        if exe_dir_logs_direct:
            print(f"  [找到] exe所在目录（直接）: {len(exe_dir_logs_direct)} 个日志文件")
            all_log_files.extend(exe_dir_logs_direct)
    
    # 4. 检查当前工作目录下的 logs
    current_dir = Path.cwd()
    current_logs = current_dir / "logs"
    if current_logs != project_logs_dir:
        checked_paths.append(("当前工作目录", current_logs))
        if current_logs.exists():
            current_log_files = list(current_logs.glob("app_*.log"))
            if current_log_files:
                print(f"  [找到] 当前工作目录: {len(current_log_files)} 个日志文件")
                all_log_files.extend(current_log_files)
    
    if not all_log_files:
        print("  [警告] 未找到应用日志文件")
        print("\n  已检查的所有路径:")
        for name, path in checked_paths:
            exists = "存在" if path.exists() else "不存在"
            log_count = len(list(path.glob("app_*.log"))) if path.exists() else 0
            print(f"    {name}: {path}")
            print(f"      目录状态: {exists}, 日志文件数: {log_count}")
        print("\n  请检查:")
        print("    1. 程序是否已运行并生成日志")
        print("    2. 程序运行时的工作目录（Directory.current）")
        print("    3. 是否有其他位置的日志文件")
        return 0
    
    # 按修改时间排序，取最新的20个
    all_log_files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
    all_log_files = all_log_files[:20]
    
    count = 0
    for log_file in all_log_files:
        try:
            # 使用带来源标识的文件名，避免同名文件覆盖
            source = "project" if log_file.parent == project_logs_dir else "app_support"
            dest_file = log_dir / f"{source}_{log_file.name}"
            shutil.copy2(log_file, dest_file)
            print(f"  [OK] {dest_file.name} (来源: {log_file.parent})")
            count += 1
        except Exception as e:
            print(f"  [警告] 复制 {log_file.name} 失败: {e}")
    
    return count


def get_user_config_dir() -> Optional[Path]:
    """获取用户配置目录
    
    路径：
    - Windows: %APPDATA%/com.example.SvnMergeTool/config/
    - macOS: ~/Library/Application Support/com.example.SvnMergeTool/config/
    - Linux: ~/.local/share/com.example.SvnMergeTool/config/
    """
    try:
        if sys.platform == 'win32':
            appdata = os.getenv('APPDATA')
            if appdata:
                return Path(appdata) / 'com.example.SvnMergeTool' / 'config'
        elif sys.platform == 'darwin':
            home = os.path.expanduser('~')
            return Path(home) / 'Library' / 'Application Support' / 'com.example.SvnMergeTool' / 'config'
        elif sys.platform.startswith('linux'):
            home = os.path.expanduser('~')
            return Path(home) / '.local' / 'share' / 'com.example.SvnMergeTool' / 'config'
    except Exception:
        pass
    return None


def collect_config_files(project_root: Path, log_dir: Path):
    """收集配置文件"""
    print("\n收集配置文件...")
    
    # 1. 收集预置配置 assets/config/source_urls.json
    assets_config = project_root / "assets" / "config" / "source_urls.json"
    if assets_config.exists():
        try:
            dest_file = log_dir / "config_preset.json"
            shutil.copy2(assets_config, dest_file)
            print("  [OK] config_preset.json (预置配置，来自 assets/config/)")
        except Exception as e:
            print(f"  [警告] 复制预置配置失败: {e}")
    
    # 2. 收集用户配置（Application Support 目录）
    user_config_dir = get_user_config_dir()
    if user_config_dir:
        user_config = user_config_dir / "source_urls.json"
        if user_config.exists():
            try:
                dest_file = log_dir / "config_user.json"
                shutil.copy2(user_config, dest_file)
                print(f"  [OK] config_user.json (用户配置，来自 {user_config_dir})")
            except Exception as e:
                print(f"  [警告] 复制用户配置失败: {e}")
        else:
            print(f"  [信息] 用户配置不存在: {user_config}")
    
    # 3. 收集开发环境配置 config/source_urls.json（兼容旧版）
    runtime_config = project_root / "config" / "source_urls.json"
    if runtime_config.exists():
        try:
            dest_file = log_dir / "config_runtime.json"
            shutil.copy2(runtime_config, dest_file)
            print("  [OK] config_runtime.json (来自 config/)")
        except Exception as e:
            print(f"  [警告] 复制 config_runtime.json 失败: {e}")


def run_command(cmd: List[str]) -> Optional[str]:
    """运行命令并返回输出"""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
            check=False
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
        return None


def collect_system_info(log_dir: Path):
    """收集系统信息"""
    print("\n收集系统信息...")
    
    system_info_file = log_dir / "system_info.txt"
    
    with open(system_info_file, 'w', encoding='utf-8') as f:
        f.write("=== 系统信息 ===\n")
        f.write(f"时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"操作系统: {sys.platform}\n")
        
        # 尝试获取计算机名和用户名（跨平台）
        try:
            import os
            if hasattr(os, 'getenv'):
                computer_name = os.getenv('COMPUTERNAME') or os.getenv('HOSTNAME')
                if computer_name:
                    f.write(f"计算机名: {computer_name}\n")
                username = os.getenv('USERNAME') or os.getenv('USER')
                if username:
                    f.write(f"用户名: {username}\n")
        except Exception:
            pass
        
        f.write("\n")
        f.write("=== Flutter 信息 ===\n")
        flutter_version = run_command(['flutter', '--version'])
        if flutter_version:
            f.write(flutter_version)
            f.write("\n")
        else:
            f.write("Flutter 未安装或不在 PATH\n")
        
        f.write("\n")
        f.write("=== Dart 信息 ===\n")
        dart_version = run_command(['dart', '--version'])
        if dart_version:
            f.write(dart_version)
            f.write("\n")
        else:
            f.write("Dart 未安装或不在 PATH\n")
    
    print("  [OK] system_info.txt")


def generate_summary(log_dir: Path, log_count: int):
    """生成日志摘要"""
    print("\n生成日志摘要...")
    
    summary_file = log_dir / "SUMMARY.txt"
    
    # 计算总大小
    total_size = 0
    file_list = []
    for item in log_dir.iterdir():
        if item.is_file() and item.name != "SUMMARY.txt":
            size = item.stat().st_size
            total_size += size
            file_list.append((item.name, size))
    
    with open(summary_file, 'w', encoding='utf-8') as f:
        f.write("=== 日志收集摘要 ===\n")
        f.write(f"收集时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"日志目录: {log_dir}\n")
        f.write("\n")
        f.write("=== 收集的文件 ===\n")
        for name, size in sorted(file_list):
            # 格式化文件大小
            if size < 1024:
                size_str = f"{size} B"
            elif size < 1024 * 1024:
                size_str = f"{size / 1024:.1f} KB"
            else:
                size_str = f"{size / (1024 * 1024):.1f} MB"
            f.write(f"{name} ({size_str})\n")
        f.write("\n")
        f.write("=== 日志文件统计 ===\n")
        f.write(f"日志文件数量: {log_count}\n")
        if total_size < 1024:
            total_size_str = f"{total_size} B"
        elif total_size < 1024 * 1024:
            total_size_str = f"{total_size / 1024:.1f} KB"
        else:
            total_size_str = f"{total_size / (1024 * 1024):.1f} MB"
        f.write(f"总大小: {total_size_str}\n")
    
    print("  [OK] SUMMARY.txt")


def main():
    """主函数"""
    print("=" * 40)
    print("  日志收集脚本")
    print("=" * 40)
    
    # 获取项目根目录（使用 pathlib）
    project_root = get_project_root()
    
    # 创建日志目录（使用 pathlib）
    log_dir = create_log_directory(project_root)
    print(f"\n[OK] 创建日志目录: {log_dir}")
    
    # 收集日志文件
    log_count = collect_log_files(project_root, log_dir)
    
    # 收集配置文件
    collect_config_files(project_root, log_dir)
    
    # 收集系统信息
    collect_system_info(log_dir)
    
    # 生成摘要
    generate_summary(log_dir, log_count)
    
    print("\n" + "=" * 40)
    print("  日志收集完成！")
    print("=" * 40)
    print(f"\n日志目录: {log_dir}")
    print("\n查看日志：")
    print(f"  cat {log_dir / 'SUMMARY.txt'}")
    print(f"  tail -f {log_dir / 'app_*.log'}")


if __name__ == '__main__':
    try:
        main()
        sys.exit(0)
    except KeyboardInterrupt:
        print("\n\n[警告] 用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n[错误] 日志收集失败: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

