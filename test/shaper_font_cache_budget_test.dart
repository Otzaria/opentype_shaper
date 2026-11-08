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

    test('cache budget includes strings retained by the shaping key', () {
      font.cacheByteCapacity = 512;
      final script = 'x' * 4096;
      final first = font.shape('שלום', script: script);
      final second = font.shape('שלום', script: script);
      expect(identical(first, second), isFalse);
      expect(second.records, orderedEquals(first.records));
    });

    test('an oversized run preserves already cached short words', () {
      font.cacheByteCapacity = 512;
      final first = font.shape('שלום', rtl: true, script: 'hebr');
      font.shape('שלום ' * 1000, rtl: true, script: 'hebr');
      expect(
        identical(first, font.shape('שלום', rtl: true, script: 'hebr')),
        isTrue,
      );
    });

    test('cache hits update recency without consuming more byte budget', () {
      final first = font.shape('שלום');
      final cost = first.text.length * 2 + first.records.lengthInBytes + 96;
      font.cacheByteCapacity = cost * 2;
      final second = font.shape('עולם');
      for (var i = 0; i < 10; i++) {
        expect(identical(first, font.shape('שלום')), isTrue);
      }
      font.shape('אדם ');
      expect(identical(first, font.shape('שלום')), isTrue);
      expect(identical(second, font.shape('עולם')), isFalse);
    });

    for (final byteLimit in [false, true]) {
      test('negative ${byteLimit ? 'byte' : 'entry'} limit disables hits', () {
        final first = font.shape('שלום');
        if (byteLimit) {
          font.cacheByteCapacity = -1;
        } else {
          font.cacheCapacity = -1;
        }
        expect(identical(first, font.shape('שלום')), isFalse);
        font.cacheCapacity = 8192;
        font.cacheByteCapacity = 8 * 1024 * 1024;
        expect(identical(first, font.shape('שלום')), isFalse);
      });
    }

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
          (first.text.length + 'hebr'.length) * 2 +
          first.records.lengthInBytes +
          96;
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
