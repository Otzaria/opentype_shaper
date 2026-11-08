import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';

import 'shaping_test.dart' show readTestFont;

void main() {
  final fontBytes = readTestFont();

  group('ShaperFont bounded run cache', () {
    late ShaperFont font;

    setUp(() {
      font = ShaperFont.register(fontBytes!);
    });

    tearDown(() => font.dispose());

    test('short repeated Hebrew words still hit the LRU', () {
      final first = font.shape('שלום', rtl: true, script: 'hebr');
      final second = font.shape('שלום', rtl: true, script: 'hebr');
      expect(identical(first, second), isTrue);
    });

    test('an oversized shaped run is returned without being cached', () {
      font.cacheByteCapacity = 160;
      const text = 'שלום עולם שלום עולם שלום עולם שלום עולם';
      final first = font.shape(text, rtl: true, script: 'hebr');
      final second = font.shape(text, rtl: true, script: 'hebr');

      expect(identical(first, second), isFalse);
      expect(second.records, orderedEquals(first.records));
    });

    test('byte budget evicts least-recently-used runs', () {
      final first = font.shape('שלום', rtl: true, script: 'hebr');
      final estimatedBytes =
          first.text.length * 2 + first.records.lengthInBytes + 96;
      font.cacheByteCapacity = estimatedBytes;

      // Same-length Hebrew words with four glyphs cannot both fit.
      final other = font.shape('עולם', rtl: true, script: 'hebr');
      expect(other.isNotEmpty, isTrue);
      final reshaped = font.shape('שלום', rtl: true, script: 'hebr');

      expect(identical(reshaped, first), isFalse);
      expect(reshaped.records, orderedEquals(first.records));
    });

    test('lowering entry capacity evicts existing entries immediately', () {
      final first = font.shape('שלום', rtl: true, script: 'hebr');
      font.shape('עולם', rtl: true, script: 'hebr');
      font.cacheCapacity = 1;

      expect(
        identical(font.shape('שלום', rtl: true, script: 'hebr'), first),
        isFalse,
      );
    });

    test('disabling cache stops existing hits, and reenable works', () {
      final first = font.shape('שלום', rtl: true, script: 'hebr');
      font.cacheCapacity = 0;
      final uncached = font.shape('שלום', rtl: true, script: 'hebr');
      expect(identical(first, uncached), isFalse);

      font.cacheCapacity = 8192;
      final stored = font.shape('שלום', rtl: true, script: 'hebr');
      expect(identical(stored, uncached), isFalse);
      expect(
        identical(stored, font.shape('שלום', rtl: true, script: 'hebr')),
        isTrue,
      );
    });

    test('zero byte capacity disables caching independently', () {
      font.cacheByteCapacity = 0;
      final first = font.shape('שלום', rtl: true, script: 'hebr');
      final second = font.shape('שלום', rtl: true, script: 'hebr');
      expect(identical(first, second), isFalse);
      expect(second.records, orderedEquals(first.records));
    });
  }, skip: fontBytes == null ? 'set OPENTYPE_SHAPER_TEST_FONT' : null);
}
