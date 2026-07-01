#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN 合并助手 - 构建环境验证脚本（跨平台 Python 实现）

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
    print("  验证构建环境")
    print("=" * 40)
    print()
    
    project_root = get_project_root()
    os.chdir(str(project_root))
    
    # 1. 检查 Flutter
    print("1. 检查 Flutter...")
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
                print(f"✓ 已检测到 Flutter: {version_line}")
            else:
                print("✗ 未找到 Flutter")
                return 1
        except Exception:
            print("✗ 未找到 Flutter")
            return 1
    else:
        print("✗ 未找到 Flutter")
        return 1
    
    # 2. 运行 flutter doctor
    print("\n2. 运行 flutter doctor...")
    run_command(['flutter', 'doctor'], check=False)
    
    # 3. 检查项目目录
    print("\n3. 检查项目目录...")
    print(f"✓ 项目目录: {project_root}")
    
    # 4. 获取依赖
    print("\n4. 获取依赖...")
    if run_command(['flutter', 'pub', 'get']):
        print("✓ 依赖获取成功")
    else:
        print("✗ 获取依赖失败")
        return 1
    
    # 5. 检查构建工具
    print("\n5. 检查构建工具...")
    cmake_cmd = find_command('cmake')
    if cmake_cmd:
        print("✓ 已检测到 CMake")
    else:
        print("⚠ 未检测到 CMake（Windows 构建可能需要）")
    
    # 6. 检查设备
    print("\n6. 检查可用设备...")
    run_command(['flutter', 'devices'], check=False)
    
    # 7. 测试构建（dry-run）
    print("\n7. 测试构建（dry-run）...")
    result = subprocess.run(
        ['flutter', 'build', 'windows', '--debug', '--dry-run'],
        capture_output=True,
        text=True,
        timeout=60,
        check=False
    )
    if 'build windows' in result.stdout or result.returncode == 0:
        print("✓ 构建配置看起来正常")
    else:
        print("⚠ dry-run 已完成（可能仍有警告）")
    
    print("\n" + "=" * 40)
    print("  构建环境验证完成！")
    print("=" * 40)
    print()
    
    print("下一步：")
    print("  flutter run -d windows  # 启动应用")
    print("  flutter build windows --debug  # 构建 Windows 调试包")
    print("  ./scripts/deploy.sh  # 使用仓库部署脚本")
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




