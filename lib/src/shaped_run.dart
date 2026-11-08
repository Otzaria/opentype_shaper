import 'dart:typed_data';

/// One cluster of a shaped run: the glyphs that came out of one indivisible
/// piece of text, together with the text they came from.
///
/// A base letter with two nikud marks is one cluster of three glyphs; a
/// ligature that replaced two characters is one cluster of one glyph.
class ShapedCluster {
  const ShapedCluster({
    required this.firstGlyph,
    required this.glyphCount,
    required this.textStart,
    required this.textEnd,
  });

  /// Index of the cluster's first glyph in the run.
  final int firstGlyph;

  final int glyphCount;

  /// UTF-16 range of the run's text that this cluster covers.
  final int textStart;
  final int textEnd;

  int get lastGlyph => firstGlyph + glyphCount - 1;

  @override
  String toString() =>
      'ShapedCluster(glyphs $firstGlyph..$lastGlyph, text $textStart..$textEnd)';
}

/// The shaped form of one run of text: a glyph id per position, with the offset
/// and advance the font's GPOS rules produced. All values are in font units.
///
/// Glyphs are stored flat rather than as objects because a page of text is tens
/// of thousands of them and a PDF writer walks the numbers directly. The order
/// is visual: for a right-to-left run the first glyph is the leftmost one, so a
/// consumer advances the pen positively while emitting in order.
class ShapedRun {
  const ShapedRun({
    required this.text,
    required this.glyphCount,
    required Int32List records,
    required this.fieldsPerGlyph,
    required this.unitsPerEm,
  }) : _records = records;

  /// An empty run, for empty input.
  static final ShapedRun empty = ShapedRun(
    text: '',
    glyphCount: 0,
    records: Int32List(0),
    fieldsPerGlyph: 6,
    unitsPerEm: 1000,
  );

  /// The text this run was shaped from. Kept so a consumer can recover the
  /// characters behind a cluster, which a PDF text layer needs.
  final String text;

  final int glyphCount;
  final int fieldsPerGlyph;
  final int unitsPerEm;
  final Int32List _records;

  bool get isEmpty => glyphCount == 0;
  bool get isNotEmpty => glyphCount != 0;

  /// The raw records, `fieldsPerGlyph` ints per glyph. Exposed so hot consumers
  /// can walk it without going through an accessor per field.
  Int32List get records => _records;

  int glyphId(int index) => _records[index * fieldsPerGlyph];

  /// UTF-16 offset into [text] of the cluster this glyph belongs to. Several
  /// glyphs share a cluster when one character produced marks, and one glyph
  /// covers several characters when a ligature replaced them.
  int cluster(int index) => _records[index * fieldsPerGlyph + 1];

  int xAdvance(int index) => _records[index * fieldsPerGlyph + 2];
  int yAdvance(int index) => _records[index * fieldsPerGlyph + 3];

  /// Horizontal displacement from the pen, which does not consume advance.
  int xOffset(int index) => _records[index * fieldsPerGlyph + 4];
  int yOffset(int index) => _records[index * fieldsPerGlyph + 5];

  /// Walks the run one cluster at a time, in the order the glyphs are stored.
  ///
  /// The shaper emits clusters monotonically, so a cluster ends where the
  /// neighbouring cluster on its logical right begins.
  List<ShapedCluster> clusters() {
    if (glyphCount == 0) {
      return const [];
    }

    final starts = <int>[];
    final firstGlyphs = <int>[];
    final counts = <int>[];
    for (var index = 0; index < glyphCount; index++) {
      final value = cluster(index);
      if (starts.isEmpty || starts.last != value) {
        starts.add(value);
        firstGlyphs.add(index);
        counts.add(1);
      } else {
        counts[counts.length - 1]++;
      }
    }

    // HarfRust normally emits monotonic UTF-16 clusters. End offsets can
    // therefore be found from adjacent starts without sorting every word and
    // allocating a lookup map. Keep the general path for unusual input.
    var isAscending = true;
    var isDescending = true;
    for (var index = 1; index < starts.length; index++) {
      if (starts[index] < starts[index - 1]) {
        isAscending = false;
      }
      if (starts[index] > starts[index - 1]) {
        isDescending = false;
      }
    }

    Map<int, int>? endOf;
    if (!isAscending && !isDescending) {
      final sorted = List<int>.of(starts)..sort();
      endOf = <int, int>{};
      for (var index = 0; index < sorted.length; index++) {
        endOf[sorted[index]] = index + 1 < sorted.length
            ? sorted[index + 1]
            : text.length;
      }
    }

    int clusterEnd(int group) {
      if (isAscending) {
        return group + 1 < starts.length ? starts[group + 1] : text.length;
      }
      if (isDescending) {
        return group > 0 ? starts[group - 1] : text.length;
      }
      return endOf![starts[group]] ?? text.length;
    }

    return [
      for (var group = 0; group < starts.length; group++)
        ShapedCluster(
          firstGlyph: firstGlyphs[group],
          glyphCount: counts[group],
          textStart: starts[group],
          textEnd: clusterEnd(group),
        ),
    ];
  }

  /// Total advance of the run in font units.
  int get advance {
    var total = 0;
    for (var index = 0; index < glyphCount; index++) {
      total += _records[index * fieldsPerGlyph + 2];
    }
    return total;
  }

  /// Total advance scaled to `fontSize`.
  double advanceAt(double fontSize) => advance * fontSize / unitsPerEm;

  @override
  String toString() => 'ShapedRun($glyphCount glyphs, advance $advance)';
}
