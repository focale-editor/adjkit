<p align="center">
  <img src="screenshots/overview.png" alt="AdjKit package illustration" width="180">
</p>

# AdjKit

AdjKit is a pure Dart codec for Adobe Photoshop adjustment presets: Levels (`.alv`), Hue/Saturation (`.ahu`), Selective Color (`.asv`), Channel Mixer (`.cha`), and Black & White (`.blw`), plus Duotone Options (`.ado`). It has no Flutter or native-code dependency.

## Supported data

- Levels (`.alv`) version 2 with 29 standard channel records and optional Photoshop CS extended records.
- Hue/Saturation (`.ahu`) version 2 with colorization, master settings, and six editable color ranges.
- Selective Color (`.asv`) version 1 with relative or absolute corrections and all ten records, including the reserved first record.
- Channel Mixer (`.cha`) version 1 with monochrome mode, four output rows, source-channel percentages, and constants.
- Black & White (`.blw`), a version 16 Action Descriptor with six colour contributions, the optional tint, and the preset kind; unknown descriptor items round-trip.
- Duotone Options (`.ado`) and duotone PSD color mode data: one to four inks with their colors or matching-system catalog codes, transfer curves, dot gain, and overprint colors, through `AdjDuotoneDecoder` and `AdjDuotoneEncoder`.
- Shared `PsLevels`, `PsHueSaturation`, `PsSelectiveColor`, `PsChannelMixer`, and `PsBlackAndWhite` settings from pscore.
- Strict and tolerant decoding with a configurable file-size limit, compatibility warnings, and retained trailing bytes.
- Encoding from settings and reusable `dart:convert` codecs and converters.

## Reading a file

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:adjkit/adjkit.dart';

final File file = File('Strong Contrast.alv');
final Uint8List bytes = await file.readAsBytes();
final AdjPresetFile preset = AdjDecoder.decode(
  bytes,
  kind: AdjPresetKind.levels,
);

if (preset.settings case PsLevels(:final List<PsLevelRecord> records)) {
  final PsLevelRecord composite = records.first;
  print('Input ${composite.inputFloor}–${composite.inputCeiling}, gamma ${composite.gammaValue}');
}

for (final AdjWarning warning in preset.warnings) {
  print(warning.message);
}
```

The files carry no signature, so the caller must choose the kind. `AdjPresetKind.fromExtension` accepts extensions with or without a leading dot, ignores case, and returns `null` for unsupported extensions.

## Writing a preset

```dart
final PsSelectiveColor settings = PsSelectiveColor(
  corrections: List.filled(
    PsSelectiveColor.correctionCount,
    const PsSelectiveColorCorrection(),
  ),
);

final Uint8List output = AdjEncoder.encode(settings);
await File('neutral.asv').writeAsBytes(output);
```

The settings type determines the output format. To save a decoded preset, pass `preset.settings` to `AdjEncoder.encode`. Encoding checks the required record counts and retains the model's version and trailing bytes; it does not apply the decoder's Photoshop dialog-range checks. Invalid record counts are reported through `AdjWriteException`.

## Reusable `dart:convert` API

`AdjCodec` implements `Codec<PsAdjustmentSettings, List<int>>` and keeps the expected input kind and decoding policy together:

```dart
const AdjCodec codec = AdjCodec(
  kind: AdjPresetKind.levels,
  decodeOptions: AdjDecodeOptions(mode: AdjDecodeMode.strict),
);

final PsAdjustmentSettings settings = codec.decode(bytes);
final Uint8List output = codec.encode(settings);
```

The codec returns settings directly. Use `AdjDecoder` when warnings are also needed. `kind` selects the layout for decoding; encoding always follows the actual settings type.

The `List<int>` binary type allows composition with standard codecs such as `base64`; direct `encode` calls still return `Uint8List`. `AdjEncoder` and `AdjDecoder` are also reusable `Converter` implementations. Each conversion consumes or produces one complete in-memory preset.

## Strict, tolerant, and bounded decoding

Tolerant decoding is the default. Unexpected main versions, trailing bytes, and out-of-range levels, master/range hue-saturation values, selective-color corrections, or channel-mixer values produce `AdjWarning` entries in `AdjPresetFile.warnings`.

Strict mode turns the first compatibility issue into an `AdjFormatException`:

```dart
final AdjPresetFile preset = AdjDecoder.decode(
  bytes,
  kind: AdjPresetKind.levels,
  options: const AdjDecodeOptions(mode: AdjDecodeMode.strict),
);
```

Truncated required fields and files exceeding `AdjDecodeOptions.maxFileBytes` always throw. The default file-size limit is 1 MiB.

The bundled example prints a preset summary and its warnings:

```console
dart run example/main.dart 'Strong Contrast.alv'
```

## Shared PSD settings

PsdKit's `PsdLevelsAdjustment`, `PsdHueSaturationAdjustment`, `PsdSelectiveColorAdjustment`, and `PsdChannelMixerAdjustment` extend the same PsCore settings types. Their settings can therefore be passed directly to `AdjEncoder.encode`. A host editor can use decoded preset settings when constructing its corresponding adjustment layer without translating to a second settings model.

## Scope

AdjKit reads and writes presets but does not apply adjustments to pixels. Curves presets (`.acv`) have their own layout and are handled by [AcvKit](https://pub.dev/packages/acvkit). Exposure and other undocumented preset layouts are not supported.

The layouts follow Adobe's specification and the shared PSD adjustment codec. Standalone Photoshop preset samples have not yet been used to verify compatibility; the Channel Mixer layout is derived from the PSD `mixr` block.

See [docs/ADJUSTMENTS.md](docs/ADJUSTMENTS.md) for the binary layouts, validation rules, encoding behavior, and integration guidance.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)

AdjKit is an independent implementation and is not affiliated with or endorsed by Adobe.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
