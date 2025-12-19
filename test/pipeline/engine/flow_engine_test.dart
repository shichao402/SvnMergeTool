import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SvnMergeTool/pipeline/data/data.dart';
import 'package:SvnMergeTool/pipeline/engine/new_engine.dart';
import 'package:SvnMergeTool/pipeline/registry/registry.dart';

void main() {
  group('FlowEngine', () {
    late NodeTypeRegistry registry;

    setUp(() {
      registry = NodeTypeRegistry.instance;
      registry.clear();

      // 注册测试用节点类型
      registry.register(NodeTypeDefinition(
        typeId: 'start',
        name: 'Start',
        icon: Icons.play_arrow,
        inputs: [],
        outputs: [PortSpec(id: 'success', name: 'Success', direction: PortDirection.output)],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      ));

      registry.register(NodeTypeDefinition(
        typeId: 'process',
        name: 'Process',
        icon: Icons.settings,
        inputs: [PortSpec(id: 'in', name: 'Input', direction: PortDirection.input)],
        outputs: [
          PortSpec(id: 'success', name: 'Success', direction: PortDirection.output),
          PortSpec(id: 'failure', name: 'Failure', direction: PortDirection.output, role: PortRole.error),
        ],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async {
          final shouldFail = config['fail'] == true;
          return shouldFail ? NodeOutput.failure() : NodeOutput.success();
        },
      ));

      registry.register(NodeTypeDefinition(
        typeId: 'end',
        name: 'End',
        icon: Icons.stop,
        inputs: [PortSpec(id: 'in', name: 'Input', direction: PortDirection.input)],
        outputs: [],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      ));
    });

    tearDown(() {
      registry.clear();
    });

    // 注意: 完整的 FlowEngine 测试需要 mock MergeJob 和 SvnService
    // 这里只测试基本的图加载和验证功能

    test('should load graph', () {
      final graph = FlowGraphData(
        nodes: [
          NodeData(id: 'start', typeId: 'start', x: 0, y: 0),
          NodeData(id: 'end', typeId: 'end', x: 200, y: 0),
        ],
        connections: [
          ConnectionData(
            id: 'c1',
            sourceNodeId: 'start',
            sourcePortId: 'success',
            targetNodeId: 'end',
            targetPortId: 'in',
          ),
        ],
      );

      final engine = FlowEngine();
      engine.loadGraph(graph);

      expect(engine.isRunning, isFalse);
      expect(engine.currentNodeId, isNull);
    });

    test('should emit events through stream', () async {
      final engine = FlowEngine();
      
      final events = <ExecutionEvent>[];
      engine.events.listen((event) {
        events.add(event);
      });

      // 事件流应该是广播流
      expect(engine.events.isBroadcast, isTrue);
      
      engine.dispose();
    });
  });

  group('NodeOutput', () {
    test('should create success output', () {
      final output = NodeOutput.success();
      expect(output.port, 'success');
      expect(output.isSuccess, isTrue);
      expect(output.data, isEmpty);
    });

    test('should create success output with data', () {
      final output = NodeOutput.success(data: {'result': 'value'});
      expect(output.port, 'success');
      expect(output.data['result'], 'value');
    });

    test('should create failure output', () {
      final output = NodeOutput.failure();
      expect(output.port, 'failure');
      expect(output.isSuccess, isFalse);
    });

    test('should create failure output with message', () {
      final output = NodeOutput.failure(message: 'Error occurred');
      expect(output.port, 'failure');
      expect(output.message, 'Error occurred');
    });

    test('should create custom port output', () {
      final output = NodeOutput.port('custom_port');
      expect(output.port, 'custom_port');
    });

    test('should create custom port output with data', () {
      final output = NodeOutput.port('custom', data: {'key': 'value'});
      expect(output.port, 'custom');
      expect(output.data['key'], 'value');
    });

    test('should create cancelled output', () {
      final output = NodeOutput.cancelled();
      expect(output.isCancelled, isTrue);
    });
  });

  group('ExecutionCancelledException', () {
    test('should create with default message', () {
      final exception = ExecutionCancelledException();
      expect(exception.message, '执行已取消');
    });

    test('should create with custom message', () {
      final exception = ExecutionCancelledException('Custom cancel message');
      expect(exception.message, 'Custom cancel message');
    });

    test('should have string representation', () {
      final exception = ExecutionCancelledException('Test');
      expect(exception.toString(), contains('Test'));
    });
  });
}
