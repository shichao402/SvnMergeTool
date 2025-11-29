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
    """Version Manager"""
    
    def __init__(self, version_file: str = "VERSION.yaml"):
        """Initialize version manager"""
        self.project_root = self._find_project_root()
        self.version_file = self.project_root / version_file
        
        if not self.version_file.exists():
            raise FileNotFoundError(f"Version file not found: {self.version_file}")
    
    def _find_project_root(self) -> Path:
        """Find project root directory (contains VERSION.yaml)"""
        current = Path.cwd()
        
        # Search upward until finding VERSION.yaml or reaching root
        for parent in [current] + list(current.parents):
            if (parent / "VERSION.yaml").exists():
                return parent
        
        # If not found, use current directory
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
        
        # Parse version number part
        parts = version_part.split('.')
        if len(parts) != 3:
            raise ValueError(f"Invalid version format: {version_str}, expected x.y.z+build")
        
        major = int(parts[0])
        minor = int(parts[1])
        patch = int(parts[2])
        
        return (major, minor, patch, build)
    
    def _format_version(self, major: int, minor: int, patch: int, build: int) -> str:
        """Format version string"""
        return f"{major}.{minor}.{patch}+{build}"
    
    def get_version(self, component: str = "app") -> str:
        """Get version number"""
        data = self._load_version_file()
        component_key = component if component in data else "app"
        
        if component_key not in data or "version" not in data[component_key]:
            raise ValueError(f"Version for component {component_key} not found")
        
        return data[component_key]["version"]
    
    def set_version(self, component: str, version: str):
        """Set version number"""
        # Validate version format
        self._parse_version(version)
        
        data = self._load_version_file()
        if component not in data:
            data[component] = {}
        
        data[component]["version"] = version
        self._save_version_file(data)
        print(f"Set {component} version to: {version}")
    
    def bump_version(self, component: str, part: str):
        """Increment version number
        
        Args:
            component: Component name (e.g., "app")
            part: Part to increment (major, minor, patch, build)
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
            raise ValueError(f"Invalid version part: {part}, should be major/minor/patch/build")
        
        new_version = self._format_version(major, minor, patch, build)
        self.set_version(component, new_version)
        return new_version
    
    def sync_to_pubspec(self, component: str = "app"):
        """Sync version number to pubspec.yaml"""
        version = self.get_version(component)
        pubspec_file = self.project_root / "pubspec.yaml"
        
        if not pubspec_file.exists():
            raise FileNotFoundError(f"pubspec.yaml not found: {pubspec_file}")
        
        # Read pubspec.yaml
        with open(pubspec_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Replace version (format: version: x.y.z+build)
        pattern = r'^version:\s*[\d.]+(?:\+\d+)?'
        replacement = f'version: {version}'
        new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
        
        if new_content == content:
            # If not matched, try to add
            if 'version:' not in content:
                # Add version after name line
                content = re.sub(
                    r'^(name:.*)$',
                    f'\\1\nversion: {version}',
                    content,
                    flags=re.MULTILINE
                )
                new_content = content
            else:
                print(f"Warning: Cannot find version line, please update pubspec.yaml manually")
                return False
        
        # Write file
        with open(pubspec_file, 'w', encoding='utf-8') as f:
            f.write(new_content)
        
        print(f"Synced version to pubspec.yaml: {version}")
        return True
    
    def extract_version(self, component: str = "app", output_format: str = "text") -> str:
        """Extract version number (for CI/CD)
        
        Args:
            component: Component name
            output_format: Output format (text, json)
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
    """Main function"""
    parser = argparse.ArgumentParser(description="Version Management Tool")
    subparsers = parser.add_subparsers(dest='command', help='Command')
    
    # get command
    parser_get = subparsers.add_parser('get', help='Get version number')
    parser_get.add_argument('component', nargs='?', default='app', help='Component name')
    parser_get.add_argument('--json', action='store_true', help='JSON format output')
    
    # set command
    parser_set = subparsers.add_parser('set', help='Set version number')
    parser_set.add_argument('component', help='Component name')
    parser_set.add_argument('version', help='Version number (format: x.y.z+build)')
    
    # bump command
    parser_bump = subparsers.add_parser('bump', help='Increment version number')
    parser_bump.add_argument('component', help='Component name')
    parser_bump.add_argument('part', choices=['major', 'minor', 'patch', 'build'], help='Part to increment')
    
    # sync command
    parser_sync = subparsers.add_parser('sync', help='Sync version to project config file')
    parser_sync.add_argument('component', nargs='?', default='app', help='Component name')
    
    # extract command (for CI/CD)
    parser_extract = subparsers.add_parser('extract', help='Extract version number (for CI/CD)')
    parser_extract.add_argument('component', nargs='?', default='app', help='Component name')
    parser_extract.add_argument('--json', action='store_true', help='JSON format output')
    
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
            print(f"Version incremented to: {new_version}")
        
        elif args.command == 'sync':
            manager.sync_to_pubspec(args.component)
        
        elif args.command == 'extract':
            output_format = 'json' if args.json else 'text'
            result = manager.extract_version(args.component, output_format)
            print(result)
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()


