/// 执行指令系统
///
/// 提供异步指令队列，用户发送指令后系统在合适时机执行
library;

/// 指令类型
enum CommandType {
  /// 暂停执行
  pause,
  
  /// 恢复执行
  resume,
  
  /// 取消执行（在下一个检查点生效）
  cancel,
  
  /// 跳过当前项
  skip,
  
  /// 提交用户输入
  submitInput,
}

/// 执行指令
class ExecutionCommand {
  /// 指令类型
  final CommandType type;
  
  /// 指令数据（如用户输入值）
  final dynamic data;
  
  /// 创建时间
  final DateTime createdAt;

  ExecutionCommand({
    required this.type,
    this.data,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 创建暂停指令
  factory ExecutionCommand.pause() => ExecutionCommand(type: CommandType.pause);

  /// 创建恢复指令
  factory ExecutionCommand.resume() => ExecutionCommand(type: CommandType.resume);

  /// 创建取消指令
  factory ExecutionCommand.cancel() => ExecutionCommand(type: CommandType.cancel);

  /// 创建跳过指令
  factory ExecutionCommand.skip() => ExecutionCommand(type: CommandType.skip);

  /// 创建提交输入指令
  factory ExecutionCommand.submitInput(String value) => 
      ExecutionCommand(type: CommandType.submitInput, data: value);

  @override
  String toString() => 'ExecutionCommand($type, data: $data)';
}

/// 指令队列
/// 
/// 用于接收和处理用户指令。指令不会立即执行，
/// 而是在执行引擎的检查点被处理。
class CommandQueue {
  final List<ExecutionCommand> _commands = [];
  
  /// 是否有待处理的指令
  bool get hasPending => _commands.isNotEmpty;
  
  /// 待处理指令数量
  int get pendingCount => _commands.length;
  
  /// 发送指令
  void send(ExecutionCommand command) {
    _commands.add(command);
  }
  
  /// 获取并移除下一个指令
  ExecutionCommand? poll() {
    if (_commands.isEmpty) return null;
    return _commands.removeAt(0);
  }
  
  /// 查看下一个指令（不移除）
  ExecutionCommand? peek() {
    if (_commands.isEmpty) return null;
    return _commands.first;
  }
  
  /// 检查是否有特定类型的指令
  bool hasCommand(CommandType type) {
    return _commands.any((c) => c.type == type);
  }
  
  /// 获取特定类型的指令（移除）
  ExecutionCommand? pollByType(CommandType type) {
    final index = _commands.indexWhere((c) => c.type == type);
    if (index == -1) return null;
    return _commands.removeAt(index);
  }
  
  /// 清空所有指令
  void clear() {
    _commands.clear();
  }
  
  /// 移除特定类型的所有指令
  void removeByType(CommandType type) {
    _commands.removeWhere((c) => c.type == type);
  }
}
