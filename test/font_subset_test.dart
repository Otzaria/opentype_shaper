import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';

import 'shaping_test.dart' show findNativeLibrary, readTestFont, sample;

/// Reads a single-font table directory: tag to (offset, length).
Map<String, (int, int)> tablesOf(Uint8List font) {
  final data = ByteData.sublistView(font);
  return {
    for (var index = 0; index < data.getUint16(4); index++)
      String.fromCharCodes(font.sublist(12 + index * 16, 16 + index * 16)): (
        data.getUint32(20 + index * 16),
        data.getUint32(24 + index * 16),
      ),
  };
}

Uint8List tableOf(Uint8List font, String tag) {
  final (offset, length) = tablesOf(font)[tag]!;
  return Uint8List.sublistView(font, offset, offset + length);
}

/// Each glyph's outline bytes, from `loca` and `glyf`.
List<Uint8List> glyphsOf(Uint8List font) {
  final head = ByteData.sublistView(tableOf(font, 'head'));
  final count = ByteData.sublistView(tableOf(font, 'maxp')).getUint16(4);
  final loca = ByteData.sublistView(tableOf(font, 'loca'));
  final glyf = tableOf(font, 'glyf');
  final long = head.getInt16(50) == 1;
  int at(int glyph) =>
      long ? loca.getUint32(glyph * 4) : loca.getUint16(glyph * 2) * 2;
  return [
    for (var glyph = 0; glyph < count; glyph++)
      Uint8List.sublistView(glyf, at(glyph), at(glyph + 1)),
  ];
}

/// Strips the zero padding a writer may add after an outline.
List<int> trimmed(Uint8List bytes) {
  var end = bytes.length;
  while (end > 0 && bytes[end - 1] == 0) {
    end--;
  }
  return bytes.sublist(0, end);
}

int wholeFontChecksum(Uint8List font) {
  final data = ByteData.sublistView(font);
  var sum = 0;
  for (var offset = 0; offset + 4 <= font.length; offset += 4) {
    sum = (sum + data.getUint32(offset)) & 0xFFFFFFFF;
  }
  return sum;
}

void main() {
  final libraryPath = findNativeLibrary();
  final fontBytes = readTestFont();

  group(
    'subsetFontForPdf',
    () {
      late ShaperFont font;
      late List<int> used;

      setUpAll(() {
        ShaperLibrary.path = libraryPath;
        font = ShaperFont.register(fontBytes!);
        final run = font.shape(sample, rtl: true, script: 'hebr');
        used = [for (var i = 0; i < run.glyphCount; i++) run.glyphId(i)];
      });

      tearDownAll(() => font.dispose());

      test('keeps used outlines at their ids and empties the rest', () {
        final subset = subsetFontForPdf(fontBytes!, used);
        final before = glyphsOf(fontBytes);
        final after = glyphsOf(subset);

        expect(after, hasLength(before.length));
        for (final glyph in {0, ...used}) {
          expect(trimmed(after[glyph]), trimmed(before[glyph]));
        }
        final dropped = [
          for (var glyph = 0; glyph < after.length; glyph++)
            if (!used.contains(glyph) && glyph != 0) after[glyph],
        ];
        // Composites may pull in extra glyphs; most of the font still goes.
        expect(
          dropped.where((outline) => outline.isEmpty).length,
          greaterThan(dropped.length ~/ 2),
        );
        expect(subset.length, lessThan(fontBytes.length ~/ 2));
      });

      test('keeps the glyphs a composite is built from', () {
        final original = glyphsOf(fontBytes!);
        final composite = original.indexWhere(
          (outline) =>
              outline.length >= 10 &&
              ByteData.sublistView(outline).getInt16(0) < 0,
        );
        if (composite < 0) {
          markTestSkipped('the test font has no composite glyph');
          return;
        }
        final component = ByteData.sublistView(
          original[composite],
        ).getUint16(12);
        final after = glyphsOf(subsetFontForPdf(fontBytes, [composite]));
        expect(trimmed(after[component]), trimmed(original[component]));
      });

      test('drops the tables a PDF never reads', () {
        final tags = tablesOf(subsetFontForPdf(fontBytes!, used)).keys;
        for (final tag in const ['GSUB', 'GPOS', 'GDEF', 'gvar', 'fvar']) {
          expect(tags, isNot(contains(tag)));
        }
        expect(
          tags,
          containsAll(['head', 'hhea', 'hmtx', 'maxp', 'glyf', 'loca']),
        );
      });

      test('writes a font that parses and keeps its metrics', () {
        final subset = subsetFontForPdf(fontBytes!, used);
        expect(wholeFontChecksum(subset), 0xB1B0AFBA);

        final reparsed = ShaperFont.register(subset);
        addTearDown(reparsed.dispose);
        expect(reparsed.metrics.unitsPerEm, font.metrics.unitsPerEm);
        expect(reparsed.metrics.glyphCount, font.metrics.glyphCount);
        for (final glyph in used) {
          expect(reparsed.glyphAdvances[glyph], font.glyphAdvances[glyph]);
        }
      });
    },
    skip: libraryPath == null
        ? 'run cargo build first'
        : fontBytes == null
        ? 'set OPENTYPE_SHAPER_TEST_FONT'
        : null,
  );

  test('rejects data that is not a font', () {
    expect(
      () => subsetFontForPdf(Uint8List(8), const [1]),
      throwsFormatException,
    );
    expect(
      () => subsetFontForPdf(Uint8List(64), const [1]),
      throwsFormatException,
    );
  });
}
