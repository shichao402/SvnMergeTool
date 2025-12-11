#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Auto Merge Tool - Commit Script (跨平台 Python 实现)

提交所有本地更改并推送到远程仓库
功能：
- 添加所有更改的文件
- 创建提交（使用环境变量 COMMIT_MESSAGE 或默认消息）
- 推送到远程仓库

路径处理规则：
- 必须使用 pathlib.Path 处理所有路径
- 严禁手动拼装路径分隔符（/ 或 \）
"""

import sys
import subprocess
import os
from pathlib import Path
from datetime import datetime
from typing import Optional, List


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


def check_git_environment() -> bool:
    """检查 Git 环境"""
    print("Checking Git environment...")
    
    git_cmd = find_command('git')
    if not git_cmd:
        print("[ERROR] Git CLI not found")
        print("Please ensure Git is installed and added to PATH")
        return False
    
    try:
        result = subprocess.run(
            ['git', '--version'],
            capture_output=True,
            text=True,
            timeout=10,
            check=False
        )
        if result.returncode == 0:
            version = result.stdout.strip()
            print(f"[OK] Git environment is ready")
            print(f"  {version}")
            return True
    except Exception:
        pass
    
    print("[ERROR] Git CLI not found")
    return False


def is_git_repository(project_root: Path) -> bool:
    """检查是否在 Git 仓库中"""
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--git-dir'],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            check=False
        )
        return result.returncode == 0
    except Exception:
        return False


def get_staged_files(project_root: Path) -> List[str]:
    """获取已暂存的文件列表"""
    try:
        result = subprocess.run(
            ['git', 'diff', '--cached', '--name-only'],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0 and result.stdout.strip():
            return [f.strip() for f in result.stdout.strip().split('\n') if f.strip()]
    except Exception:
        pass
    return []


def get_current_branch(project_root: Path) -> Optional[str]:
    """获取当前分支"""
    try:
        result = subprocess.run(
            ['git', 'branch', '--show-current'],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def get_remote_name(project_root: Path) -> Optional[str]:
    """获取远程仓库名称"""
    try:
        result = subprocess.run(
            ['git', 'remote'],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split('\n')[0]
    except Exception:
        pass
    return None


def get_remote_url(project_root: Path, remote: str) -> Optional[str]:
    """获取远程仓库 URL"""
    try:
        result = subprocess.run(
            ['git', 'remote', 'get-url', remote],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def main():
    """主函数"""
    print("=" * 40)
    print("  SVN Auto Merge Tool - Commit Script")
    print("=" * 40)
    print()
    
    project_root = get_project_root()
    
    # 切换到项目目录
    os.chdir(str(project_root))
    
    # 检查 Git 环境
    if not check_git_environment():
        sys.exit(1)
    
    # 检查是否在 Git 仓库中
    if not is_git_repository(project_root):
        print("[ERROR] Current directory is not a Git repository")
        sys.exit(1)
    
    # 添加所有更改的文件
    print("\nChecking changed files...")
    try:
        subprocess.run(
            ['git', 'add', '-A'],
            cwd=str(project_root),
            check=True
        )
    except subprocess.CalledProcessError:
        print("[ERROR] Failed to add files")
        sys.exit(1)
    
    # 检查是否有已暂存的文件
    staged_files = get_staged_files(project_root)
    if not staged_files:
        print("[WARNING] No files to commit")
        print("Working directory is clean, no commit needed")
        sys.exit(0)
    
    print("[OK] Files to be committed:")
    for file in staged_files:
        print(f"  - {file}")
    
    # 生成提交消息
    commit_message = os.getenv('COMMIT_MESSAGE')
    if commit_message:
        print(f"\nUsing custom commit message: {commit_message}")
    else:
        # 生成默认提交消息（包含时间戳）
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        commit_message = f"Auto commit: {timestamp}"
        print(f"\nUsing default commit message: {commit_message}")
    
    # 创建提交
    print("\nCreating commit...")
    try:
        subprocess.run(
            ['git', 'commit', '-m', commit_message, '--no-verify'],
            cwd=str(project_root),
            check=True
        )
        print("[OK] Commit created successfully")
    except subprocess.CalledProcessError:
        print("[ERROR] Commit creation failed")
        sys.exit(1)
    
    # 获取当前分支
    current_branch = get_current_branch(project_root)
    if current_branch:
        print(f"\nCurrent branch: {current_branch}")
    
    # 检查远程仓库
    print("\nChecking remote repository...")
    remote = get_remote_name(project_root)
    if not remote:
        print("[WARNING] No remote repository configured")
        print("Skipping push operation")
        sys.exit(0)
    
    remote_url = get_remote_url(project_root, remote)
    if remote_url:
        print(f"[OK] Remote repository: {remote} ({remote_url})")
    else:
        print(f"[OK] Remote repository: {remote} (Not configured)")
    
    # 推送到远程仓库
    print("\nPushing to remote repository...")
    try:
        if current_branch:
            subprocess.run(
                ['git', 'push', remote, current_branch],
                cwd=str(project_root),
                check=True
            )
        else:
            subprocess.run(
                ['git', 'push', remote],
                cwd=str(project_root),
                check=True
            )
        print("[OK] Push completed successfully")
    except subprocess.CalledProcessError:
        print("[ERROR] Push failed")
        print("Please check network connection and remote repository permissions")
        sys.exit(1)
    
    print()
    print("=" * 40)
    print("  Commit and push completed!")
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
        print(f"\n[错误] 提交失败: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)




