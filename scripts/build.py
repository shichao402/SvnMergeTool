#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN 合并助手 - 跨平台桌面构建脚本。

功能：
- 自动识别当前系统并构建对应 Flutter 桌面产物
- 支持通过参数显式指定目标平台
- 构建前同步 VERSION.yaml 到 pubspec.yaml
- 输出脚本日志到 logs/scripts/build_latest.log
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys
import traceback
import zipfile
from pathlib import Path
from typing import Iterable, List, Optional, Union

sys.path.insert(0, str(Path(__file__).parent / "lib"))
from script_logger import ScriptLogger


SUPPORTED_PLATFORMS = ("windows", "macos", "linux")
BUILD_MODES = ("debug", "profile", "release")
APP_NAME = "SvnAutoMerge"

logger: Optional[ScriptLogger] = None


def get_project_root() -> Path:
    """获取项目根目录。"""
    return Path(__file__).parent.resolve().parent


def is_wsl() -> bool:
    """检测是否在 WSL 中运行。"""
    version_file = Path("/proc/version")
    if not version_file.exists():
        return False
    try:
        version = version_file.read_text(encoding="utf-8", errors="ignore").lower()
        return "microsoft" in version or "wsl" in version
    except OSError:
        return False


def detect_current_platform() -> str:
    """把系统平台映射为 Flutter 桌面平台名。"""
    system = platform.system()
    if system == "Darwin":
        return "macos"
    if system == "Windows":
        return "windows"
    if system == "Linux":
        return "linux"
    return "unknown"


def quote_command(command: Iterable[str]) -> str:
    """生成便于日志阅读的命令字符串。"""
    return subprocess.list2cmdline([str(part) for part in command])


def run_command(
    command: List[str],
    cwd: Path,
    timeout_seconds: int,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """执行命令并写入日志。"""
    if logger:
        logger.command(quote_command(command))

    use_shell = os.name == "nt" and Path(command[0]).suffix.lower() in (".bat", ".cmd")
    command_for_run: Union[List[str], str] = command
    if use_shell:
        command_for_run = quote_command(command)

    result = subprocess.run(
        command_for_run,
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout_seconds,
        shell=use_shell,
        check=False,
    )

    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    if output and logger:
        logger.command_output(output, max_lines=200)

    if check and result.returncode != 0:
        raise RuntimeError(
            f"命令执行失败（exit {result.returncode}）: {quote_command(command)}"
        )

    return result


def find_flutter() -> Optional[str]:
    """查找 Flutter CLI。"""
    flutter_path = shutil.which("flutter")
    if not flutter_path:
        return None
    return flutter_path


def check_flutter(project_root: Path) -> str:
    """检查 Flutter 环境并返回命令路径。"""
    flutter_cmd = find_flutter()
    if not flutter_cmd:
        raise RuntimeError("未找到 Flutter CLI，请先安装 Flutter 并加入 PATH")

    result = run_command([flutter_cmd, "--version"], project_root, timeout_seconds=30)
    first_line = result.stdout.splitlines()[0] if result.stdout.splitlines() else "unknown"
    if logger:
        logger.info(f"Flutter 环境就绪: {first_line}")
    return flutter_cmd


def validate_platform(target_platform: str, current_platform: str, project_root: Path) -> None:
    """校验目标平台是否能在当前系统构建。"""
    if target_platform not in SUPPORTED_PLATFORMS:
        raise RuntimeError(
            f"不支持的目标平台: {target_platform}，可选值: {', '.join(SUPPORTED_PLATFORMS)}"
        )

    if current_platform == "unknown":
        raise RuntimeError(f"无法识别当前系统平台: {platform.platform()}")

    if is_wsl():
        raise RuntimeError("检测到 WSL 环境，Flutter 桌面构建请在原生系统中执行")

    if target_platform != current_platform:
        raise RuntimeError(
            "Flutter 桌面不支持在当前环境交叉构建："
            f"当前平台是 {current_platform}，目标平台是 {target_platform}。"
            "请在对应系统上执行，例如 Windows 版本需要在 Windows 环境构建。"
        )

    platform_dir = project_root / target_platform
    if not platform_dir.exists():
        raise RuntimeError(
            f"项目缺少 {target_platform} 桌面平台目录: {platform_dir}。"
            "请先为该平台生成 Flutter 桌面工程后再构建。"
        )


def sync_version(project_root: Path, component: str) -> Optional[str]:
    """复用现有版本管理脚本，同步版本号并返回版本字符串。"""
    version_manager = project_root / "scripts" / "lib" / "version_manager.py"
    if not version_manager.exists():
        if logger:
            logger.warn("未找到版本管理脚本，跳过版本同步")
        return None

    python_cmd = sys.executable
    try:
        if logger:
            logger.info("同步 VERSION.yaml 到 pubspec.yaml...")
        run_command(
            [python_cmd, str(version_manager), "sync", component],
            project_root,
            timeout_seconds=60,
        )

        result = run_command(
            [python_cmd, str(version_manager), "extract", component],
            project_root,
            timeout_seconds=60,
        )
        version = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else None
        if version and logger:
            logger.info(f"当前版本: {version}")
        return version
    except Exception as error:
        if logger:
            logger.warn(f"版本同步失败，继续构建: {error}")
        return None


def should_run_codegen(project_root: Path) -> bool:
    """根据项目文件判断是否需要生成 json_serializable 代码。"""
    pubspec_file = project_root / "pubspec.yaml"
    if not pubspec_file.exists():
        return False

    content = pubspec_file.read_text(encoding="utf-8")
    return "build_runner" in content


def run_flutter_build(
    flutter_cmd: str,
    project_root: Path,
    target_platform: str,
    mode: str,
    clean: bool,
    skip_codegen: bool,
) -> None:
    """执行 Flutter 桌面构建。"""
    if clean:
        run_command([flutter_cmd, "clean"], project_root, timeout_seconds=600, check=False)

    run_command([flutter_cmd, "pub", "get"], project_root, timeout_seconds=600)

    if not skip_codegen and should_run_codegen(project_root):
        run_command(
            [
                flutter_cmd,
                "pub",
                "run",
                "build_runner",
                "build",
                "--delete-conflicting-outputs",
            ],
            project_root,
            timeout_seconds=900,
        )
    elif skip_codegen and logger:
        logger.info("已按参数跳过代码生成")

    run_command(
        [flutter_cmd, "build", target_platform, f"--{mode}"],
        project_root,
        timeout_seconds=1800,
    )


def get_build_output_path(project_root: Path, target_platform: str, mode: str) -> Path:
    """获取 Flutter 桌面构建产物路径。"""
    mode_dir = mode.capitalize()
    if target_platform == "macos":
        return project_root / "build" / "macos" / "Build" / "Products" / mode_dir / f"{APP_NAME}.app"
    if target_platform == "windows":
        return project_root / "build" / "windows" / "x64" / "runner" / mode_dir
    return project_root / "build" / "linux" / "x64" / mode / "bundle"


def normalize_version_for_file(version: Optional[str]) -> str:
    """把版本号转换为文件名安全格式。"""
    if not version:
        return "unknown"
    return version.replace("+", "build")


def add_directory_to_zip(zip_file: zipfile.ZipFile, source: Path, include_root: bool) -> None:
    """把目录加入 zip 包。"""
    base_dir = source.parent if include_root else source
    for file_path in source.rglob("*"):
        if file_path.is_file():
            zip_file.write(file_path, file_path.relative_to(base_dir))


def package_output(
    project_root: Path,
    target_platform: str,
    output_path: Path,
    version: Optional[str],
) -> Path:
    """打包构建产物为 zip。"""
    dist_dir = project_root / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)
    version_for_file = normalize_version_for_file(version)
    zip_path = dist_dir / f"{APP_NAME}_{target_platform}_{version_for_file}.zip"

    if zip_path.exists():
        zip_path.unlink()

    include_root = target_platform == "macos"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        if output_path.is_dir():
            add_directory_to_zip(archive, output_path, include_root=include_root)
        else:
            archive.write(output_path, output_path.name)

    if logger:
        logger.info(f"打包产物: {zip_path}")
    return zip_path


def create_parser() -> argparse.ArgumentParser:
    """创建命令行参数解析器。"""
    parser = argparse.ArgumentParser(
        description="自动识别平台并构建 Flutter 桌面产物",
    )
    parser.add_argument(
        "--platform",
        dest="target_platform",
        choices=SUPPORTED_PLATFORMS,
        help="目标平台，默认自动识别当前系统",
    )
    parser.add_argument(
        "--mode",
        choices=BUILD_MODES,
        default="release",
        help="构建模式，默认 release",
    )
    parser.add_argument(
        "--component",
        default="app",
        help="VERSION.yaml 中的组件名，默认 app",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="构建前执行 flutter clean",
    )
    parser.add_argument(
        "--skip-codegen",
        action="store_true",
        help="跳过 build_runner 代码生成",
    )
    parser.add_argument(
        "--package",
        action="store_true",
        help="构建成功后打包为 dist/*.zip",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只校验平台并输出计划，不执行 Flutter 命令",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    """主入口。"""
    global logger
    logger = ScriptLogger("build")

    parser = create_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exit_error:
        code = int(exit_error.code or 0)
        if code == 0:
            logger.success("显示帮助完成")
        else:
            logger.failed("参数解析失败")
        return code

    project_root = get_project_root()
    os.chdir(str(project_root))

    current_platform = detect_current_platform()
    target_platform = args.target_platform or current_platform

    try:
        logger.info(f"项目目录: {project_root}")
        logger.info(f"当前平台: {current_platform}")
        logger.info(f"目标平台: {target_platform}")
        logger.info(f"构建模式: {args.mode}")

        validate_platform(target_platform, current_platform, project_root)

        if args.dry_run:
            logger.info("dry-run 模式：已完成平台校验，将跳过 Flutter 命令")
            logger.success("dry-run 校验完成")
            return 0

        flutter_cmd = check_flutter(project_root)
        version = sync_version(project_root, args.component)
        run_flutter_build(
            flutter_cmd=flutter_cmd,
            project_root=project_root,
            target_platform=target_platform,
            mode=args.mode,
            clean=args.clean,
            skip_codegen=args.skip_codegen,
        )

        output_path = get_build_output_path(project_root, target_platform, args.mode)
        if not output_path.exists():
            raise RuntimeError(f"构建命令完成，但未找到预期产物: {output_path}")

        logger.info(f"构建产物: {output_path}")

        if args.package:
            package_output(project_root, target_platform, output_path, version)

        logger.success("构建完成")
        return 0
    except Exception as error:
        logger.error(f"构建失败: {error}")
        logger.error(traceback.format_exc())
        logger.failed(str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
