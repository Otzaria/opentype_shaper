import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';

ShapedRun _run(String text, List<int> starts) {
  final records = Int32List(starts.length * 6);
  for (var index = 0; index < starts.length; index++) {
    records[index * 6] = index + 1;
    records[index * 6 + 1] = starts[index];
  }
  return ShapedRun(
    text: text,
    glyphCount: starts.length,
    records: records,
    fieldsPerGlyph: 6,
    unitsPerEm: 1000,
  );
}

List<(int, int, int, int)> _describe(ShapedRun run) => [
  for (final cluster in run.clusters())
    (
      cluster.firstGlyph,
      cluster.glyphCount,
      cluster.textStart,
      cluster.textEnd,
    ),
];

void main() {
  test('LTR clusters preserve grouped glyphs and ascending text ranges', () {
    expect(_describe(_run('abcdef', [0, 0, 2, 4])), [
      (0, 2, 0, 2),
      (2, 1, 2, 4),
      (3, 1, 4, 6),
    ]);
  });

  test('RTL clusters preserve visual order and descending text ranges', () {
    expect(_describe(_run('abcdef', [4, 2, 2, 0])), [
      (0, 1, 4, 6),
      (1, 2, 2, 4),
      (3, 1, 0, 2),
    ]);
  });

  test('unusual nonmonotonic clusters still use sorted logical ends', () {
    expect(_describe(_run('abcdef', [2, 0, 4])), [
      (0, 1, 2, 4),
      (1, 1, 0, 2),
      (2, 1, 4, 6),
    ]);
  });

  test('a UTF-16 surrogate pair stays inside a cluster range', () {
    expect(_describe(_run('A😀B', [3, 1, 0])), [
      (0, 1, 3, 4),
      (1, 1, 1, 3),
      (2, 1, 0, 1),
    ]);
  });

  test('single-cluster and empty runs have stable ranges', () {
    expect(_describe(_run('abc', [0, 0, 0])), [(0, 3, 0, 3)]);
    expect(_describe(ShapedRun.empty), isEmpty);
  });
}
