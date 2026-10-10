# Adobe Photoshop adjustment preset support

This document describes the binary layouts implemented by AdjKit, the shared PsCore settings models, and the boundaries of validation and reconstruction.

## Format selection

Adobe's specification states that adjustment-layer data matches the load file of each adjustment. AdjKit delegates those layouts to `PsAdjustmentSettingsCodec`, which is also used for the corresponding PSD adjustment blocks.

The files have no identifying signature. Callers select an `AdjPresetKind`, usually from the extension with `AdjPresetKind.fromExtension`. All multibyte values are big-endian; versions and counts are unsigned 16-bit integers, except the Black & White descriptor version, which is 32-bit.

| Kind | Extension | PSD key | Main version | Base size | Settings model |
| --- | --- | --- | ---: | ---: | --- |
| Levels | `.alv` | `levl` | 2 | 292 bytes | `PsLevels` |
| Hue/Saturation | `.ahu` | `hue2` | 2 | 100 bytes | `PsHueSaturation` |
| Selective Color | `.asv` | `selc` | 1 | 84 bytes | `PsSelectiveColor` |
| Channel Mixer | `.cha` | `mixr` | 1 | 44 bytes | `PsChannelMixer` |
| Black & White | `.blw` | `blwh` | 16 (32-bit) | variable | `PsBlackAndWhite` |

Base sizes exclude the optional Levels CS extension and any uninterpreted trailing bytes.

## Levels records

A Levels payload begins with version 2 followed by 29 channel records. Each record stores five unsigned 16-bit values:

| Field | Meaning |
| --- | --- |
| Input floor | Input black point |
| Input ceiling | Input white point |
| Output floor | Output black point |
| Output ceiling | Output white point |
| Gamma | Gamma in hundredths, where 100 means 1.0 |

The first record is the composite; the next ones apply to the channels in order. `PsLevelRecord.gammaValue` exposes gamma as a floating-point value, and `PsLevels.identity()` creates the 29 neutral records.

### Photoshop CS extension

The optional extension follows the standard records:

```text
char marker[4] = "Lvls"
uint16 version = 3
uint16 totalRecordCount
levelRecord extraRecords[totalRecordCount - 29]
```

`PsLevels.extendedRecords` holds the extra records, while `extendedVersion` retains the extension version. Encoding writes this section when the extra-record list is nonempty.

## Hue/Saturation fields

A Hue/Saturation payload stores:

1. Version 2 as a `uint16`.
2. A one-byte colorize flag and one padding byte.
3. Colorization hue, saturation, and lightness as three signed 16-bit values.
4. Master hue, saturation, and lightness in the same representation.
5. Six color ranges, each with four signed 16-bit boundaries and a hue/saturation/lightness triplet.

Range boundaries represent fall-off start, range start, range end, and fall-off end in degrees. `PsHueSaturation` retains colorization, master values, and the six `PsHueSaturationRange` entries separately.

Photoshop 4 wrote colorization values in the −100–100 range; later versions store hue in −180–180 and saturation in 0–100. Both share the same binary layout and cannot be told apart from the file alone. AdjKit retains the stored colorization values without normalizing them.

## Selective Color records

A Selective Color payload starts with version 1 and a 16-bit method field: 0 for relative corrections and 1 for absolute corrections. Ten records follow, each containing signed 16-bit cyan, magenta, yellow, and black corrections.

The first record is reserved. The remaining records describe red, yellow, green, cyan, blue, magenta, white, neutral, and black corrections in that order. `PsSelectiveColor.corrections` retains all ten entries; `absolute` exposes the method.

## Channel Mixer rows

A Channel Mixer payload starts with version 1 and a 16-bit monochrome flag. Four output rows follow, each containing four signed 16-bit source-channel percentages and one signed 16-bit constant.

`PsChannelMixer.outputs` retains every row, including unused channel slots. The layout occupies 44 bytes before any trailing data and is derived from the PSD `mixr` adjustment block.

## Black & White descriptor

A `.blw` file is a version 16 Action Descriptor, the same one PSD `blwh` adjustment layers hold. Its integer items `Rd  `, `Yllw`, `Grn `, `Cyn `, `Bl  `, and `Mgnt` give each colour's contribution in percent (Photoshop's dialog allows −200 to 300); `useTint` and the `tintColor` object describe the optional tint; `bwPresetKind` and `blackAndWhitePresetFileName` record where the settings came from. `PsBlackAndWhite` keeps the whole descriptor, so unknown items and their order survive, and all 22 `.blw` files shipped with Photoshop CS3 to CS5 are rewritten byte for byte.

## Duotone options

`.ado` files and the color mode data of duotone PSD documents share one 524-byte big-endian layout, which `AdjDuotoneDecoder` and `AdjDuotoneEncoder` read and write. It is not part of Adobe's published specification; the layout below was established on the 548 duotone, tritone, and quadtone presets shipped with Photoshop CS1 to CS5, all of which round-trip byte for byte.

| Field | Size | Meaning |
| --- | ---: | --- |
| Version | 2 bytes | 1 |
| Ink count | 2 bytes | 1 to 4 |
| Ink colors | 4 × 10 bytes | Swatch-file color: a color-space identifier and four 16-bit components |
| Ink names | 4 × 64 bytes | Pascal strings; the padding keeps earlier names' bytes |
| Transfer curves | 4 × 28 bytes | Thirteen signed values for inputs 0, 5, 10, 20, …, 90, 95, and 100%, in tenths of a percent or −1 where unset, then an override flag |
| Dot gain | 2 bytes | Percentage |
| Overprint colors | 11 × 10 bytes | Swatch-file colors, kept as stored |

Ink colors use the swatch-file conventions: CMYK stores 0 for full ink and Lab stores signed hundredths. Matching-system inks (identifiers 3 to 6 and 10) hold their catalog code in ASCII, such as `  404C`, exposed by `AdjDuotoneInk.bookCode`; their color is only known to the matching book. `AdjDuotoneInk.outputAt` interpolates the curve between its set points. Unused ink slots and all padding are preserved.

## Compatibility modes and limits

`AdjDecodeMode.tolerant` is the default. Unexpected main versions, trailing bytes, and values outside the following ranges become `AdjWarning` entries in `AdjPresetFile.warnings`:

| Settings | Checked range |
| --- | --- |
| Levels input/output points | 0–255, with input floor below input ceiling |
| Levels gamma | 10–999 in hundredths |
| Master and range hue | −180–180 |
| Master and range saturation/lightness | −100–100 |
| Selective Color corrections | −100–100 |
| Channel Mixer source values and constants | −200–200 |

Strict mode rejects the first such issue with `AdjFormatException`. These checks do not cover colorization values, hue-range boundaries, or the Levels extension version.

The default `AdjDecodeOptions.maxFileBytes` limit is 1 MiB. Exceeding it always throws, regardless of mode. Truncated required fields also throw in both modes; the decoder does not return partially decoded settings.

## Preservation and encoding

Each settings model retains the main version and uninterpreted `trailingData`. Levels also retain extended records and their version. `AdjEncoder.encode` chooses the layout from the settings type and writes these values through the shared PsCore codec.

Encoding requires 29 standard Levels records, six Hue/Saturation ranges with four boundaries each, ten Selective Color records, or four Channel Mixer rows with four source channels each. Invalid counts produce `AdjWriteException`. Encoding does not repeat the decoder's dialog-range checks or provide separate strict and permissive modes.

Reconstruction is semantic rather than a complete source-byte copy. Boolean flags are written as 0 or 1, Hue/Saturation padding is written as zero, and an empty Levels extension is omitted. Retaining trailing bytes therefore does not imply byte-exact preservation of every nonstandard input.

## Integration guidance

Use `AdjDecoder` when an editor needs both settings and compatibility warnings. `AdjCodec` is a `Codec<PsAdjustmentSettings, List<int>>` adapter that returns settings alone; its `kind` selects the input layout, while encoding follows the supplied settings type.

PsdKit's corresponding adjustment classes extend these same PsCore models, so an existing PSD adjustment can be passed directly to `AdjEncoder.encode`. A host editor remains responsible for constructing layers from imported settings, applying adjustments to pixels, and interpreting channels in the document's color mode.

## Current boundaries

AdjKit supports the five layouts above. Curves presets belong to [AcvKit](https://pub.dev/packages/acvkit); Exposure and other undocumented preset layouts are outside the current scope.

The layouts follow Adobe's specification and the PSD adjustment blocks that PsdKit validates against real documents. No public `.alv`, `.ahu`, `.asv`, or `.cha` file was available to compare against; the Channel Mixer size in particular is derived from the `mixr` layout.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
