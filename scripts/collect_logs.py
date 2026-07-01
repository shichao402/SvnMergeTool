#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN 合并助手 - 日志收集脚本（跨平台 Python 实现）

收集所有相关日志文件到统一目录
包括：
- 应用日志文件（logs/latest.log, logs/app_*.log）
- Flutter 输出日志
- 配置文件
- 系统信息

路径处理规则：
- 必须使用 pathlib.Path 处理所有路径
- 严禁手动拼装路径分隔符（/ 或 \\）
- 严禁手动处理盘符或绝对路径前缀
- 使用 Path.joinpath() 或 / 操作符拼接路径
"""

import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Optional

LOG_PATTERNS = ("latest.log", "app_*.log")


def get_project_root() -> Path:
    """获取项目根目录。"""
    return Path(__file__).parent.resolve().parent


def create_log_directory(project_root: Path) -> Path:
    """创建日志收集目录。"""
    logs_dir = project_root / "logs"
    logs_dir.mkdir(exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_dir = logs_dir / f"app_{timestamp}"
    log_dir.mkdir(exist_ok=True)
    return log_dir


def get_app_support_roots() -> List[Path]:
    """获取当前平台实际使用的应用支持根目录。"""
    system = platform.system()

    if system == 'Windows':
        appdata = os.getenv('APPDATA')
        return [Path(appdata) / 'SvnAutoMerge'] if appdata else []
    if system == 'Darwin':
        return [
            Path.home()
            / 'Library'
            / 'Application Support'
            / 'com.example.svnautomerge'
        ]
    if system == 'Linux':
        return [Path.home() / '.local' / 'share' / 'SvnAutoMerge']
    return []


def get_runtime_log_dirs() -> List[Path]:
    """获取当前平台实际使用的运行时日志目录。"""
    return [root / 'logs' for root in get_app_support_roots()]


def get_user_config_dirs() -> List[Path]:
    """获取当前平台实际使用的用户配置目录。"""
    return [root / 'config' for root in get_app_support_roots()]


def list_log_files(directory: Path) -> List[Path]:
    """列出目录中的日志文件，包含 latest.log 和历史归档。"""
    files: List[Path] = []
    for pattern in LOG_PATTERNS:
        files.extend(directory.glob(pattern))
    files.sort(key=lambda file: file.stat().st_mtime, reverse=True)
    return files


def make_unique_dest(log_dir: Path, file_name: str) -> Path:
    """生成不冲突的目标文件名。"""
    candidate = log_dir / file_name
    if not candidate.exists():
        return candidate

    stem = Path(file_name).stem
    suffix = Path(file_name).suffix
    index = 1
    while True:
        candidate = log_dir / f"{stem}_{index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def collect_log_files(project_root: Path, log_dir: Path) -> int:
    """收集应用日志文件（从所有可能的位置）。"""
    print("\n收集应用日志文件...")

    checked_paths: List[tuple[str, Path]] = []
    collected: dict[str, Path] = {}

    project_logs_dir = project_root / 'logs'
    checked_paths.append(("项目根目录", project_logs_dir))
    if project_logs_dir.exists():
        project_log_files = list_log_files(project_logs_dir)
        if project_log_files:
            print(f"  [找到] 项目目录: {len(project_log_files)} 个日志文件")
        for log_file in project_log_files:
            collected.setdefault(str(log_file), log_file)

    for runtime_dir in get_runtime_log_dirs():
        checked_paths.append(("应用支持目录", runtime_dir))
        if runtime_dir.exists():
            runtime_logs = list_log_files(runtime_dir)
            if runtime_logs:
                print(f"  [找到] 应用支持目录: {len(runtime_logs)} 个日志文件 ({runtime_dir})")
            for log_file in runtime_logs:
                collected.setdefault(str(log_file), log_file)

    exe_dir_logs: Optional[Path] = None
    exe_dir: Optional[Path] = None
    exe_path = project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'SvnAutoMerge.exe'
    if exe_path.exists():
        exe_dir = exe_path.parent
        exe_dir_logs = exe_dir / 'logs'
        checked_paths.append(("exe所在目录下的logs", exe_dir_logs))
        if exe_dir_logs.exists():
            exe_logs = list_log_files(exe_dir_logs)
            if exe_logs:
                print(f"  [找到] exe所在目录下的logs: {len(exe_logs)} 个日志文件")
            for log_file in exe_logs:
                collected.setdefault(str(log_file), log_file)

        checked_paths.append(("exe所在目录（直接）", exe_dir))
        if exe_dir.exists():
            exe_direct_logs = list_log_files(exe_dir)
            if exe_direct_logs:
                print(f"  [找到] exe所在目录（直接）: {len(exe_direct_logs)} 个日志文件")
            for log_file in exe_direct_logs:
                collected.setdefault(str(log_file), log_file)

    current_dir = Path.cwd()
    current_logs = current_dir / 'logs'
    if current_logs != project_logs_dir:
        checked_paths.append(("当前工作目录", current_logs))
        if current_logs.exists():
            current_log_files = list_log_files(current_logs)
            if current_log_files:
                print(f"  [找到] 当前工作目录: {len(current_log_files)} 个日志文件")
            for log_file in current_log_files:
                collected.setdefault(str(log_file), log_file)

    all_log_files = sorted(
        collected.values(),
        key=lambda file: file.stat().st_mtime,
        reverse=True,
    )[:20]

    if not all_log_files:
        print("  [警告] 未找到应用日志文件")
        print("\n  已检查的所有路径:")
        for name, path in checked_paths:
            exists = "存在" if path.exists() else "不存在"
            log_count = len(list_log_files(path)) if path.exists() else 0
            print(f"    {name}: {path}")
            print(f"      目录状态: {exists}, 日志文件数: {log_count}")
        print("\n  请检查:")
        print("    1. 程序是否已运行并生成日志")
        print("    2. 程序运行时的工作目录（Directory.current）")
        print("    3. 是否有其他位置的日志文件")
        return 0

    print(f"  [信息] 共收集到 {len(all_log_files)} 个候选日志文件")

    count = 0
    for log_file in all_log_files:
        try:
            if log_file.parent == project_logs_dir:
                source = 'project'
            elif exe_dir_logs is not None and log_file.parent == exe_dir_logs:
                source = 'exe_logs'
            elif exe_dir is not None and log_file.parent == exe_dir:
                source = 'exe_dir'
            elif log_file.parent == current_logs:
                source = 'cwd'
            else:
                source = 'app_support'

            dest_file = make_unique_dest(log_dir, f"{source}_{log_file.name}")
            shutil.copy2(log_file, dest_file)
            print(f"  [OK] {dest_file.name} (来源: {log_file.parent})")
            count += 1
        except Exception as error:
            print(f"  [ERROR] 复制日志失败 {log_file}: {error}")

    return count


def collect_flutter_logs(project_root: Path, log_dir: Path) -> int:
    """收集 Flutter 输出日志。"""
    print("\n收集 Flutter 输出日志...")
    count = 0
    for pattern in ('flutter*.log', '*.flutter.log'):
        for log_file in sorted(project_root.glob(pattern), key=lambda file: file.stat().st_mtime, reverse=True)[:10]:
            try:
                dest_file = make_unique_dest(log_dir, f"flutter_{log_file.name}")
                shutil.copy2(log_file, dest_file)
                print(f"  [OK] {dest_file.name}")
                count += 1
            except Exception as error:
                print(f"  [ERROR] 复制 Flutter 日志失败 {log_file}: {error}")
    return count


def collect_config_files(project_root: Path, log_dir: Path) -> int:
    """收集配置文件快照。"""
    print("\n收集配置文件...")
    count = 0

    repo_config = project_root / 'config' / 'source_urls.json'
    if repo_config.exists():
        dest_file = make_unique_dest(log_dir, 'repo_source_urls.json')
        shutil.copy2(repo_config, dest_file)
        print(f"  [OK] {dest_file.name}")
        count += 1

    asset_config = project_root / 'assets' / 'config' / 'source_urls.json'
    if asset_config.exists():
        dest_file = make_unique_dest(log_dir, 'asset_source_urls.json')
        shutil.copy2(asset_config, dest_file)
        print(f"  [OK] {dest_file.name}")
        count += 1

    for config_dir in get_user_config_dirs():
        user_config = config_dir / 'source_urls.json'
        if user_config.exists():
            dest_file = make_unique_dest(log_dir, 'user_source_urls.json')
            shutil.copy2(user_config, dest_file)
            print(f"  [OK] {dest_file.name} ({user_config})")
            count += 1

    return count


def collect_system_info(log_dir: Path) -> bool:
    """收集系统信息。"""
    print("\n收集系统信息...")
    try:
        info_file = log_dir / 'system_info.txt'
        with info_file.open('w', encoding='utf-8') as file:
            file.write(f"platform: {platform.platform()}\n")
            file.write(f"system: {platform.system()}\n")
            file.write(f"release: {platform.release()}\n")
            file.write(f"version: {platform.version()}\n")
            file.write(f"machine: {platform.machine()}\n")
            file.write(f"python: {sys.version}\n")
            file.write(f"cwd: {Path.cwd()}\n")
        print(f"  [OK] {info_file.name}")
        return True
    except Exception as error:
        print(f"  [ERROR] 收集系统信息失败: {error}")
        return False


def collect_flutter_doctor(log_dir: Path) -> bool:
    """收集 flutter doctor 输出。"""
    print("\n收集 Flutter 环境信息...")
    try:
        result = subprocess.run(
            ['flutter', 'doctor', '-v'],
            capture_output=True,
            text=True,
            encoding='utf-8',
            errors='replace',
            check=False,
        )
        output_file = log_dir / 'flutter_doctor.txt'
        output_file.write_text(result.stdout + '\n' + result.stderr, encoding='utf-8')
        print(f"  [OK] {output_file.name}")
        return True
    except Exception as error:
        print(f"  [ERROR] 收集 Flutter 环境信息失败: {error}")
        return False


def main() -> int:
    project_root = get_project_root()
    log_dir = create_log_directory(project_root)

    print("=" * 70)
    print("SVN 合并助手日志收集")
    print("=" * 70)
    print(f"输出目录: {log_dir}")

    total = 0
    total += collect_log_files(project_root, log_dir)
    total += collect_flutter_logs(project_root, log_dir)
    total += collect_config_files(project_root, log_dir)
    collect_system_info(log_dir)
    collect_flutter_doctor(log_dir)

    print("\n" + "=" * 70)
    print(f"完成，共收集 {total} 个文件")
    print(f"输出目录: {log_dir}")
    print("=" * 70)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
