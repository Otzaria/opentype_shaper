# opentype_shaper

OpenType text shaping for Dart and Flutter.

Dart's PDF and text libraries do not run a font's OpenType layout tables. For a
script that positions marks through `GPOS`, such as Hebrew with nikud and
te'amim, that leaves every mark drawn at the pen instead of on its letter, and
a glyph that only a `GSUB` rule can produce is never reached at all.

This package runs the shaping and hands back what a renderer or a PDF writer
needs to place text itself: a glyph id per position, with the offset and
advance the font's rules produced, in font units.

The engine is [HarfRust](https://github.com/harfbuzz/harfrust), the Rust port
of HarfBuzz, compiled into a small native library with no C or C++
dependencies. The Dart side talks to it over a plain C ABI, so there is no
bridge runtime and nothing to initialise at startup.

## Usage

```dart
import 'package:opentype_shaper/opentype_shaper.dart';

final font = ShaperFont.register(fontBytes);
try {
  final run = font.shape('שָׁלוֹם', rtl: true, script: 'hebr');
  for (var i = 0; i < run.glyphCount; i++) {
    // run.glyphId(i), run.xAdvance(i), run.xOffset(i), run.yOffset(i)
  }
} finally {
  font.dispose();
}
```

Results are in font units; divide by `font.metrics.unitsPerEm` and multiply by
the point size. Glyphs of a right-to-left run come back in visual order, so a
consumer advances the pen positively while emitting them in sequence.

`ShaperFont.attach(handle)` lets a background isolate use a font the main
isolate registered, by passing the integer handle rather than the bytes.
It **borrows** the native registry entry; it does not add a reference. Every
attached instance still owns reusable native scratch buffers and must be
disposed in the isolate that used it. Keep the registered owner alive until
the worker's future has completed, on success or failure:

```dart
final owner = ShaperFont.register(fontBytes);
try {
  final handle = owner.handle;
  await Isolate.run(() {
    final attached = ShaperFont.attach(handle);
    try {
      return attached.shape('123').records;
    } finally {
      attached.dispose();
    }
  });
} finally {
  owner.dispose();
}
```

The isolate example also needs `import 'dart:isolate';`. Do not release the
owner after a timeout while its worker is still running. Killing an isolate
does not execute its `finally` blocks; let it finish and clean up cooperatively.

On Linux with glibc, `dart run tool/lifecycle_probe.dart /path/to/font.ttf`
measures native allocator bytes and RSS over 30 worker lifecycles. Run it in
a separate process with `--retain-buffers` to reproduce the missing-dispose
case. The latter intentionally keeps scratch allocations until process exit;
both modes check the same shaping output after five warm-up cycles.
The allocator metric relies on glibc 2.33+ `mallinfo2`, which does **not**
include every allocator arena or the Dart heap. RSS and allocator figures are
process-level observations, not a complete leak inventory or per-font cost.
Run both modes in fresh, comparable processes and interpret deltas alongside
the reference-count lifecycle tests.

### Embedding in a PDF

A PDF that draws shaped glyphs addresses them by id (`/CIDToGIDMap
/Identity`), so the font cannot be subset by character. `subsetFontForPdf`
subsets by glyph id instead: the ids stay put, unused outlines become empty,
components of composite glyphs are kept, and only the tables a PDF renderer
reads survive. A variable font embeds its default instance, the one the shaper
measured.

```dart
final program = subsetFontForPdf(fontBytes, usedGlyphIds);
```

For the fonts it was measured on, this is ten to thirty times smaller than the
full file. CFF outlines are stripped of the other tables but not pruned glyph
by glyph.

## Building

The Rust crate in `rust/` reaches the app through the package's build hook
(`hook/build.dart`), so it needs no platform plugin code and works with Swift
Package Manager as well as CocoaPods. The hook downloads the signed binary
published for the crate's content hash and compiles it with cargo only when
none is published, which requires [Rust](https://rustup.rs). An app can force
the source build:

```yaml
hooks:
  user_defines:
    opentype_shaper:
      build_from_source: true
```

Published iOS device libraries target iOS 12, the framework minimum Flutter
3.38.1 writes, and the publisher checks the final Mach-O before signing so App
Store validation accepts them. ARM64 simulator libraries target iOS 14, Rust's
minimum for that target.

Tests need a font; `flutter test` builds the library itself:

```sh
OPENTYPE_SHAPER_TEST_FONT=/path/to/NotoSerifHebrew.ttf flutter test
```

The repository vendors no fonts. Continuous integration fetches an OFL font.

## License

MIT. See `LICENSE`.
