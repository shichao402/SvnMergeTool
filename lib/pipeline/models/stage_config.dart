import 'capture_mode.dart';
import 'stage_type.dart';

class ReviewInputConfig {
  final String label;
  final String? hint;
  final String? validationRegex;
  final bool required;

  const ReviewInputConfig({
    required this.label,
    this.hint,
    this.validationRegex,
    this.required = true,
  });
}

class StageConfig {
  final String id;
  final StageType type;
  final String name;
  final String? script;
  final List<String>? scriptArgs;
  final CaptureMode captureMode;
  final bool enabled;
  final int timeoutSeconds;
  final ReviewInputConfig? reviewInput;
  final String? commitMessageTemplate;

  const StageConfig({
    required this.id,
    required this.type,
    required this.name,
    this.script,
    this.scriptArgs,
    this.captureMode = CaptureMode.none,
    this.enabled = true,
    this.timeoutSeconds = 0,
    this.reviewInput,
    this.commitMessageTemplate,
  });
}
