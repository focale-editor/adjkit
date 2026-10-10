import 'dart:convert';
import 'dart:typed_data';

import 'package:adjkit/src/model/adj_options.dart';
import 'package:adjkit/src/model/adj_preset.dart';
import 'package:pscore/pscore.dart';

/// Decodes Photoshop `.alv`, `.ahu`, `.asv`, `.cha`, and `.blw` adjustment presets.
///
/// These files carry no signature, so the caller selects the [kind], usually
/// from the file extension with [AdjPresetKind.fromExtension].
final class AdjDecoder extends Converter<List<int>, AdjPresetFile> {
  /// Adjustment expected in the decoded files.
  final AdjPresetKind kind;

  /// Options applied by [convert].
  final AdjDecodeOptions options;

  /// Creates a reusable decoder for [kind].
  const AdjDecoder({required this.kind, this.options = const AdjDecodeOptions()});

  @override
  AdjPresetFile convert(List<int> input) => decode(input is Uint8List ? input : Uint8List.fromList(input), kind: kind, options: options);

  /// Decodes one complete preset of [kind].
  static AdjPresetFile decode(
    Uint8List bytes, {
    required AdjPresetKind kind,
    AdjDecodeOptions options = const AdjDecodeOptions(),
  }) {
    if (bytes.length > options.maxFileBytes) {
      throw AdjFormatException(message: '${kind.extension.toUpperCase()} file size ${bytes.length} exceeds the configured ${options.maxFileBytes} byte limit', source: bytes, offset: 0);
    }
    final PsAdjustmentSettings settings;
    try {
      final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
      settings = switch (kind) {
        AdjPresetKind.levels => PsAdjustmentSettingsCodec.readLevels(reader),
        AdjPresetKind.hueSaturation => PsAdjustmentSettingsCodec.readHueSaturation(reader),
        AdjPresetKind.selectiveColor => PsAdjustmentSettingsCodec.readSelectiveColor(reader),
        AdjPresetKind.channelMixer => PsAdjustmentSettingsCodec.readChannelMixer(reader),
        AdjPresetKind.blackAndWhite => PsAdjustmentSettingsCodec.readBlackAndWhite(reader),
      };
    } on PsFormatException catch (error) {
      throw AdjFormatException(message: 'Truncated ${kind.extension.toUpperCase()} preset: ${error.message}', source: bytes, offset: error.offset);
    } on RangeError catch (error) {
      throw AdjFormatException(message: 'Truncated ${kind.extension.toUpperCase()} preset: $error', source: bytes);
    }
    final List<AdjWarning> warnings = [];
    for (final String issue in _issues(settings, kind)) {
      if (options.mode == AdjDecodeMode.strict) {
        throw AdjFormatException(message: issue, source: bytes);
      }
      warnings.add(AdjWarning(message: issue));
    }
    return AdjPresetFile(settings: settings, warnings: warnings);
  }

  /// Lists the values Photoshop would not have written for [kind].
  static List<String> _issues(PsAdjustmentSettings settings, AdjPresetKind kind) {
    final (int version, Uint8List trailingData) = switch (settings) {
      PsLevels(:final int version, :final Uint8List trailingData) => (version, trailingData),
      PsHueSaturation(:final int version, :final Uint8List trailingData) => (version, trailingData),
      PsSelectiveColor(:final int version, :final Uint8List trailingData) => (version, trailingData),
      PsChannelMixer(:final int version, :final Uint8List trailingData) => (version, trailingData),
      PsBlackAndWhite(:final int version, :final Uint8List trailingData) => (version, trailingData),
    };
    bool outside(Iterable<int> values, int minimum, int maximum) => values.any((value) => value < minimum || value > maximum);
    return [
      if (version != kind.version) '${kind.extension.toUpperCase()} version $version is not ${kind.version}',
      if (trailingData.isNotEmpty) '${trailingData.length} unrecognized trailing bytes follow the ${kind.extension.toUpperCase()} settings',
      ...switch (settings) {
        PsLevels(:final List<PsLevelRecord> records, :final List<PsLevelRecord> extendedRecords) => [
          for (final PsLevelRecord record in [...records, ...extendedRecords])
            if (outside([record.inputFloor, record.inputCeiling, record.outputFloor, record.outputCeiling], 0, 255) ||
                record.inputFloor >= record.inputCeiling ||
                record.gamma < 10 ||
                record.gamma > 999)
              'A levels record holds values outside the Photoshop ranges',
        ].take(1),
        PsHueSaturation(:final PsHueSaturationValues master, :final List<PsHueSaturationRange> ranges) => [
          if (outside([master.hue, for (final PsHueSaturationRange range in ranges) range.values.hue], -180, 180) ||
              outside(
                [
                  master.saturation,
                  master.lightness,
                  for (final PsHueSaturationRange range in ranges) ...[range.values.saturation, range.values.lightness],
                ],
                -100,
                100,
              ))
            'Hue/saturation values lie outside the Photoshop ranges',
        ],
        PsSelectiveColor(:final List<PsSelectiveColorCorrection> corrections) => [
          if (outside(
            [
              for (final PsSelectiveColorCorrection correction in corrections) ...[correction.cyan, correction.magenta, correction.yellow, correction.black],
            ],
            -100,
            100,
          ))
            'Selective color corrections lie outside the −100–100 range',
        ],
        PsChannelMixer(:final List<PsChannelMixerOutput> outputs) => [
          if (outside(
            [
              for (final PsChannelMixerOutput output in outputs) ...[...output.channels, output.constant],
            ],
            -200,
            200,
          ))
            'Channel mixer values lie outside the −200–200 range',
        ],
        PsBlackAndWhite(:final int red, :final int yellow, :final int green, :final int cyan, :final int blue, :final int magenta) => [
          if (outside([red, yellow, green, cyan, blue, magenta], -200, 300)) 'Black and white contributions lie outside the −200–300 range',
        ],
      },
    ];
  }
}

/// Encodes Photoshop adjustment presets.
final class AdjEncoder extends Converter<PsAdjustmentSettings, List<int>> {
  /// Creates a reusable encoder.
  const AdjEncoder();

  @override
  Uint8List convert(PsAdjustmentSettings input) => encode(input);

  /// Encodes [settings] in the preset layout of their kind.
  ///
  /// PSD adjustment layers such as `PsdLevelsAdjustment` are accepted
  /// directly, since they extend the shared settings types.
  static Uint8List encode(PsAdjustmentSettings settings) {
    try {
      return PsAdjustmentSettingsCodec.encode(settings);
    } on PsWriteException catch (error) {
      throw AdjWriteException(message: error.message);
    }
  }
}

/// Converts adjustment presets of one [kind] to and from bytes.
final class AdjCodec extends Codec<PsAdjustmentSettings, List<int>> {
  /// Adjustment expected when decoding.
  final AdjPresetKind kind;

  /// Options applied while decoding.
  final AdjDecodeOptions decodeOptions;

  /// Creates a reusable codec for [kind].
  const AdjCodec({required this.kind, this.decodeOptions = const AdjDecodeOptions()});

  @override
  Converter<List<int>, PsAdjustmentSettings> get decoder => _AdjSettingsDecoder(AdjDecoder(kind: kind, options: decodeOptions));

  @override
  AdjEncoder get encoder => const AdjEncoder();

  @override
  Uint8List encode(PsAdjustmentSettings input) => AdjEncoder.encode(input);
}

/// Adapts [AdjDecoder] to return the decoded settings only.
final class _AdjSettingsDecoder extends Converter<List<int>, PsAdjustmentSettings> {
  /// Decoder producing complete preset files.
  final AdjDecoder _decoder;

  /// Creates an adapter around [_decoder].
  const _AdjSettingsDecoder(this._decoder);

  @override
  PsAdjustmentSettings convert(List<int> input) => _decoder.convert(input).settings;
}
