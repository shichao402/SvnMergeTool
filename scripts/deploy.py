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
"""

import sys
import subprocess
import shutil
import platform
from pathlib import Path
from typing import Optional, List, Tuple


def get_project_root() -> Path:
    """获取项目根目录"""
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    return project_root


def kill_existing_processes():
    """杀掉所有正在运行的 SvnMergeTool 进程"""
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
                if killed_count > 0:
                    print(f"[OK] Stopped {killed_count} existing process(es)")
                else:
                    print("[OK] No existing processes found")
            elif 'not found' in result.stderr.lower() or '没有找到' in result.stderr or '找不到' in result.stderr:
                print("[OK] No existing processes found")
            else:
                # 其他错误，但不阻止部署
                print("[OK] No existing processes to stop")
        else:
            # macOS/Linux: 使用 pkill 命令
            result = subprocess.run(
                ['pkill', '-f', 'SvnMergeTool'],
                capture_output=True,
                text=True,
                check=False
            )
            if result.returncode == 0:
                print("[OK] Stopped existing processes")
            else:
                print("[OK] No existing processes found")
    except Exception as e:
        print(f"[WARNING] Failed to stop processes: {e}")
        # 不阻止部署继续


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
        print("[ERROR] Flutter does not support building in WSL")
        print("Please use the Windows deployment script instead:")
        print("  scripts\\deploy.bat")
        print()
        print("Or run from Windows PowerShell/CMD:")
        print("  cd D:\\workspace\\GitHub\\SvnMergeTool")
        print("  scripts\\deploy.bat")
        return None, None
    
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
                # 使用 shell=True 和命令字符串，让系统解析 PATH
                # 在 Windows 上使用 UTF-8 编码避免中文乱码
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
                print(f"[OK] Flutter environment is ready")
                # 安全地打印版本信息，避免编码错误
                try:
                    print(f"  {version_line}")
                except UnicodeEncodeError:
                    # 如果编码失败，使用 ASCII 安全的方式
                    print(f"  {version_line.encode('ascii', 'replace').decode('ascii')}")
                # 在 Windows 上返回命令名，系统会自动解析
                return 'flutter', version_line
        except Exception as e:
            # 安全地打印错误信息
            try:
                print(f"[DEBUG] Flutter version check failed: {e}")
            except UnicodeEncodeError:
                print(f"[DEBUG] Flutter version check failed: {str(e).encode('ascii', 'replace').decode('ascii')}")
            pass
    
    print("[ERROR] Flutter CLI not found")
    print("Please install Flutter")
    print("Options:")
    print("  1. Install Flutter: https://docs.flutter.dev/get-started/install")
    return None, None


def check_devices(flutter_cmd: str) -> Tuple[int, bool]:
    """检查可用设备"""
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
                print("[WARNING] No available devices detected")
                print("For Windows desktop app, we will build only (no install/run needed)")
                return 0, True
            else:
                print(f"[OK] Detected {device_count} available device(s)")
                return device_count, False
    except Exception:
        pass
    
    print("[WARNING] No available devices detected")
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
    print("\nSyncing version number...")
    
    script_dir = Path(__file__).parent
    version_script = script_dir / 'version.bat' if platform.system() == 'Windows' else script_dir / 'version.sh'
    
    if not version_script.exists():
        print("[WARNING] Version management script not found, skipping version sync")
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
            print("[OK] Version synced")
            return True
        else:
            print("[WARNING] Version sync failed, continuing")
            return False
    except Exception as e:
        print(f"[WARNING] Version sync failed: {e}, continuing")
        return False


def copy_config_file(project_root: Path, platform_name: str) -> bool:
    """复制配置文件到构建输出目录"""
    config_source = project_root / 'config' / 'source_urls.json'
    if not config_source.exists():
        print(f"[WARNING] Config file not found: {config_source}")
        return False
    
    # 根据平台确定目标目录（使用 pathlib）
    if platform_name == 'windows':
        config_dir = project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'config'
    elif platform_name == 'macos':
        config_dir = project_root / 'build' / 'macos' / 'Build' / 'Products' / 'Debug' / 'SvnMergeTool.app' / 'Contents' / 'Resources' / 'config'
    else:  # linux
        config_dir = project_root / 'build' / 'linux' / 'x64' / 'debug' / 'bundle' / 'config'
    
    try:
        config_dir.mkdir(parents=True, exist_ok=True)
        dest_file = config_dir / 'source_urls.json'
        shutil.copy2(config_source, dest_file)
        print(f"[OK] Config file copied to build output")
        return True
    except Exception as e:
        print(f"[WARNING] Failed to copy config file: {e}")
        return False


def run_flutter_command(flutter_cmd: str, args: List[str], check: bool = True) -> bool:
    """运行 Flutter 命令"""
    # 在 Windows 上，如果 flutter_cmd 是 'flutter'，使用 shell=True
    if platform.system() == 'Windows' and flutter_cmd == 'flutter':
        cmd_str = 'flutter ' + ' '.join(args)
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
            print(f"[ERROR] Command timeout: {cmd_str}")
            return False
        except Exception as e:
            print(f"[ERROR] Command failed: {e}")
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
            print(f"[ERROR] Command timeout: {' '.join(cmd)}")
            return False
        except Exception as e:
            print(f"[ERROR] Command failed: {e}")
            return False


def main():
    """主函数"""
    print("=" * 40)
    print("  SVN Auto Merge Tool - Deploy Script")
    print("=" * 40)
    print()
    
    project_root = get_project_root()
    
    # 切换到项目目录
    import os
    os.chdir(str(project_root))
    
    # 杀掉所有正在运行的 SvnMergeTool 进程
    kill_existing_processes()
    
    # 检查 Flutter 环境
    flutter_cmd, flutter_version = check_flutter_environment()
    if not flutter_cmd:
        sys.exit(1)
    
    # 检查设备
    device_count, build_only = check_devices(flutter_cmd)
    
    # 检测平台
    platform_name = detect_platform()
    print(f"\nTarget platform: {platform_name}")
    
    # 清理之前的构建
    print("\nCleaning previous build...")
    if not run_flutter_command(flutter_cmd, ['clean'], check=False):
        print("[WARNING] Clean failed, continuing")
    else:
        print("[OK] Clean completed")
    
    # 同步版本号
    sync_version(project_root)
    
    # 获取依赖
    print("\nGetting dependencies...")
    if not run_flutter_command(flutter_cmd, ['pub', 'get']):
        print("[ERROR] Failed to get dependencies")
        sys.exit(1)
    print("[OK] Dependencies retrieved")
    
    # 构建应用
    print("\nBuilding application...")
    build_args = ['build', platform_name, '--debug']
    if not run_flutter_command(flutter_cmd, build_args):
        print("[ERROR] Build failed")
        sys.exit(1)
    print("[OK] Build completed")
    
    # 复制配置文件
    copy_config_file(project_root, platform_name)
    
    # 显示构建输出位置
    print()
    print("Application location:")
    if platform_name == 'windows':
        exe_path = project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'SvnMergeTool.exe'
        print(f"  {exe_path}")
    elif platform_name == 'macos':
        app_bundle = project_root / 'build' / 'macos' / 'Build' / 'Products' / 'Debug' / 'SvnMergeTool.app'
        print(f"  {app_bundle}")
    else:
        bundle_dir = project_root / 'build' / 'linux' / 'x64' / 'debug' / 'bundle'
        print(f"  {bundle_dir}")
    
    print("Config file location:")
    if platform_name == 'windows':
        config_path = project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'config' / 'source_urls.json'
    elif platform_name == 'macos':
        config_path = project_root / 'build' / 'macos' / 'Build' / 'Products' / 'Debug' / 'SvnMergeTool.app' / 'Contents' / 'Resources' / 'config' / 'source_urls.json'
    else:
        config_path = project_root / 'build' / 'linux' / 'x64' / 'debug' / 'bundle' / 'config' / 'source_urls.json'
    print(f"  {config_path}")
    
    # 如果只构建，则退出
    if build_only:
        print()
        print("[OK] Build completed!")
        sys.exit(0)
    
    # 安装到设备
    print("\nInstalling to device...")
    if not run_flutter_command(flutter_cmd, ['install'], check=False):
        print("[WARNING] Install failed, but continuing")
    else:
        print("[OK] Install completed")
    
    # 启动应用
    print("\nLaunching application...")
    if not run_flutter_command(flutter_cmd, ['run'], check=False):
        print("[WARNING] Application launch failed")
        sys.exit(1)
    print("[OK] Application launched")
    
    print()
    print("=" * 40)
    print("  Deployment completed!")
    print("=" * 40)
    print()


if __name__ == '__main__':
    try:
        main()
        sys.exit(0)
    except KeyboardInterrupt:
        print("\n\n[警告] 用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n[错误] 部署失败: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

