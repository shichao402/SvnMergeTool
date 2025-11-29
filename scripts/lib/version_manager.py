#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Version Management Tool

Manage project version numbers, supports:
- Read version number
- Set version number
- Increment version number
- Sync version number to project configuration file
"""

import argparse
import json
import re
import sys
import io
from pathlib import Path
from typing import Optional, Tuple

# Fix encoding for Windows
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

try:
    import yaml
except ImportError:
    print("Error: PyYAML library is required")
    print("Please run: pip install pyyaml")
    sys.exit(1)


class VersionManager:
    """版本号管理器"""
    
    def __init__(self, version_file: str = "VERSION.yaml"):
        """初始化版本管理器"""
        self.project_root = self._find_project_root()
        self.version_file = self.project_root / version_file
        
        if not self.version_file.exists():
            raise FileNotFoundError(f"版本文件不存在: {self.version_file}")
    
    def _find_project_root(self) -> Path:
        """查找项目根目录（包含 VERSION.yaml 的目录）"""
        current = Path.cwd()
        
        # 向上查找，直到找到 VERSION.yaml 或到达根目录
        for parent in [current] + list(current.parents):
            if (parent / "VERSION.yaml").exists():
                return parent
        
        # 如果找不到，使用当前目录
        return current
    
    def _load_version_file(self) -> dict:
        """加载版本文件"""
        with open(self.version_file, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    
    def _save_version_file(self, data: dict):
        """保存版本文件"""
        with open(self.version_file, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    def _parse_version(self, version_str: str) -> Tuple[int, int, int, int]:
        """解析版本号字符串
        
        格式: x.y.z+build 或 x.y.z
        返回: (major, minor, patch, build)
        """
        # 分离版本号和构建号
        if '+' in version_str:
            version_part, build_part = version_str.split('+', 1)
            build = int(build_part)
        else:
            version_part = version_str
            build = 0
        
        # 解析版本号部分
        parts = version_part.split('.')
        if len(parts) != 3:
            raise ValueError(f"版本号格式错误: {version_str}，应为 x.y.z+build")
        
        major = int(parts[0])
        minor = int(parts[1])
        patch = int(parts[2])
        
        return (major, minor, patch, build)
    
    def _format_version(self, major: int, minor: int, patch: int, build: int) -> str:
        """格式化版本号字符串"""
        return f"{major}.{minor}.{patch}+{build}"
    
    def get_version(self, component: str = "app") -> str:
        """获取版本号"""
        data = self._load_version_file()
        component_key = component if component in data else "app"
        
        if component_key not in data or "version" not in data[component_key]:
            raise ValueError(f"组件 {component_key} 的版本号不存在")
        
        return data[component_key]["version"]
    
    def set_version(self, component: str, version: str):
        """设置版本号"""
        # 验证版本号格式
        self._parse_version(version)
        
        data = self._load_version_file()
        if component not in data:
            data[component] = {}
        
        data[component]["version"] = version
        self._save_version_file(data)
        print(f"已设置 {component} 版本号为: {version}")
    
    def bump_version(self, component: str, part: str):
        """递增版本号
        
        Args:
            component: 组件名称（如 "app"）
            part: 要递增的部分（major, minor, patch, build）
        """
        current_version = self.get_version(component)
        major, minor, patch, build = self._parse_version(current_version)
        
        if part == "major":
            major += 1
            minor = 0
            patch = 0
        elif part == "minor":
            minor += 1
            patch = 0
        elif part == "patch":
            patch += 1
        elif part == "build":
            build += 1
        else:
            raise ValueError(f"无效的版本部分: {part}，应为 major/minor/patch/build")
        
        new_version = self._format_version(major, minor, patch, build)
        self.set_version(component, new_version)
        return new_version
    
    def sync_to_pubspec(self, component: str = "app"):
        """同步版本号到 pubspec.yaml"""
        version = self.get_version(component)
        pubspec_file = self.project_root / "pubspec.yaml"
        
        if not pubspec_file.exists():
            raise FileNotFoundError(f"pubspec.yaml 不存在: {pubspec_file}")
        
        # 读取 pubspec.yaml
        with open(pubspec_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 替换版本号（格式: version: x.y.z+build）
        pattern = r'^version:\s*[\d.]+(?:\+\d+)?'
        replacement = f'version: {version}'
        new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
        
        if new_content == content:
            # 如果没有匹配到，尝试添加
            if 'version:' not in content:
                # 在 name 行后添加 version
                content = re.sub(
                    r'^(name:.*)$',
                    f'\\1\nversion: {version}',
                    content,
                    flags=re.MULTILINE
                )
                new_content = content
            else:
                print(f"警告: 无法找到版本号行，请手动更新 pubspec.yaml")
                return False
        
        # 写入文件
        with open(pubspec_file, 'w', encoding='utf-8') as f:
            f.write(new_content)
        
        print(f"已同步版本号到 pubspec.yaml: {version}")
        return True
    
    def extract_version(self, component: str = "app", output_format: str = "text") -> str:
        """提取版本号（用于 CI/CD）
        
        Args:
            component: 组件名称
            output_format: 输出格式（text, json）
        """
        version = self.get_version(component)
        major, minor, patch, build = self._parse_version(version)
        
        if output_format == "json":
            result = {
                "version": version,
                "versionNumber": f"{major}.{minor}.{patch}",
                "buildNumber": str(build),
                "major": major,
                "minor": minor,
                "patch": patch,
                "build": build
            }
            return json.dumps(result, ensure_ascii=False)
        else:
            return version


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="版本号管理工具")
    subparsers = parser.add_subparsers(dest='command', help='命令')
    
    # get 命令
    parser_get = subparsers.add_parser('get', help='获取版本号')
    parser_get.add_argument('component', nargs='?', default='app', help='组件名称')
    parser_get.add_argument('--json', action='store_true', help='JSON 格式输出')
    
    # set 命令
    parser_set = subparsers.add_parser('set', help='设置版本号')
    parser_set.add_argument('component', help='组件名称')
    parser_set.add_argument('version', help='版本号（格式: x.y.z+build）')
    
    # bump 命令
    parser_bump = subparsers.add_parser('bump', help='递增版本号')
    parser_bump.add_argument('component', help='组件名称')
    parser_bump.add_argument('part', choices=['major', 'minor', 'patch', 'build'], help='要递增的部分')
    
    # sync 命令
    parser_sync = subparsers.add_parser('sync', help='同步版本号到项目配置文件')
    parser_sync.add_argument('component', nargs='?', default='app', help='组件名称')
    
    # extract 命令（用于 CI/CD）
    parser_extract = subparsers.add_parser('extract', help='提取版本号（用于 CI/CD）')
    parser_extract.add_argument('component', nargs='?', default='app', help='组件名称')
    parser_extract.add_argument('--json', action='store_true', help='JSON 格式输出')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    try:
        manager = VersionManager()
        
        if args.command == 'get':
            output_format = 'json' if args.json else 'text'
            result = manager.extract_version(args.component, output_format)
            print(result)
        
        elif args.command == 'set':
            manager.set_version(args.component, args.version)
        
        elif args.command == 'bump':
            new_version = manager.bump_version(args.component, args.part)
            print(f"版本号已递增为: {new_version}")
        
        elif args.command == 'sync':
            manager.sync_to_pubspec(args.component)
        
        elif args.command == 'extract':
            output_format = 'json' if args.json else 'text'
            result = manager.extract_version(args.component, output_format)
            print(result)
    
    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()


