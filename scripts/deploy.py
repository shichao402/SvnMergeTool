#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Auto Merge Tool - Deploy Script (跨平台 Python 实现)

部署 Flutter 应用到目标平台
功能：
- 检查 Flutter 环境
- 构建应用
- 安装到设备
- 启动应用

路径处理规则：
- 必须使用 pathlib.Path 处理所有路径
- 严禁手动拼装路径分隔符（/ 或 \）
- 严禁手动处理盘符或绝对路径前缀

日志规范：
- 所有输出同时写入日志文件
- AI 必须通过日志文件判断执行结果
- 日志文件位置：logs/scripts/deploy_latest.log
"""

import sys
import subprocess
import shutil
import platform
from pathlib import Path
from typing import Optional, List, Tuple

# 添加 lib 目录到路径
sys.path.insert(0, str(Path(__file__).parent / 'lib'))
from script_logger import ScriptLogger

# 全局日志记录器
logger: Optional[ScriptLogger] = None


def get_project_root() -> Path:
    """获取项目根目录"""
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    return project_root


def kill_existing_processes():
    """杀掉所有正在运行的 SvnMergeTool 进程"""
    if logger:
        logger.info("停止现有 SvnMergeTool 进程...")
    else:
        print("Stopping existing SvnMergeTool processes...")
    
    system = platform.system()
    killed_count = 0
    
    try:
        if system == 'Windows':
            # Windows: 使用 taskkill 命令
            result = subprocess.run(
                ['taskkill', '/F', '/IM', 'SvnMergeTool.exe'],
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',
                check=False
            )
            if result.returncode == 0:
                # 统计杀掉的进程数
                killed_count = result.stdout.count('SUCCESS') + result.stdout.count('成功')
                msg = f"已停止 {killed_count} 个进程" if killed_count > 0 else "没有找到运行中的进程"
            elif 'not found' in result.stderr.lower() or '没有找到' in result.stderr or '找不到' in result.stderr:
                msg = "没有找到运行中的进程"
            else:
                msg = "没有需要停止的进程"
        else:
            # macOS/Linux: 使用 pkill 命令
            result = subprocess.run(
                ['pkill', '-f', 'SvnMergeTool'],
                capture_output=True,
                text=True,
                check=False
            )
            if result.returncode == 0:
                msg = "已停止现有进程"
            else:
                msg = "没有找到运行中的进程"
        
        if logger:
            logger.info(msg)
        else:
            print(f"[OK] {msg}")
    except Exception as e:
        msg = f"停止进程失败: {e}"
        if logger:
            logger.warn(msg)
        else:
            print(f"[WARNING] {msg}")


def is_wsl() -> bool:
    """检测是否在 WSL 环境中"""
    try:
        with open('/proc/version', 'r') as f:
            version = f.read().lower()
            return 'microsoft' in version or 'wsl' in version
    except (FileNotFoundError, IOError):
        return False


def find_command(cmd: str) -> Optional[str]:
    """查找命令是否在 PATH 中"""
    if platform.system() == 'Windows':
        # 在 Windows 上，使用 where.exe 命令
        # 注意：需要使用 shell=True 或完整路径，确保能访问系统 PATH
        result = subprocess.run(
            ['where.exe', cmd],
            capture_output=True,
            text=True,
            check=False,
            shell=False
        )
        if result.returncode == 0:
            # where 可能返回多行，取第一行
            path = result.stdout.strip().split('\n')[0].strip()
            if path:
                return path
    else:
        result = subprocess.run(
            ['which', cmd],
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0:
            return result.stdout.strip().split('\n')[0]
    return None


def check_flutter_environment() -> Tuple[Optional[str], Optional[str]]:
    """检查 Flutter 环境"""
    # 检查是否在 WSL 中
    if is_wsl():
        msg = "Flutter 不支持在 WSL 中构建"
        if logger:
            logger.error(msg)
            logger.info("请使用 Windows 部署脚本: scripts\\deploy.bat")
        else:
            print(f"[ERROR] {msg}")
            print("Please use the Windows deployment script instead:")
            print("  scripts\\deploy.bat")
        return None, None
    
    if logger:
        logger.info("检查 Flutter 环境...")
    else:
        print("Checking Flutter environment...")
    
    # 查找系统 Flutter
    flutter_cmd = find_command('flutter')
    if flutter_cmd:
        # 在 Windows 上，如果找到的是 .exe 文件，优先使用 .bat 文件
        if platform.system() == 'Windows' and flutter_cmd.endswith('.exe'):
            flutter_bat = flutter_cmd.replace('.exe', '.bat')
            if Path(flutter_bat).exists():
                flutter_cmd = flutter_bat
        
        try:
            # 在 Windows 上，使用 shell=True 确保能访问系统 PATH
            if platform.system() == 'Windows':
                result = subprocess.run(
                    'flutter --version',
                    shell=True,
                    capture_output=True,
                    text=True,
                    encoding='utf-8',
                    errors='replace',
                    timeout=10,
                    check=False
                )
            else:
                result = subprocess.run(
                    [flutter_cmd, '--version'],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=False
                )
            if result.returncode == 0:
                version_line = result.stdout.split('\n')[0]
                if logger:
                    logger.info("Flutter 环境就绪")
                    logger.info(f"版本: {version_line}")
                else:
                    print(f"[OK] Flutter environment is ready")
                    print(f"  {version_line}")
                return 'flutter', version_line
        except Exception as e:
            if logger:
                logger.debug(f"Flutter 版本检查失败: {e}")
            pass
    
    msg = "未找到 Flutter CLI"
    if logger:
        logger.error(msg)
        logger.info("请安装 Flutter: https://docs.flutter.dev/get-started/install")
    else:
        print(f"[ERROR] {msg}")
        print("Please install Flutter: https://docs.flutter.dev/get-started/install")
    return None, None


def check_devices(flutter_cmd: str) -> Tuple[int, bool]:
    """检查可用设备"""
    if logger:
        logger.info("检查可用设备...")
    else:
        print("\nChecking available devices...")
    
    try:
        # 在 Windows 上，如果 flutter_cmd 是 'flutter'，使用 shell=True
        if platform.system() == 'Windows' and flutter_cmd == 'flutter':
            cmd_str = 'flutter devices --machine'
            result = subprocess.run(
                cmd_str,
                shell=True,
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',
                timeout=10,
                check=False
            )
        else:
            result = subprocess.run(
                flutter_cmd.split() + ['devices', '--machine'],
                capture_output=True,
                text=True,
                timeout=10,
                check=False
            )
        
        if result.returncode == 0:
            device_count = result.stdout.count('"deviceId"')
            if device_count == 0:
                msg = "未检测到可用设备，将仅构建（桌面应用无需设备）"
                if logger:
                    logger.info(msg)
                else:
                    print(f"[WARNING] {msg}")
                return 0, True
            else:
                msg = f"检测到 {device_count} 个可用设备"
                if logger:
                    logger.info(msg)
                else:
                    print(f"[OK] {msg}")
                return device_count, False
    except Exception:
        pass
    
    msg = "未检测到可用设备"
    if logger:
        logger.info(msg)
    else:
        print(f"[WARNING] {msg}")
    return 0, True


def detect_platform() -> str:
    """检测目标平台"""
    system = platform.system()
    if system == 'Darwin':
        return 'macos'
    elif system == 'Windows':
        return 'windows'
    elif system == 'Linux':
        return 'linux'
    else:
        return 'windows'  # 默认


def sync_version(project_root: Path) -> bool:
    """同步版本号"""
    if logger:
        logger.info("同步版本号...")
    else:
        print("\nSyncing version number...")
    
    script_dir = Path(__file__).parent
    version_script = script_dir / 'version.bat' if platform.system() == 'Windows' else script_dir / 'version.sh'
    
    if not version_script.exists():
        msg = "版本管理脚本不存在，跳过版本同步"
        if logger:
            logger.warn(msg)
        else:
            print(f"[WARNING] {msg}")
        return False
    
    try:
        if platform.system() == 'Windows':
            result = subprocess.run(
                [str(version_script), 'sync', 'app'],
                cwd=str(project_root),
                capture_output=True,
                check=False
            )
        else:
            result = subprocess.run(
                ['bash', str(version_script), 'sync', 'app'],
                cwd=str(project_root),
                capture_output=True,
                check=False
            )
        
        if result.returncode == 0:
            msg = "版本同步完成"
            if logger:
                logger.info(msg)
            else:
                print(f"[OK] {msg}")
            return True
        else:
            msg = "版本同步失败，继续执行"
            if logger:
                logger.warn(msg)
            else:
                print(f"[WARNING] {msg}")
            return False
    except Exception as e:
        msg = f"版本同步失败: {e}，继续执行"
        if logger:
            logger.warn(msg)
        else:
            print(f"[WARNING] {msg}")
        return False


def copy_config_file(project_root: Path, platform_name: str) -> bool:
    """复制配置文件到构建输出目录
    
    注意：macOS 不复制配置文件到 .app 包内，因为这会破坏代码签名。
    macOS 应用从 assets 读取预置配置，用户配置保存在 Application Support 目录。
    """
    # macOS 不需要复制配置文件
    if platform_name == 'macos':
        msg = "macOS 使用 assets 预置配置，跳过复制配置文件"
        if logger:
            logger.info(msg)
        else:
            print(f"[INFO] {msg}")
        return True
    
    config_source = project_root / 'config' / 'source_urls.json'
    if not config_source.exists():
        msg = f"配置文件不存在: {config_source}"
        if logger:
            logger.warn(msg)
        else:
            print(f"[WARNING] {msg}")
        return False
    
    # 根据平台确定目标目录（使用 pathlib）
    if platform_name == 'windows':
        config_dir = project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'config'
    else:  # linux
        config_dir = project_root / 'build' / 'linux' / 'x64' / 'debug' / 'bundle' / 'config'
    
    try:
        config_dir.mkdir(parents=True, exist_ok=True)
        dest_file = config_dir / 'source_urls.json'
        shutil.copy2(config_source, dest_file)
        msg = "配置文件已复制到构建输出目录"
        if logger:
            logger.info(msg)
        else:
            print(f"[OK] {msg}")
        return True
    except Exception as e:
        msg = f"复制配置文件失败: {e}"
        if logger:
            logger.warn(msg)
        else:
            print(f"[WARNING] {msg}")
        return False


def run_flutter_command(flutter_cmd: str, args: List[str], check: bool = True) -> bool:
    """运行 Flutter 命令"""
    cmd_str = f"flutter {' '.join(args)}"
    if logger:
        logger.command(cmd_str)
    
    # 在 Windows 上，如果 flutter_cmd 是 'flutter'，使用 shell=True
    if platform.system() == 'Windows' and flutter_cmd == 'flutter':
        try:
            result = subprocess.run(
                cmd_str,
                shell=True,
                check=check,
                timeout=600,  # 10 分钟超时
                encoding='utf-8',
                errors='replace'
            )
            return result.returncode == 0
        except subprocess.TimeoutExpired:
            msg = f"命令超时: {cmd_str}"
            if logger:
                logger.error(msg)
            else:
                print(f"[ERROR] {msg}")
            return False
        except Exception as e:
            msg = f"命令失败: {e}"
            if logger:
                logger.error(msg)
            else:
                print(f"[ERROR] {msg}")
            return False
    else:
        cmd = flutter_cmd.split() + args
        try:
            result = subprocess.run(
                cmd,
                check=check,
                timeout=600  # 10 分钟超时
            )
            return result.returncode == 0
        except subprocess.TimeoutExpired:
            msg = f"命令超时: {' '.join(cmd)}"
            if logger:
                logger.error(msg)
            else:
                print(f"[ERROR] {msg}")
            return False
        except Exception as e:
            msg = f"命令失败: {e}"
            if logger:
                logger.error(msg)
            else:
                print(f"[ERROR] {msg}")
            return False


def main():
    """主函数"""
    global logger
    logger = ScriptLogger("deploy")
    
    project_root = get_project_root()
    
    # 切换到项目目录
    import os
    os.chdir(str(project_root))
    
    # 步骤计数
    total_steps = 7
    current_step = 0
    
    # 步骤 1: 杀掉所有正在运行的 SvnMergeTool 进程
    current_step += 1
    logger.step(current_step, total_steps, "停止现有进程")
    kill_existing_processes()
    logger.step_done(current_step, total_steps)
    
    # 步骤 2: 检查 Flutter 环境
    current_step += 1
    logger.step(current_step, total_steps, "检查 Flutter 环境")
    flutter_cmd, flutter_version = check_flutter_environment()
    if not flutter_cmd:
        logger.failed("Flutter 环境检查失败")
        sys.exit(1)
    logger.step_done(current_step, total_steps)
    
    # 步骤 3: 检查设备
    current_step += 1
    logger.step(current_step, total_steps, "检查可用设备")
    device_count, build_only = check_devices(flutter_cmd)
    logger.step_done(current_step, total_steps)
    
    # 检测平台
    platform_name = detect_platform()
    logger.info(f"目标平台: {platform_name}")
    
    # 步骤 4: 清理之前的构建
    current_step += 1
    logger.step(current_step, total_steps, "清理之前的构建")
    if not run_flutter_command(flutter_cmd, ['clean'], check=False):
        logger.warn("清理失败，继续执行")
    logger.step_done(current_step, total_steps)
    
    # 同步版本号
    sync_version(project_root)
    
    # 步骤 5: 获取依赖
    current_step += 1
    logger.step(current_step, total_steps, "获取依赖")
    if not run_flutter_command(flutter_cmd, ['pub', 'get']):
        logger.failed("获取依赖失败")
        sys.exit(1)
    logger.step_done(current_step, total_steps)
    
    # 步骤 6: 构建应用
    current_step += 1
    logger.step(current_step, total_steps, "构建应用")
    build_args = ['build', platform_name, '--debug']
    logger.command(f"flutter {' '.join(build_args)}")
    if not run_flutter_command(flutter_cmd, build_args):
        logger.failed("构建失败")
        sys.exit(1)
    logger.step_done(current_step, total_steps)
    
    # 复制配置文件
    copy_config_file(project_root, platform_name)
    
    # 显示构建输出位置
    if platform_name == 'windows':
        exe_path = project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'SvnMergeTool.exe'
        logger.info(f"应用位置: {exe_path}")
    elif platform_name == 'macos':
        app_bundle = project_root / 'build' / 'macos' / 'Build' / 'Products' / 'Debug' / 'SvnMergeTool.app'
        logger.info(f"应用位置: {app_bundle}")
    else:
        bundle_dir = project_root / 'build' / 'linux' / 'x64' / 'debug' / 'bundle'
        logger.info(f"应用位置: {bundle_dir}")
    
    # 步骤 7: 启动应用（如果不是仅构建模式）
    current_step += 1
    if build_only:
        logger.step(current_step, total_steps, "跳过启动（仅构建模式）")
        logger.step_done(current_step, total_steps)
        logger.success("部署完成（仅构建）")
        sys.exit(0)
    
    logger.step(current_step, total_steps, "启动应用")
    
    # 安装到设备
    logger.info("安装到设备...")
    if not run_flutter_command(flutter_cmd, ['install'], check=False):
        logger.warn("安装失败，但继续执行")
    
    # 启动应用
    logger.info("启动应用...")
    if not run_flutter_command(flutter_cmd, ['run'], check=False):
        logger.warn("应用启动失败")
    
    logger.step_done(current_step, total_steps)
    logger.success("部署完成")


if __name__ == '__main__':
    try:
        main()
        sys.exit(0)
    except KeyboardInterrupt:
        if logger:
            logger.warn("用户中断")
            logger.failed("用户中断")
        else:
            print("\n\n[警告] 用户中断")
        sys.exit(1)
    except Exception as e:
        if logger:
            logger.error(f"部署失败: {e}")
            import traceback
            logger.error(traceback.format_exc())
            logger.failed(str(e))
        else:
            print(f"\n[错误] 部署失败: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
        sys.exit(1)

