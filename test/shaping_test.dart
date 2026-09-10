import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';

/// A pointed Hebrew word carrying nikud and one ta'am.
const String sample =
    'שָׁ֖' // shin + shin dot + qamats + tipeha
    'לֹ' // lamed + holam
    'ם'; // final mem

/// Locates the library cargo built. A plugin's native artefact is only placed
/// beside the executable by a Flutter build, so a host-VM test points at it.
String? findNativeLibrary() {
  final name = Platform.isWindows
      ? 'opentype_shaper.dll'
      : Platform.isMacOS
      ? 'libopentype_shaper.dylib'
      : 'libopentype_shaper.so';
  for (final profile in const ['release', 'debug']) {
    final candidate = File('rust/target/$profile/$name');
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  return null;
}

Uint8List? readTestFont() {
  final path = Platform.environment['OPENTYPE_SHAPER_TEST_FONT'];
  if (path == null) {
    return null;
  }
  final file = File(path);
  return file.existsSync() ? file.readAsBytesSync() : null;
}

void main() {
  final libraryPath = findNativeLibrary();
  final fontBytes = readTestFont();

  setUpAll(() {
    if (libraryPath != null) {
      ShaperLibrary.path = libraryPath;
    }
  });

  group('bindings', () {
    test('load the native library and agree on the ABI', () {
      expect(ShaperLibrary.abiVersion, 1);
      expect(ShaperLibrary.recordFields, 6);
    }, skip: libraryPath == null ? 'run cargo build first' : null);
  });

  group(
    'shaping',
    () {
      late ShaperFont font;

      setUp(() {
        font = ShaperFont.register(fontBytes!);
      });

      tearDown(() => font.dispose());

      test('reads the font metrics', () {
        expect(font.metrics.unitsPerEm, greaterThan(0));
        expect(font.metrics.glyphCount, greaterThan(0));
        expect(font.metrics.ascender, greaterThan(0));
        expect(font.metrics.descender, lessThan(0));
        expect(font.glyphAdvances.length, font.metrics.glyphCount);
        // A Hebrew font must position its own marks.
        expect(font.metrics.hasGpos, isTrue);
      });

      test('positions marks through GPOS instead of at the pen', () {
        final run = font.shape(sample, rtl: true, script: 'hebr');

        expect(run.glyphCount, greaterThan(0));

        final markIndices = [
          for (var index = 0; index < run.glyphCount; index++)
            if (run.xAdvance(index) == 0) index,
        ];
        expect(
          markIndices,
          isNotEmpty,
          reason: 'nikud produces zero-advance marks',
        );
        expect(
          markIndices.any(
            (index) => run.xOffset(index) != 0 || run.yOffset(index) != 0,
          ),
          isTrue,
          reason: 'an unshaped writer would leave every offset at zero',
        );
      });

      test('returns right-to-left glyphs in visual order', () {
        final run = font.shape(sample, rtl: true, script: 'hebr');
        final clusters = [
          for (var index = 0; index < run.glyphCount; index++)
            run.cluster(index),
        ];
        // Visual order runs leftmost first, so clusters never increase.
        for (var index = 1; index < clusters.length; index++) {
          expect(clusters[index], lessThanOrEqualTo(clusters[index - 1]));
        }
        expect(clusters.every((cluster) => cluster < sample.length), isTrue);
      });

      test('scales the advance to a point size', () {
        final run = font.shape(sample, rtl: true, script: 'hebr');
        expect(run.advance, greaterThan(0));
        final expected = run.advance * 24.0 / font.metrics.unitsPerEm;
        expect(run.advanceAt(24), closeTo(expected, 1e-9));
      });

      test('caches repeated runs and returns the same result', () {
        final first = font.shape(sample, rtl: true, script: 'hebr');
        final second = font.shape(sample, rtl: true, script: 'hebr');
        expect(identical(first, second), isTrue);

        // A different parameter must not hit the cached entry.
        final ltr = font.shape(sample, script: 'hebr');
        expect(identical(first, ltr), isFalse);
      });

      test('grows the output buffer rather than truncating', () {
        // Long enough that the first guess at capacity cannot hold the marks.
        final long = sample * 40;
        final run = font.shape(long, rtl: true, script: 'hebr');
        expect(run.glyphCount, greaterThan(sample.length * 40 * 0.5));
        expect(run.records.length, run.glyphCount * run.fieldsPerGlyph);
      });

      test('groups glyphs into clusters that cover the text once', () {
        final run = font.shape(sample, rtl: true, script: 'hebr');
        final clusters = run.clusters();

        expect(clusters, isNotEmpty);
        expect(
          clusters.fold<int>(0, (sum, cluster) => sum + cluster.glyphCount),
          run.glyphCount,
          reason: 'every glyph belongs to exactly one cluster',
        );

        // The ranges must tile the text without gaps or overlap, which is what
        // makes a PDF text layer recoverable from the shaped result.
        final ordered = clusters.toList()
          ..sort((a, b) => a.textStart.compareTo(b.textStart));
        expect(ordered.first.textStart, 0);
        expect(ordered.last.textEnd, sample.length);
        for (var index = 1; index < ordered.length; index++) {
          expect(ordered[index].textStart, ordered[index - 1].textEnd);
        }

        // A base carrying nikud is one cluster of several glyphs.
        expect(clusters.any((cluster) => cluster.glyphCount > 1), isTrue);
      });

      test('shapes an empty string to an empty run', () {
        expect(font.shape('').isEmpty, isTrue);
      });

      test('rejects use after dispose', () {
        font.dispose();
        expect(() => font.shape(sample), throwsA(isA<ShaperException>()));
        // A second dispose must be harmless; tearDown calls it again.
        font.dispose();
      });
    },
    skip: libraryPath == null
        ? 'run cargo build first'
        : fontBytes == null
        ? 'set OPENTYPE_SHAPER_TEST_FONT'
        : null,
  );

  group('failures', () {
    test('reports a font that cannot be parsed', () {
      expect(
        () => ShaperFont.register(Uint8List.fromList(List.filled(64, 0))),
        throwsA(isA<ShaperException>()),
      );
    });

    test('rejects empty font data', () {
      expect(
        () => ShaperFont.register(Uint8List(0)),
        throwsA(isA<ShaperException>()),
      );
    });
  }, skip: libraryPath == null ? 'run cargo build first' : null);
}
