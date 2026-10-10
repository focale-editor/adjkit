import 'dart:convert';
import 'dart:typed_data';

import 'package:adjkit/src/model/adj_duotone.dart';
import 'package:adjkit/src/model/adj_options.dart';
import 'package:pscore/pscore.dart';

/// Size of a complete duotone specification.
const int _specificationBytes = 524;

/// Decodes Photoshop `.ado` duotone options and duotone color mode data.
final class AdjDuotoneDecoder extends Converter<List<int>, AdjDuotoneFile> {
  /// Options applied by [convert].
  final AdjDecodeOptions options;

  /// Creates a reusable decoder.
  const AdjDuotoneDecoder({this.options = const AdjDecodeOptions()});

  @override
  AdjDuotoneFile convert(List<int> input) => decode(input is Uint8List ? input : Uint8List.fromList(input), options: options);

  /// Decodes one complete specification.
  static AdjDuotoneFile decode(Uint8List bytes, {AdjDecodeOptions options = const AdjDecodeOptions()}) {
    if (bytes.length > options.maxFileBytes) {
      throw AdjFormatException(message: 'ADO file size ${bytes.length} exceeds the configured ${options.maxFileBytes} byte limit', source: bytes, offset: 0);
    }
    if (bytes.length < _specificationBytes) {
      throw AdjFormatException(message: 'A duotone specification holds $_specificationBytes bytes, not ${bytes.length}', source: bytes, offset: bytes.length);
    }
    final List<String> issues = [];
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint16();
    if (version != 1) {
      issues.add('ADO version $version is not 1');
    }
    final int inkCount = reader.readUint16();
    if (inkCount < 1 || inkCount > 4) {
      throw AdjFormatException(message: 'A duotone specification uses 1 to 4 inks, not $inkCount', source: bytes, offset: 2);
    }
    final List<({int space, List<int> components})> colors = [
      for (int index = 0; index < 4; index++) (space: reader.readUint16(), components: [for (int component = 0; component < 4; component++) reader.readUint16()]),
    ];
    final List<Uint8List> names = [for (int index = 0; index < 4; index++) reader.readBytes(AdjDuotoneInk.nameFieldBytes)];
    final List<({List<int> transfer, int override})> curves = [
      for (int index = 0; index < 4; index++) (transfer: [for (int point = 0; point < adjDuotoneTransferLevels.length; point++) reader.readInt16()], override: reader.readUint16()),
    ];
    final int dotGain = reader.readUint16();
    final Uint8List overprintData = reader.readBytes(AdjDuotoneFile.overprintCount * 10);
    final Uint8List trailingData = reader.readBytes(reader.remaining);
    if (trailingData.isNotEmpty) {
      issues.add('${trailingData.length} unrecognized trailing bytes follow the duotone specification');
    }
    final List<AdjDuotoneInk> inks = [];
    for (int index = 0; index < 4; index++) {
      try {
        inks.add(
          AdjDuotoneInk(colorSpaceId: colors[index].space, components: colors[index].components, nameField: names[index], transfer: curves[index].transfer, transferOverride: curves[index].override),
        );
      } on AdjWriteException catch (error) {
        throw AdjFormatException(message: 'Duotone ink ${index + 1}: ${error.message}', source: bytes);
      }
    }
    for (final AdjDuotoneInk ink in inks.take(inkCount)) {
      if (ink.color == null && ink.bookCode == null) {
        issues.add('Duotone ink "${ink.name}" uses unknown color space ${ink.colorSpaceId}');
      }
    }
    if (options.mode == AdjDecodeMode.strict && issues.isNotEmpty) {
      throw AdjFormatException(message: issues.first, source: bytes);
    }
    return AdjDuotoneFile(
      version: version,
      inkCount: inkCount,
      inks: inks,
      dotGain: dotGain,
      overprintData: overprintData,
      trailingData: trailingData,
      warnings: [for (final String issue in issues) AdjWarning(message: issue)],
    );
  }
}

/// Encodes Photoshop `.ado` duotone options and duotone color mode data.
final class AdjDuotoneEncoder extends Converter<AdjDuotoneFile, List<int>> {
  /// Creates a reusable encoder.
  const AdjDuotoneEncoder();

  @override
  Uint8List convert(AdjDuotoneFile input) => encode(input);

  /// Encodes [file].
  static Uint8List encode(AdjDuotoneFile file) {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeUint16(file.version)
      ..writeUint16(file.inkCount);
    for (final AdjDuotoneInk ink in file.inks) {
      writer.writeUint16(ink.colorSpaceId);
      ink.components.forEach(writer.writeUint16);
    }
    for (final AdjDuotoneInk ink in file.inks) {
      writer.writeBytes(ink.nameField);
    }
    for (final AdjDuotoneInk ink in file.inks) {
      ink.transfer.forEach(writer.writeInt16);
      writer.writeUint16(ink.transferOverride);
    }
    writer
      ..writeUint16(file.dotGain)
      ..writeBytes(file.overprintData)
      ..writeBytes(file.trailingData);
    return writer.takeBytes();
  }
}
