import 'package:adjkit/src/model/adj_options.dart';
import 'package:pscore/pscore.dart';

/// Identifies the adjustment saved in a Photoshop preset file.
enum AdjPresetKind {
  /// Levels, saved as `.alv`.
  levels('alv', 2),

  /// Hue/Saturation, saved as `.ahu`.
  hueSaturation('ahu', 2),

  /// Selective Color, saved as `.asv`.
  selectiveColor('asv', 1),

  /// Channel Mixer, saved as `.cha`.
  channelMixer('cha', 1);

  /// File extension without a leading dot.
  final String extension;

  /// Version Photoshop writes for this kind.
  final int version;

  /// Creates a kind saved with [extension] and [version].
  const AdjPresetKind(this.extension, this.version);

  /// Returns the kind saved with [extension], ignoring case and a leading dot.
  static AdjPresetKind? fromExtension(String extension) {
    final String normalized = extension.toLowerCase().replaceFirst('.', '');
    return values.where((kind) => kind.extension == normalized).firstOrNull;
  }

  /// Returns the kind that stores [settings].
  static AdjPresetKind of(PsAdjustmentSettings settings) => switch (settings) {
    PsLevels() => levels,
    PsHueSaturation() => hueSaturation,
    PsSelectiveColor() => selectiveColor,
    PsChannelMixer() => channelMixer,
  };
}

/// One decoded Photoshop adjustment preset.
final class AdjPresetFile {
  /// Decoded settings: a [PsLevels], [PsHueSaturation], [PsSelectiveColor], or [PsChannelMixer].
  final PsAdjustmentSettings settings;

  /// Recoverable issues encountered while decoding.
  final List<AdjWarning> warnings;

  /// Creates a decoded preset.
  AdjPresetFile({
    required this.settings,
    List<AdjWarning> warnings = const [],
  }) : warnings = List<AdjWarning>.unmodifiable(warnings);

  /// Adjustment saved in this preset.
  AdjPresetKind get kind => AdjPresetKind.of(settings);
}
