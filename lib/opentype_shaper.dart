/// OpenType text shaping for Dart and Flutter.
///
/// Dart's PDF and text libraries do not run a font's OpenType layout tables, so
/// scripts that position marks through GPOS come out misplaced. This package
/// runs the shaping and hands back glyph ids with a per-glyph offset and
/// advance, in font units, which a renderer or a PDF writer can place directly.
library;

export 'src/errors.dart';
export 'src/font_metrics.dart';
export 'src/shaped_run.dart';
export 'src/shaper_font.dart';
export 'src/shaper_library.dart';
