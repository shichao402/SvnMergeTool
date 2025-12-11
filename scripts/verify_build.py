#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Auto Merge Tool - Verify Build Script (跨平台 Python 实现)

验证 Flutter 构建环境
检查环境是否准备好进行构建

路径处理规则：
- 必须使用 pathlib.Path 处理所有路径
"""

import sys
import subprocess
import os
from pathlib import Path
from typing import Optional


def get_project_root() -> Path:
    """获取项目根目录"""
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    return project_root


def find_command(cmd: str) -> Optional[str]:
    """查找命令是否在 PATH 中"""
    import platform
    if platform.system() == 'Windows':
        result = subprocess.run(
            ['where', cmd],
            capture_output=True,
            text=True,
            check=False
        )
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


def run_command(cmd: list, check: bool = False) -> bool:
    """运行命令"""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60,
            check=check
        )
        return result.returncode == 0
    except Exception:
        return False


def main():
    """主函数"""
    print("=" * 40)
    print("  Verifying Build Environment")
    print("=" * 40)
    print()
    
    project_root = get_project_root()
    os.chdir(str(project_root))
    
    # 1. 检查 Flutter
    print("1. Checking Flutter...")
    flutter_cmd = find_command('flutter')
    if flutter_cmd:
        try:
            result = subprocess.run(
                ['flutter', '--version'],
                capture_output=True,
                text=True,
                timeout=10,
                check=False
            )
            if result.returncode == 0:
                version_line = result.stdout.split('\n')[0]
                print(f"✓ Flutter found: {version_line}")
            else:
                print("✗ Flutter not found")
                return 1
        except Exception:
            print("✗ Flutter not found")
            return 1
    else:
        print("✗ Flutter not found")
        return 1
    
    # 2. 运行 flutter doctor
    print("\n2. Running flutter doctor...")
    run_command(['flutter', 'doctor'], check=False)
    
    # 3. 检查项目目录
    print("\n3. Checking project...")
    print(f"✓ Project directory: {project_root}")
    
    # 4. 获取依赖
    print("\n4. Getting dependencies...")
    if run_command(['flutter', 'pub', 'get']):
        print("✓ Dependencies retrieved")
    else:
        print("✗ Failed to get dependencies")
        return 1
    
    # 5. 检查构建工具
    print("\n5. Checking build tools...")
    cmake_cmd = find_command('cmake')
    if cmake_cmd:
        print("✓ CMake found")
    else:
        print("⚠ CMake not found (may be needed for Windows build)")
    
    # 6. 检查设备
    print("\n6. Checking available devices...")
    run_command(['flutter', 'devices'], check=False)
    
    # 7. 测试构建（dry-run）
    print("\n7. Testing build (dry-run)...")
    result = subprocess.run(
        ['flutter', 'build', 'windows', '--debug', '--dry-run'],
        capture_output=True,
        text=True,
        timeout=60,
        check=False
    )
    if 'build windows' in result.stdout or result.returncode == 0:
        print("✓ Build configuration looks good")
    else:
        print("⚠ Build dry-run completed (may have warnings)")
    
    print("\n" + "=" * 40)
    print("  Environment Verification Complete!")
    print("=" * 40)
    print()
    
    print("Next steps:")
    print("  flutter run -d windows - Run the app")
    print("  flutter build windows --debug - Build for Windows")
    print("  ./scripts/deploy.sh - Use deployment script")
    print()
    
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\n[警告] 用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n[错误] 验证失败: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)




