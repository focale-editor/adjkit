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

  group('black and white', () {
    test('reads and writes a .blw descriptor preset', () {
      final Uint8List bytes = AdjEncoder.encode(PsBlackAndWhite.create(red: 110, blue: -50, presetKind: 3));

      final AdjPresetFile preset = AdjDecoder.decode(bytes, kind: AdjPresetKind.fromExtension('blw')!);

      check(preset.kind).equals(AdjPresetKind.blackAndWhite);
      check(preset.warnings).isEmpty();
      final PsBlackAndWhite settings = preset.settings as PsBlackAndWhite;
      check([settings.red, settings.blue, settings.presetKind]).deepEquals([110, -50, 3]);
      check(AdjEncoder.encode(settings)).deepEquals(bytes);
    });

    test('flags contributions outside the dialog range and rejects truncated files', () {
      final Uint8List bytes = AdjEncoder.encode(PsBlackAndWhite.create(green: 400));

      check(AdjDecoder.decode(bytes, kind: AdjPresetKind.blackAndWhite).warnings).length.equals(1);
      check(() => AdjDecoder.decode(Uint8List.sublistView(bytes, 0, 30), kind: AdjPresetKind.blackAndWhite)).throws<AdjFormatException>();
    });
  });

  group('duotone', () {
    test('creates, writes, and reads back a duotone specification', () {
      final AdjDuotoneFile source = AdjDuotoneFile.create(
        inks: [
          AdjDuotoneInk.create(name: 'Black', color: PsColor.cmyk(cyan: 0, magenta: 0, yellow: 0, black: 100)),
          AdjDuotoneInk.create(name: 'Cyan', color: PsColor.cmyk(cyan: 100, magenta: 0, yellow: 0, black: 0), transfer: [0, -1, -1, -1, -1, -1, 500, -1, -1, -1, -1, -1, 800]),
        ],
      );

      final Uint8List bytes = AdjDuotoneEncoder.encode(source);
      final AdjDuotoneFile decoded = AdjDuotoneDecoder.decode(bytes, options: const AdjDecodeOptions(mode: AdjDecodeMode.strict));

      check(bytes).length.equals(524);
      check(decoded.inkCount).equals(2);
      check(decoded.activeInks.map((ink) => ink.name)).deepEquals(['Black', 'Cyan']);
      check(decoded.activeInks.first.color!.toRgb()!.red).isCloseTo(0, 0.5);
      check(decoded.activeInks.last.color!.toRgb()!.red).isCloseTo(0, 0.5);
      check(decoded.activeInks.last.color!.toRgb()!.blue).isCloseTo(255, 0.5);
      check(decoded.activeInks.last.outputAt(0.25)).isCloseTo(0.25, 1e-9);
      check(decoded.activeInks.last.outputAt(0.75)).isCloseTo(0.65, 1e-9);
      check(AdjDuotoneEncoder.encode(decoded)).deepEquals(bytes);
    });

    test('exposes the catalog code of a matching-system ink', () {
      final AdjDuotoneInk ink = AdjDuotoneInk(
        colorSpaceId: 3,
        components: const [0x2020, 0x3430, 0x3443, 0],
        nameField: Uint8List(AdjDuotoneInk.nameFieldBytes),
        transfer: const [0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 1000],
      );

      check(ink.color).isNull();
      check(ink.bookCode).equals('404C');
    });

    test('rejects truncated files and impossible ink counts', () {
      final Uint8List bytes = AdjDuotoneEncoder.encode(
        AdjDuotoneFile.create(
          inks: [AdjDuotoneInk.create(name: 'Black', color: PsColor.grayscale(gray: 100))],
        ),
      );
      final Uint8List fiveInks = Uint8List.fromList(bytes)..[3] = 5;

      check(() => AdjDuotoneDecoder.decode(Uint8List.sublistView(bytes, 0, 300))).throws<AdjFormatException>();
      check(() => AdjDuotoneDecoder.decode(fiveInks)).throws<AdjFormatException>();
    });
  });
}
