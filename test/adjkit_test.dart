import 'dart:typed_data';

import 'package:adjkit/adjkit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Exercises adjustment preset decoding, validation, and encoding.
void main() {
  group('AdjPresetKind', () {
    test('maps extensions and settings to kinds', () {
      check(AdjPresetKind.fromExtension('.ALV')).equals(AdjPresetKind.levels);
      check(AdjPresetKind.fromExtension('cha')).equals(AdjPresetKind.channelMixer);
      check(AdjPresetKind.fromExtension('acv')).isNull();
      check(AdjPresetKind.of(PsLevels.identity())).equals(AdjPresetKind.levels);
    });
  });

  group('round trips', () {
    test('writes the documented preset sizes and reads them back', () {
      final Map<AdjPresetKind, (PsAdjustmentSettings, int)> presets = {
        AdjPresetKind.levels: (PsLevels.identity(), 292),
        AdjPresetKind.hueSaturation: (
          PsHueSaturation(
            master: const PsHueSaturationValues(hue: -20),
            ranges: List.filled(6, const PsHueSaturationRange(boundaries: [315, 345, 15, 45])),
          ),
          100,
        ),
        AdjPresetKind.selectiveColor: (PsSelectiveColor(corrections: List.filled(10, const PsSelectiveColorCorrection(cyan: 15))), 84),
        AdjPresetKind.channelMixer: (PsChannelMixer(outputs: List.filled(4, const PsChannelMixerOutput(channels: [100, 0, 0, 0]))), 44),
      };

      for (final MapEntry<AdjPresetKind, (PsAdjustmentSettings, int)> entry in presets.entries) {
        final Uint8List bytes = const AdjEncoder().convert(entry.value.$1);
        final AdjPresetFile file = AdjDecoder.decode(
          bytes,
          kind: entry.key,
          options: const AdjDecodeOptions(mode: AdjDecodeMode.strict),
        );

        check(because: entry.key.name, bytes.length).equals(entry.value.$2);
        check(file.kind).equals(entry.key);
        check(file.warnings).isEmpty();
        check(AdjEncoder.encode(file.settings)).deepEquals(bytes);
      }
    });

    test('decodes through the dart:convert codec', () {
      const AdjCodec codec = AdjCodec(kind: AdjPresetKind.hueSaturation);
      final PsHueSaturation source = PsHueSaturation(
        colorize: true,
        colorization: const PsHueSaturationValues(hue: 200, saturation: 40),
        ranges: List.filled(6, const PsHueSaturationRange(boundaries: [0, 0, 0, 0])),
      );

      final PsAdjustmentSettings decoded = codec.decode(codec.encode(source));

      check(decoded).isA<PsHueSaturation>().has((settings) => settings.colorization.hue, 'hue').equals(200);
    });
  });

  group('validation', () {
    test('reports unexpected versions, ranges, and trailing bytes', () {
      final Uint8List levels = AdjEncoder.encode(PsLevels(version: 3, records: List.filled(29, const PsLevelRecord(gamma: 5)), trailingData: Uint8List(2)));

      final AdjPresetFile file = AdjDecoder.decode(levels, kind: AdjPresetKind.levels);

      check(file.warnings.map((warning) => warning.message).toList()).deepEquals([
        'ALV version 3 is not 2',
        '2 unrecognized trailing bytes follow the ALV settings',
        'A levels record holds values outside the Photoshop ranges',
      ]);
      check(
        () => AdjDecoder.decode(
          levels,
          kind: AdjPresetKind.levels,
          options: const AdjDecodeOptions(mode: AdjDecodeMode.strict),
        ),
      ).throws<AdjFormatException>();
    });

    test('flags out-of-range corrections and mixer values', () {
      final Uint8List selective = AdjEncoder.encode(PsSelectiveColor(corrections: List.filled(10, const PsSelectiveColorCorrection(black: 150))));
      final Uint8List mixer = AdjEncoder.encode(PsChannelMixer(outputs: List.filled(4, const PsChannelMixerOutput(channels: [300, 0, 0, 0]))));

      check(AdjDecoder.decode(selective, kind: AdjPresetKind.selectiveColor).warnings).length.equals(1);
      check(AdjDecoder.decode(mixer, kind: AdjPresetKind.channelMixer).warnings).length.equals(1);
    });

    test('rejects truncated, oversized, and unwritable presets', () {
      check(() => AdjDecoder.decode(Uint8List(20), kind: AdjPresetKind.levels)).throws<AdjFormatException>();
      check(() => AdjDecoder.decode(Uint8List(100), kind: AdjPresetKind.hueSaturation, options: const AdjDecodeOptions(maxFileBytes: 50))).throws<AdjFormatException>();
      check(() => AdjEncoder.encode(PsSelectiveColor(corrections: const []))).throws<AdjWriteException>();
    });
  });
}
