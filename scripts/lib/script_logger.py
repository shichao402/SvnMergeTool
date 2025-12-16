#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
脚本日志工具类

提供统一的日志输出功能，同时输出到标准输出和日志文件。
AI 必须通过日志文件判断脚本执行结果，而非标准输出。

日志文件位置：logs/scripts/{脚本名}_{时间戳}.log
最新日志链接：logs/scripts/{脚本名}_latest.log
"""

import os
import sys
from pathlib import Path
from datetime import datetime
from typing import Optional


class ScriptLogger:
    """脚本日志记录器
    
    使用示例：
    ```python
    from lib.script_logger import ScriptLogger
    
    logger = ScriptLogger("deploy")
    logger.info("开始部署")
    logger.info("步骤 1/3: 清理")
    # ... 执行操作 ...
    logger.success()  # 或 logger.failed("原因")
    ```
    """
    
    def __init__(self, script_name: str, log_dir: Optional[Path] = None):
        """初始化日志记录器
        
        Args:
            script_name: 脚本名称，用于生成日志文件名
            log_dir: 日志目录，默认为项目根目录下的 logs/scripts/
        """
        self.script_name = script_name
        self.start_time = datetime.now()
        
        # 确定日志目录
        if log_dir:
            self.log_dir = Path(log_dir)
        else:
            # 默认：项目根目录/logs/scripts/
            project_root = Path(__file__).parent.parent.parent
            self.log_dir = project_root / "logs" / "scripts"
        
        self.log_dir.mkdir(parents=True, exist_ok=True)
        
        # 生成日志文件名
        timestamp = self.start_time.strftime("%Y%m%d_%H%M%S")
        self.log_file = self.log_dir / f"{script_name}_{timestamp}.log"
        self.latest_link = self.log_dir / f"{script_name}_latest.log"
        
        # 更新最新日志链接（跨平台处理）
        self._update_latest_link()
        
        # 记录脚本开始
        self._write_header()
    
    def _update_latest_link(self):
        """更新最新日志链接"""
        try:
            # 删除旧链接
            if self.latest_link.exists() or self.latest_link.is_symlink():
                self.latest_link.unlink()
            
            # 创建新链接
            if os.name == 'nt':
                # Windows: 复制文件路径到 .latest 文件
                # Windows 符号链接需要管理员权限，使用替代方案
                with open(self.latest_link, 'w', encoding='utf-8') as f:
                    f.write(str(self.log_file.name))
            else:
                # Unix: 创建符号链接
                self.latest_link.symlink_to(self.log_file.name)
        except Exception as e:
            # 链接创建失败不影响主要功能
            print(f"[WARN] 无法创建最新日志链接: {e}", file=sys.stderr)
    
    def _write_header(self):
        """写入日志头部"""
        separator = "=" * 50
        self._log("INFO", separator)
        self._log("INFO", f"{self.script_name} 脚本开始执行")
        self._log("INFO", separator)
        self._log("INFO", f"平台: {sys.platform}")
        self._log("INFO", f"Python: {sys.version.split()[0]}")
        self._log("INFO", f"工作目录: {Path.cwd()}")
        self._log("INFO", f"日志文件: {self.log_file}")
    
    def _log(self, level: str, message: str):
        """写入日志
        
        Args:
            level: 日志级别 (INFO, WARN, ERROR, DEBUG)
            message: 日志消息
        """
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"[{timestamp}] [{level}] {message}"
        
        # 输出到标准输出
        if level == "ERROR":
            print(line, file=sys.stderr)
        else:
            print(line)
        
        # 写入日志文件
        try:
            with open(self.log_file, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except Exception as e:
            print(f"[ERROR] 无法写入日志文件: {e}", file=sys.stderr)
    
    def info(self, message: str):
        """记录信息日志"""
        self._log("INFO", message)
    
    def warn(self, message: str):
        """记录警告日志"""
        self._log("WARN", message)
    
    def error(self, message: str):
        """记录错误日志"""
        self._log("ERROR", message)
    
    def debug(self, message: str):
        """记录调试日志"""
        self._log("DEBUG", message)
    
    def step(self, current: int, total: int, description: str):
        """记录步骤进度
        
        Args:
            current: 当前步骤
            total: 总步骤数
            description: 步骤描述
        """
        self.info(f"步骤 {current}/{total}: {description}")
    
    def step_done(self, current: int, total: int):
        """记录步骤完成"""
        self.info(f"步骤 {current}/{total}: 完成")
    
    def command(self, cmd: str):
        """记录执行的命令"""
        self.info(f"执行命令: {cmd}")
    
    def command_output(self, output: str, max_lines: int = 50):
        """记录命令输出
        
        Args:
            output: 命令输出
            max_lines: 最大记录行数，超过则截断
        """
        lines = output.strip().split('\n')
        if len(lines) > max_lines:
            self.info(f"命令输出 (显示前 {max_lines} 行，共 {len(lines)} 行):")
            for line in lines[:max_lines]:
                self._log("INFO", f"  | {line}")
            self._log("INFO", f"  | ... (省略 {len(lines) - max_lines} 行)")
        else:
            self.info("命令输出:")
            for line in lines:
                self._log("INFO", f"  | {line}")
    
    def _write_footer(self, result: str, reason: str = ""):
        """写入日志尾部"""
        end_time = datetime.now()
        duration = (end_time - self.start_time).total_seconds()
        
        separator = "=" * 50
        self._log("INFO", separator)
        self._log("INFO", f"{self.script_name} 脚本执行完成")
        self._log("INFO", separator)
        
        if reason:
            self._log("INFO" if result == "SUCCESS" else "ERROR", f"结果: {result} - {reason}")
        else:
            self._log("INFO" if result == "SUCCESS" else "ERROR", f"结果: {result}")
        
        self._log("INFO", f"耗时: {duration:.1f} 秒")
        self._log("INFO", f"日志文件: {self.log_file}")
    
    def success(self, message: str = ""):
        """记录脚本执行成功
        
        Args:
            message: 可选的成功消息
        """
        self._write_footer("SUCCESS", message)
    
    def failed(self, reason: str = ""):
        """记录脚本执行失败
        
        Args:
            reason: 失败原因
        """
        self._write_footer("FAILED", reason)
    
    def get_log_file(self) -> Path:
        """获取日志文件路径"""
        return self.log_file
    
    def get_latest_link(self) -> Path:
        """获取最新日志链接路径"""
        return self.latest_link


def get_latest_log(script_name: str, log_dir: Optional[Path] = None) -> Optional[Path]:
    """获取指定脚本的最新日志文件
    
    Args:
        script_name: 脚本名称
        log_dir: 日志目录，默认为项目根目录下的 logs/scripts/
    
    Returns:
        最新日志文件路径，如果不存在则返回 None
    """
    if log_dir is None:
        project_root = Path(__file__).parent.parent.parent
        log_dir = project_root / "logs" / "scripts"
    
    latest_link = log_dir / f"{script_name}_latest.log"
    
    if not latest_link.exists():
        return None
    
    if os.name == 'nt':
        # Windows: 读取文件内容获取实际日志文件名
        try:
            with open(latest_link, 'r', encoding='utf-8') as f:
                log_name = f.read().strip()
            return log_dir / log_name
        except Exception:
            return None
    else:
        # Unix: 符号链接直接指向日志文件
        if latest_link.is_symlink():
            return latest_link.resolve()
        return latest_link


def read_latest_log(script_name: str, log_dir: Optional[Path] = None) -> Optional[str]:
    """读取指定脚本的最新日志内容
    
    Args:
        script_name: 脚本名称
        log_dir: 日志目录
    
    Returns:
        日志内容，如果不存在则返回 None
    """
    log_file = get_latest_log(script_name, log_dir)
    if log_file and log_file.exists():
        return log_file.read_text(encoding='utf-8')
    return None


def check_script_result(script_name: str, log_dir: Optional[Path] = None) -> tuple[bool, str]:
    """检查脚本执行结果
    
    Args:
        script_name: 脚本名称
        log_dir: 日志目录
    
    Returns:
        (是否成功, 结果消息)
    """
    content = read_latest_log(script_name, log_dir)
    if content is None:
        return False, "日志文件不存在"
    
    # 查找结果行
    for line in reversed(content.split('\n')):
        if '结果: SUCCESS' in line:
            return True, line
        if '结果: FAILED' in line:
            return False, line
    
    return False, "未找到执行结果"


if __name__ == "__main__":
    # 测试日志功能
    logger = ScriptLogger("test")
    logger.info("这是一条信息日志")
    logger.warn("这是一条警告日志")
    logger.error("这是一条错误日志")
    logger.step(1, 3, "测试步骤")
    logger.step_done(1, 3)
    logger.command("echo hello")
    logger.command_output("hello\nworld")
    logger.success("测试完成")
    
    print(f"\n日志文件: {logger.get_log_file()}")
    print(f"最新链接: {logger.get_latest_link()}")
