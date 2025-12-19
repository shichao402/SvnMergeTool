import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SvnMergeTool/pipeline/engine/new_engine.dart';
import 'package:SvnMergeTool/pipeline/registry/registry.dart';

void main() {
  group('NodeTypeRegistry', () {
    late NodeTypeRegistry registry;

    setUp(() {
      registry = NodeTypeRegistry.instance;
      registry.clear();
    });

    tearDown(() {
      registry.clear();
    });

    test('should register and retrieve node type', () {
      final definition = NodeTypeDefinition(
        typeId: 'test_type',
        name: 'Test Node',
        icon: Icons.star,
        inputs: [PortSpec(id: 'in', name: 'Input', direction: PortDirection.input)],
        outputs: [PortSpec(id: 'out', name: 'Output', direction: PortDirection.output)],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      );

      registry.register(definition);

      final retrieved = registry.get('test_type');
      expect(retrieved, isNotNull);
      expect(retrieved!.typeId, 'test_type');
      expect(retrieved.name, 'Test Node');
    });

    test('should return null for unregistered type', () {
      final result = registry.get('non_existent');
      expect(result, isNull);
    });

    test('should check if type exists', () {
      final definition = NodeTypeDefinition(
        typeId: 'exists',
        name: 'Exists',
        icon: Icons.check,
        inputs: [],
        outputs: [],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      );

      expect(registry.contains('exists'), isFalse);
      registry.register(definition);
      expect(registry.contains('exists'), isTrue);
    });

    test('should list all registered types', () {
      registry.register(NodeTypeDefinition(
        typeId: 'type1',
        name: 'Type 1',
        icon: Icons.one_k,
        inputs: [],
        outputs: [],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      ));

      registry.register(NodeTypeDefinition(
        typeId: 'type2',
        name: 'Type 2',
        icon: Icons.two_k,
        inputs: [],
        outputs: [],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      ));

      final all = registry.definitions.toList();
      expect(all.length, 2);
      expect(all.map((d) => d.typeId).toSet(), {'type1', 'type2'});
    });

    test('should unregister type', () {
      registry.register(NodeTypeDefinition(
        typeId: 'to_remove',
        name: 'To Remove',
        icon: Icons.delete,
        inputs: [],
        outputs: [],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      ));

      expect(registry.contains('to_remove'), isTrue);
      registry.unregister('to_remove');
      expect(registry.contains('to_remove'), isFalse);
    });

    test('should clear all types', () {
      registry.register(NodeTypeDefinition(
        typeId: 'type1',
        name: 'Type 1',
        icon: Icons.one_k,
        inputs: [],
        outputs: [],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      ));

      registry.register(NodeTypeDefinition(
        typeId: 'type2',
        name: 'Type 2',
        icon: Icons.two_k,
        inputs: [],
        outputs: [],
        params: [],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      ));

      expect(registry.definitions.length, 2);
      registry.clear();
      expect(registry.definitions, isEmpty);
    });
  });

  group('NodeTypeDefinition', () {
    test('should create definition with all fields', () {
      final definition = NodeTypeDefinition(
        typeId: 'custom',
        name: 'Custom Node',
        icon: Icons.build,
        category: 'Tools',
        description: 'A custom node',
        inputs: [
          PortSpec(id: 'in', name: 'Input', direction: PortDirection.input),
        ],
        outputs: [
          PortSpec(id: 'success', name: 'Success', direction: PortDirection.output),
          PortSpec(id: 'failure', name: 'Failure', direction: PortDirection.output, role: PortRole.error),
        ],
        params: [
          ParamSpec(key: 'param1', label: 'Parameter 1', type: ParamType.string, defaultValue: 'default'),
        ],
        executor: ({
          required Map<String, dynamic> input,
          required Map<String, dynamic> config,
          required ExecutionContext context,
        }) async => NodeOutput.success(),
      );

      expect(definition.typeId, 'custom');
      expect(definition.name, 'Custom Node');
      expect(definition.category, 'Tools');
      expect(definition.description, 'A custom node');
      expect(definition.inputs.length, 1);
      expect(definition.outputs.length, 2);
      expect(definition.params.length, 1);
    });
  });

  group('PortSpec', () {
    test('should create input port', () {
      final port = PortSpec(
        id: 'in',
        name: 'Input',
        direction: PortDirection.input,
      );

      expect(port.id, 'in');
      expect(port.name, 'Input');
      expect(port.direction, PortDirection.input);
      expect(port.role, PortRole.data);  // default role
    });

    test('should create output port with error role', () {
      final port = PortSpec(
        id: 'error',
        name: 'Error',
        direction: PortDirection.output,
        role: PortRole.error,
      );

      expect(port.direction, PortDirection.output);
      expect(port.role, PortRole.error);
    });

    test('should use predefined ports', () {
      expect(PortSpec.defaultInput.id, 'in');
      expect(PortSpec.success.id, 'success');
      expect(PortSpec.failure.id, 'failure');
      expect(PortSpec.failure.role, PortRole.error);
    });
  });

  group('ParamSpec', () {
    test('should create string param', () {
      final param = ParamSpec(
        key: 'name',
        label: 'Name',
        type: ParamType.string,
        defaultValue: 'default',
        required: true,
      );

      expect(param.key, 'name');
      expect(param.type, ParamType.string);
      expect(param.defaultValue, 'default');
      expect(param.required, isTrue);
    });

    test('should create select param with options', () {
      final param = ParamSpec(
        key: 'choice',
        label: 'Choice',
        type: ParamType.select,
        options: [
          SelectOption(value: 'option1', label: 'Option 1'),
          SelectOption(value: 'option2', label: 'Option 2'),
          SelectOption(value: 'option3', label: 'Option 3'),
        ],
        defaultValue: 'option1',
      );

      expect(param.type, ParamType.select);
      expect(param.options?.length, 3);
    });

    test('should validate required param', () {
      final param = ParamSpec(
        key: 'required_field',
        label: 'Required Field',
        type: ParamType.string,
        required: true,
      );

      final emptyResult = param.validate(null);
      expect(emptyResult.isValid, isFalse);

      final validResult = param.validate('some value');
      expect(validResult.isValid, isTrue);
    });

    test('should validate int param with range', () {
      final param = ParamSpec(
        key: 'count',
        label: 'Count',
        type: ParamType.int,
        min: 0,
        max: 100,
      );

      expect(param.validate(-1).isValid, isFalse);
      expect(param.validate(50).isValid, isTrue);
      expect(param.validate(101).isValid, isFalse);
    });
  });
}
