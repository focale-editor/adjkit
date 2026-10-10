import 'dart:typed_data';

import 'package:adjkit/src/model/adj_options.dart';
import 'package:pscore/pscore.dart';

/// Number of input levels a duotone transfer curve stores, in percent.
const List<int> adjDuotoneTransferLevels = [0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100];

/// One ink of a duotone, tritone, or quadtone specification.
final class AdjDuotoneInk {
  /// Size of the stored name field, length byte included.
  static const int nameFieldBytes = 64;

  /// Photoshop color-space identifier of [components], as in swatch files.
  ///
  /// 0 is RGB, 1 HSB, 2 CMYK, 7 Lab, 8 grayscale; 3 to 6 and 10 are
  /// matching-system references such as Pantone, whose components hold the
  /// catalog code instead of a color.
  final int colorSpaceId;

  /// Four 16-bit components in [colorSpaceId].
  final List<int> components;

  /// The complete 64-byte Pascal name field, padding included.
  ///
  /// Photoshop leaves earlier names' bytes in the padding, which is kept so
  /// files round-trip unchanged.
  final Uint8List nameField;

  /// Output percentage times ten for each of [adjDuotoneTransferLevels], or -1
  /// where the curve has no point.
  final List<int> transfer;

  /// Photoshop's transfer-function override flag.
  final int transferOverride;

  /// Creates an ink from its stored fields.
  AdjDuotoneInk({required this.colorSpaceId, required List<int> components, required Uint8List nameField, required List<int> transfer, this.transferOverride = 0})
    : components = List<int>.unmodifiable(components),
      nameField = Uint8List.fromList(nameField).asUnmodifiableView(),
      transfer = List<int>.unmodifiable(transfer) {
    if (components.length != 4 || components.any((value) => value < 0 || value > 0xffff)) {
      throw const AdjWriteException(message: 'A duotone ink holds four 16-bit color components');
    }
    if (nameField.length != nameFieldBytes || nameField.first > nameFieldBytes - 1) {
      throw const AdjWriteException(message: 'A duotone ink name field holds a Pascal string of at most 63 bytes in 64 bytes');
    }
    if (transfer.length != adjDuotoneTransferLevels.length || transfer.any((value) => value < -1 || value > 1000)) {
      throw const AdjWriteException(message: 'A duotone transfer curve holds 13 values from -1 to 1000');
    }
  }

  /// Creates an ink named [name] from [color], with a linear curve unless [transfer] is given.
  factory AdjDuotoneInk.create({required String name, required PsColor color, List<int>? transfer}) {
    final ({int space, List<int> components}) stored = _storedColor(color);
    final List<int> bytes = name.codeUnits.map((unit) => unit > 0xff ? 0x3f : unit).take(nameFieldBytes - 1).toList();
    return AdjDuotoneInk(
      colorSpaceId: stored.space,
      components: stored.components,
      nameField: Uint8List(nameFieldBytes)
        ..[0] = bytes.length
        ..setAll(1, bytes),
      transfer: transfer ?? adjDuotoneTransferLevels.map((level) => level == 0 || level == 100 ? level * 10 : -1).toList(),
    );
  }

  /// The ink's name.
  String get name => String.fromCharCodes(nameField.sublist(1, 1 + nameField.first));

  /// The matching-system catalog code of a reference ink, such as `404C`.
  String? get bookCode => switch (colorSpaceId) {
    3 || 4 || 5 || 6 || 10 => String.fromCharCodes([
      for (final int component in components.take(3)) ...[component >> 8, component & 0xff],
    ]).trim(),
    _ => null,
  };

  /// This ink's color, or `null` for a matching-system reference.
  PsColor? get color {
    double unit(int value) => value / 655.35;
    return switch (colorSpaceId) {
      0 => PsColor.rgb(red: components[0] / 257, green: components[1] / 257, blue: components[2] / 257),
      1 => PsColor.hsb(hue: components[0] / 182.04, saturation: unit(components[1]), brightness: unit(components[2])),
      // Swatch-file CMYK stores 0 for full ink.
      2 => PsColor.cmyk(cyan: 100 - unit(components[0]), magenta: 100 - unit(components[1]), yellow: 100 - unit(components[2]), black: 100 - unit(components[3])),
      7 => PsColor.lab(lightness: components[0] / 100, a: components[1].toSigned(16) / 100, b: components[2].toSigned(16) / 100),
      8 => PsColor.grayscale(gray: components[0] / 100),
      _ => null,
    };
  }

  /// Output fraction for an input density from 0 to 1, interpolating between
  /// the curve's points as Photoshop does.
  double outputAt(double density) {
    final List<(double, double)> points = [
      for (int index = 0; index < transfer.length; index++)
        if (transfer[index] >= 0) (adjDuotoneTransferLevels[index] / 100, transfer[index] / 1000),
    ];
    if (points.isEmpty) {
      return density.clamp(0.0, 1.0);
    }
    if (points.first.$1 > 0) {
      points.insert(0, (0, 0));
    }
    if (points.last.$1 < 1) {
      points.add((1, 1));
    }
    final double input = density.clamp(0.0, 1.0);
    for (int index = 1; index < points.length; index++) {
      final (double x1, double y1) = points[index];
      if (input <= x1) {
        final (double x0, double y0) = points[index - 1];
        return x1 == x0 ? y1 : y0 + (y1 - y0) * (input - x0) / (x1 - x0);
      }
    }
    return points.last.$2;
  }

  /// Stores [color] in the swatch-file layout.
  static ({int space, List<int> components}) _storedColor(PsColor color) {
    int word(double value) => value.round().clamp(0, 0xffff);
    switch (color.colorSpace) {
      case PsColorSpace.cmyk:
        double read(String short, String long) => (color.components[short] ?? color.components[long])?.value ?? 0;
        return (
          space: 2,
          components: [
            word((100 - read('Cyn ', 'cyan')) * 655.35),
            word((100 - read('Mgnt', 'magenta')) * 655.35),
            word((100 - read('Ylw ', 'yellowColor')) * 655.35),
            word((100 - read('Blck', 'black')) * 655.35),
          ],
        );
      default:
        final ({double red, double green, double blue}) rgb = color.toRgb() ?? (throw AdjWriteException(message: 'The ${color.classId} color cannot be stored in a duotone ink'));
        return (space: 0, components: [word(rgb.red * 257), word(rgb.green * 257), word(rgb.blue * 257), 0]);
    }
  }
}

/// Complete decoded contents of one Photoshop `.ado` duotone options file.
///
/// PSD and PSB files in duotone mode store the same structure as their color
/// mode data.
final class AdjDuotoneFile {
  /// Number of overprint color records stored after the inks.
  static const int overprintCount = 11;

  /// Format version, 1 in every known file.
  final int version;

  /// Inks in use, from 1 (monotone) to 4 (quadtone).
  final int inkCount;

  /// Four ink slots; slots beyond [inkCount] keep whatever Photoshop left there.
  final List<AdjDuotoneInk> inks;

  /// Dot gain in percent.
  final int dotGain;

  /// The eleven 10-byte overprint color records, kept as stored.
  final Uint8List overprintData;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Recoverable compatibility issues encountered while decoding.
  final List<AdjWarning> warnings;

  /// Creates a duotone specification from its stored fields.
  AdjDuotoneFile({
    this.version = 1,
    required this.inkCount,
    required List<AdjDuotoneInk> inks,
    this.dotGain = 20,
    Uint8List? overprintData,
    Uint8List? trailingData,
    List<AdjWarning> warnings = const [],
  }) : inks = List<AdjDuotoneInk>.unmodifiable(inks),
       overprintData = Uint8List.fromList(overprintData ?? _defaultOverprints()).asUnmodifiableView(),
       trailingData = Uint8List.fromList(trailingData ?? const []).asUnmodifiableView(),
       warnings = List<AdjWarning>.unmodifiable(warnings) {
    if (inkCount < 1 || inkCount > 4 || inks.length != 4) {
      throw const AdjWriteException(message: 'A duotone specification uses 1 to 4 of its 4 ink slots');
    }
    if (this.overprintData.length != overprintCount * 10) {
      throw const AdjWriteException(message: 'A duotone specification holds eleven 10-byte overprint colors');
    }
  }

  /// Creates a specification using [inks], filling the unused slots as Photoshop does.
  factory AdjDuotoneFile.create({required List<AdjDuotoneInk> inks, int dotGain = 20}) => AdjDuotoneFile(
    inkCount: inks.length,
    inks: [
      ...inks,
      for (int index = inks.length; index < 4; index++)
        AdjDuotoneInk(
          colorSpaceId: 0xffff,
          components: const [0, 0, 0, 0],
          nameField: Uint8List(AdjDuotoneInk.nameFieldBytes),
          transfer: adjDuotoneTransferLevels.map((level) => level == 100 ? 1000 : -1).toList(),
        ),
    ],
    dotGain: dotGain,
  );

  /// Inks in use.
  List<AdjDuotoneInk> get activeInks => inks.sublist(0, inkCount);

  /// Photoshop's empty overprint records: an unset color space and zero components.
  static Uint8List _defaultOverprints() {
    final Uint8List bytes = Uint8List(overprintCount * 10);
    for (int index = 0; index < overprintCount; index++) {
      bytes[index * 10] = 0xff;
      bytes[index * 10 + 1] = 0xff;
    }
    return bytes;
  }
}
