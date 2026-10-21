// Shapes a Hebrew word and prints where each glyph goes, then subsets the font
// for a PDF that draws those glyphs by id.
//
//   dart run example/main.dart /path/to/NotoSerifHebrew.ttf
import 'dart:io';

import 'package:opentype_shaper/opentype_shaper.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Pass the path of a Hebrew OpenType font.');
    exitCode = 64;
    return;
  }

  final bytes = File(args.first).readAsBytesSync();
  final font = ShaperFont.register(bytes);
  try {
    const fontSize = 24.0;
    final scale = fontSize / font.metrics.unitsPerEm;

    final run = font.shape('שָׁלוֹם', rtl: true, script: 'hebr');
    stdout.writeln('${font.postScriptName}: $run');

    // Glyphs come back in visual order, so the pen only moves forward.
    var penX = 0.0;
    for (var i = 0; i < run.glyphCount; i++) {
      final x = penX + run.xOffset(i) * scale;
      final y = run.yOffset(i) * scale;
      stdout.writeln(
        'glyph ${run.glyphId(i)} at (${x.toStringAsFixed(2)}, '
        '${y.toStringAsFixed(2)}), cluster ${run.cluster(i)}',
      );
      penX += run.xAdvance(i) * scale;
    }

    final usedGlyphIds = {
      for (var i = 0; i < run.glyphCount; i++) run.glyphId(i),
    };
    final subset = subsetFontForPdf(bytes, usedGlyphIds);
    stdout.writeln('PDF subset: ${subset.length} of ${bytes.length} bytes');
  } finally {
    font.dispose();
  }
}
