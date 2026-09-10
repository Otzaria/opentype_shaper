import 'dart:typed_data';

/// Font-level values in font units. Divide by [unitsPerEm] to get em fractions.
///
/// Field order mirrors `rust/src/metrics.rs`; append only, never reorder.
class FontMetrics {
  const FontMetrics({
    required this.unitsPerEm,
    required this.glyphCount,
    required this.ascender,
    required this.descender,
    required this.lineGap,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.capHeight,
    required this.xHeight,
    required this.italicAngle,
    required this.isFixedPitch,
    required this.weightClass,
    required this.flags,
    required this.typoAscender,
    required this.typoDescender,
  });

  factory FontMetrics.fromNative(Int32List fields) {
    return FontMetrics(
      unitsPerEm: fields[0],
      glyphCount: fields[1],
      ascender: fields[2],
      descender: fields[3],
      lineGap: fields[4],
      xMin: fields[5],
      yMin: fields[6],
      xMax: fields[7],
      yMax: fields[8],
      capHeight: fields[9],
      xHeight: fields[10],
      italicAngle: fields[11] / 100.0,
      isFixedPitch: fields[12] != 0,
      weightClass: fields[13],
      flags: fields[14],
      typoAscender: fields[15],
      typoDescender: fields[16],
    );
  }

  static const int flagHasGpos = 1 << 0;
  static const int flagHasGsub = 1 << 1;
  static const int flagHasGdef = 1 << 2;
  static const int flagIsItalic = 1 << 3;
  static const int flagIsSerif = 1 << 4;

  final int unitsPerEm;
  final int glyphCount;
  final int ascender;
  final int descender;
  final int lineGap;
  final int xMin;
  final int yMin;
  final int xMax;
  final int yMax;

  /// Zero when the font declares no OS/2 cap height.
  final int capHeight;

  /// Zero when the font declares no OS/2 x-height.
  final int xHeight;

  final double italicAngle;
  final bool isFixedPitch;
  final int weightClass;
  final int flags;
  final int typoAscender;
  final int typoDescender;

  /// Whether the font positions marks itself. A Hebrew font without GPOS cannot
  /// place nikud, whoever renders it.
  bool get hasGpos => flags & flagHasGpos != 0;
  bool get hasGsub => flags & flagHasGsub != 0;
  bool get hasGdef => flags & flagHasGdef != 0;
  bool get isItalic => flags & flagIsItalic != 0;
  bool get isSerif => flags & flagIsSerif != 0;

  /// Distance between baselines when the font gives no better guidance.
  int get lineHeight => ascender - descender + lineGap;

  @override
  String toString() =>
      'FontMetrics(upem: $unitsPerEm, glyphs: $glyphCount, gpos: $hasGpos)';
}
