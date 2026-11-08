import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';

/// A deliberately minimal sfnt directory for malformed-input regression tests.
/// All tables fit in the byte array, even when their contents are invalid.
(Uint8List, Map<String, int>) _fontWithTables(List<(String, int)> tables) {
  var size = 12 + tables.length * 16;
  for (final (_, length) in tables) {
    size += length;
  }
  final bytes = Uint8List(size);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, tables.length);
  final offsets = <String, int>{};
  var offset = 12 + tables.length * 16;
  for (var index = 0; index < tables.length; index++) {
    final (tag, length) = tables[index];
    final record = 12 + index * 16;
    for (var i = 0; i < 4; i++) {
      data.setUint8(record + i, tag.codeUnitAt(i));
    }
    data.setUint32(record + 8, offset);
    data.setUint32(record + 12, length);
    offsets[tag] = offset;
    offset += length;
  }
  return (bytes, offsets);
}

void main() {
  test('a truncated TTC face directory throws FormatException', () {
    final bytes = Uint8List(16);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 0x74746366); // ttcf
    data.setUint32(8, 2); // only one of two face offsets is present

    expect(
      () => subsetFontForPdf(bytes, const [], faceIndex: 0),
      throwsFormatException,
    );
  });

  test('a truncated required table throws FormatException', () {
    final (bytes, _) = _fontWithTables(const [
      ('head', 12),
      ('hhea', 36),
      ('hmtx', 4),
      ('maxp', 6),
    ]);
    expect(() => subsetFontForPdf(bytes, const []), throwsFormatException);
  });

  test('a font with zero glyphs rejects glyph-zero traversal', () {
    final (bytes, _) = _fontWithTables(const [
      ('head', 54),
      ('hhea', 36),
      ('hmtx', 4),
      ('maxp', 6),
      ('glyf', 0),
      ('loca', 2),
    ]);
    expect(() => subsetFontForPdf(bytes, const []), throwsFormatException);
  });

  test('a truncated composite glyph throws FormatException', () {
    final (bytes, offsets) = _fontWithTables(const [
      ('head', 54),
      ('hhea', 36),
      ('hmtx', 4),
      ('maxp', 6),
      ('glyf', 12),
      ('loca', 4),
    ]);
    final data = ByteData.sublistView(bytes);
    data.setUint16(offsets['maxp']! + 4, 1);
    // A single 12-byte outline (short loca offsets count 2-byte words).
    data.setUint16(offsets['loca']! + 2, 6);
    // Negative contour count denotes a composite. Its two-byte trailing
    // fragment is too short for the mandatory component record.
    data.setInt16(offsets['glyf']!, -1);
    expect(() => subsetFontForPdf(bytes, const [0]), throwsFormatException);
  });

  test('a descending loca offset throws FormatException', () {
    final (bytes, offsets) = _fontWithTables(const [
      ('head', 54),
      ('hhea', 36),
      ('hmtx', 4),
      ('maxp', 6),
      ('glyf', 8),
      ('loca', 6),
    ]);
    final data = ByteData.sublistView(bytes);
    data.setUint16(offsets['maxp']! + 4, 2);
    // Short loca offsets count 2-byte words: 0, 8, 4 is invalid.
    data.setUint16(offsets['loca']! + 2, 4);
    data.setUint16(offsets['loca']! + 4, 2);
    expect(() => subsetFontForPdf(bytes, const []), throwsFormatException);
  });
}
