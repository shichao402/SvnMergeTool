import 'package:flutter_test/flutter_test.dart';
import 'package:SvnMergeTool/pipeline/data/data.dart';

void main() {
  group('FlowGraphData', () {
    test('should create empty graph', () {
      const graph = FlowGraphData();
      expect(graph.nodes, isEmpty);
      expect(graph.connections, isEmpty);
    });

    test('should serialize to JSON', () {
      final graph = FlowGraphData(
        nodes: [
          NodeData(id: 'node1', typeId: 'prepare', x: 100, y: 200),
          NodeData(id: 'node2', typeId: 'merge', x: 300, y: 200, config: {'key': 'value'}),
        ],
        connections: [
          ConnectionData(
            id: 'conn1',
            sourceNodeId: 'node1',
            sourcePortId: 'success',
            targetNodeId: 'node2',
            targetPortId: 'in',
          ),
        ],
        metadata: {'version': '1.0'},
      );

      final json = graph.toJson();

      expect(json['nodes'], isA<List>());
      expect(json['nodes'].length, 2);
      expect(json['connections'], isA<List>());
      expect(json['connections'].length, 1);
      expect(json['metadata']['version'], '1.0');
    });

    test('should deserialize from JSON', () {
      final json = {
        'nodes': [
          {'id': 'node1', 'typeId': 'prepare', 'x': 100.0, 'y': 200.0, 'config': {}},
          {'id': 'node2', 'typeId': 'merge', 'x': 300.0, 'y': 200.0, 'config': {'key': 'value'}},
        ],
        'connections': [
          {
            'id': 'conn1',
            'sourceNodeId': 'node1',
            'sourcePortId': 'success',
            'targetNodeId': 'node2',
            'targetPortId': 'in',
          },
        ],
        'metadata': {'version': '1.0'},
      };

      final graph = FlowGraphData.fromJson(json);

      expect(graph.nodes.length, 2);
      expect(graph.nodes[0].id, 'node1');
      expect(graph.nodes[0].typeId, 'prepare');
      expect(graph.nodes[1].config['key'], 'value');
      expect(graph.connections.length, 1);
      expect(graph.connections[0].sourceNodeId, 'node1');
      expect(graph.metadata?['version'], '1.0');
    });

    test('should round-trip serialize correctly', () {
      final original = FlowGraphData(
        nodes: [
          NodeData(id: 'n1', typeId: 'type1', x: 10, y: 20, config: {'nested': {'a': 1}}),
        ],
        connections: [
          ConnectionData(
            id: 'c1',
            sourceNodeId: 'n1',
            sourcePortId: 'out',
            targetNodeId: 'n2',
            targetPortId: 'in',
          ),
        ],
        metadata: {'key': 'value'},
      );

      final json = original.toJson();
      final restored = FlowGraphData.fromJson(json);

      expect(restored.nodes.length, original.nodes.length);
      expect(restored.nodes[0].id, original.nodes[0].id);
      expect(restored.nodes[0].config['nested']['a'], 1);
      expect(restored.connections.length, original.connections.length);
      expect(restored.metadata?['key'], 'value');
    });

    test('should find entry nodes', () {
      final graph = FlowGraphData(
        nodes: [
          NodeData(id: 'start', typeId: 'start', x: 0, y: 0),
          NodeData(id: 'middle', typeId: 'process', x: 100, y: 0),
          NodeData(id: 'end', typeId: 'end', x: 200, y: 0),
        ],
        connections: [
          ConnectionData(
            id: 'c1',
            sourceNodeId: 'start',
            sourcePortId: 'out',
            targetNodeId: 'middle',
            targetPortId: 'in',
          ),
          ConnectionData(
            id: 'c2',
            sourceNodeId: 'middle',
            sourcePortId: 'out',
            targetNodeId: 'end',
            targetPortId: 'in',
          ),
        ],
      );

      final entryNodes = graph.findEntryNodes();
      expect(entryNodes.length, 1);
      expect(entryNodes[0].id, 'start');
    });

    test('should find exit nodes', () {
      final graph = FlowGraphData(
        nodes: [
          NodeData(id: 'start', typeId: 'start', x: 0, y: 0),
          NodeData(id: 'end', typeId: 'end', x: 100, y: 0),
        ],
        connections: [
          ConnectionData(
            id: 'c1',
            sourceNodeId: 'start',
            sourcePortId: 'out',
            targetNodeId: 'end',
            targetPortId: 'in',
          ),
        ],
      );

      final exitNodes = graph.findExitNodes();
      expect(exitNodes.length, 1);
      expect(exitNodes[0].id, 'end');
    });

    test('should validate graph', () {
      final validGraph = FlowGraphData(
        nodes: [
          NodeData(id: 'n1', typeId: 't1', x: 0, y: 0),
        ],
        connections: [],
      );

      final result = validGraph.validate();
      expect(result.isValid, isTrue);
    });

    test('should detect invalid connections', () {
      final invalidGraph = FlowGraphData(
        nodes: [
          NodeData(id: 'n1', typeId: 't1', x: 0, y: 0),
        ],
        connections: [
          ConnectionData(
            id: 'c1',
            sourceNodeId: 'n1',
            sourcePortId: 'out',
            targetNodeId: 'nonexistent',
            targetPortId: 'in',
          ),
        ],
      );

      final result = invalidGraph.validate();
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('nonexistent')), isTrue);
    });
  });

  group('NodeData', () {
    test('should create with default config', () {
      final node = NodeData(id: 'n1', typeId: 't1', x: 0, y: 0);
      expect(node.config, isEmpty);
    });

    test('should serialize to JSON', () {
      final node = NodeData(
        id: 'n1',
        typeId: 't1',
        x: 100.5,
        y: 200.5,
        config: {'param1': 'value1'},
      );

      final json = node.toJson();

      expect(json['id'], 'n1');
      expect(json['typeId'], 't1');
      expect(json['x'], 100.5);
      expect(json['y'], 200.5);
      expect(json['config']['param1'], 'value1');
    });

    test('should deserialize from JSON', () {
      final json = {
        'id': 'n1',
        'typeId': 't1',
        'x': 100.5,
        'y': 200.5,
        'config': {'param1': 'value1'},
      };

      final node = NodeData.fromJson(json);

      expect(node.id, 'n1');
      expect(node.typeId, 't1');
      expect(node.x, 100.5);
      expect(node.y, 200.5);
      expect(node.config['param1'], 'value1');
    });

    test('should copyWith correctly', () {
      final original = NodeData(id: 'n1', typeId: 't1', x: 100, y: 200);
      final copied = original.copyWith(x: 150, config: {'new': 'config'});

      expect(copied.id, 'n1');
      expect(copied.typeId, 't1');
      expect(copied.x, 150);
      expect(copied.y, 200);
      expect(copied.config['new'], 'config');
    });
  });

  group('ConnectionData', () {
    test('should serialize to JSON', () {
      final conn = ConnectionData(
        id: 'c1',
        sourceNodeId: 'n1',
        sourcePortId: 'out',
        targetNodeId: 'n2',
        targetPortId: 'in',
      );

      final json = conn.toJson();

      expect(json['id'], 'c1');
      expect(json['sourceNodeId'], 'n1');
      expect(json['sourcePortId'], 'out');
      expect(json['targetNodeId'], 'n2');
      expect(json['targetPortId'], 'in');
    });

    test('should deserialize from JSON', () {
      final json = {
        'id': 'c1',
        'sourceNodeId': 'n1',
        'sourcePortId': 'out',
        'targetNodeId': 'n2',
        'targetPortId': 'in',
      };

      final conn = ConnectionData.fromJson(json);

      expect(conn.id, 'c1');
      expect(conn.sourceNodeId, 'n1');
      expect(conn.sourcePortId, 'out');
      expect(conn.targetNodeId, 'n2');
      expect(conn.targetPortId, 'in');
    });
  });
}
