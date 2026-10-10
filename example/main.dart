import 'dart:io';

import 'package:adjkit/adjkit.dart';

/// Prints the settings of one Photoshop adjustment preset.
Future<void> main(List<String> arguments) async {
  final AdjPresetKind? kind = arguments.length == 1 ? AdjPresetKind.fromExtension(arguments.single.split('.').last) : null;
  if (kind == null) {
    stderr.writeln('Usage: dart run example/main.dart <preset.alv|ahu|asv|cha|blw>');
    exitCode = 64;
    return;
  }
  final AdjPresetFile preset = AdjDecoder.decode(await File(arguments.single).readAsBytes(), kind: kind);
  final String summary = switch (preset.settings) {
    PsLevels(:final List<PsLevelRecord> records) => 'Levels: input ${records.first.inputFloor}–${records.first.inputCeiling}, gamma ${records.first.gammaValue}',
    PsHueSaturation(:final PsHueSaturationValues master, :final bool colorize) => 'Hue/Saturation: hue ${master.hue}, saturation ${master.saturation}, colorize $colorize',
    PsSelectiveColor(:final bool absolute) => 'Selective Color: ${absolute ? 'absolute' : 'relative'}',
    PsChannelMixer(:final bool monochrome) => 'Channel Mixer: ${monochrome ? 'monochrome' : 'color'}',
    PsBlackAndWhite(:final int red, :final int yellow, :final int blue) => 'Black & White: reds $red%, yellows $yellow%, blues $blue%',
  };
  stdout.writeln(summary);
  preset.warnings.forEach(stderr.writeln);
}
