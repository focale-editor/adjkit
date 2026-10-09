import 'package:pscore/pscore.dart';

/// Controls whether recoverable preset issues stop decoding.
enum AdjDecodeMode {
  /// Rejects unexpected versions, out-of-range values, and trailing bytes.
  strict,

  /// Keeps such presets and reports each issue as a warning.
  tolerant,
}

/// Limits applied while decoding an adjustment preset.
final class AdjDecodeOptions {
  /// Handling policy for recoverable defects.
  final AdjDecodeMode mode;

  /// Maximum accepted input size.
  final int maxFileBytes;

  /// Creates decode options suitable for untrusted input.
  const AdjDecodeOptions({
    this.mode = AdjDecodeMode.tolerant,
    this.maxFileBytes = 1024 * 1024,
  });
}

/// Describes a recoverable issue found while decoding.
final class AdjWarning extends PsWarning {
  /// Creates a warning at an optional byte [offset].
  const AdjWarning({
    required super.message,
    super.offset,
  });

  @override
  String get typeName => 'AdjWarning';

  @override
  String get context => '';
}

/// Reports malformed, truncated, or unsafe preset input.
final class AdjFormatException extends PsFormatException {
  /// Creates an error at an optional absolute byte [offset].
  const AdjFormatException({
    required super.message,
    super.source,
    super.offset,
  });

  @override
  String get typeName => 'AdjFormatException';
}

/// Reports settings that cannot be written as a preset.
final class AdjWriteException extends PsWriteException {
  /// Creates an encoding error with a user-facing [message].
  const AdjWriteException({
    required super.message,
  });

  @override
  String get typeName => 'AdjWriteException';
}
