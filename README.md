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

final run = font.shape('שָׁלוֹם', rtl: true, script: 'hebr');
for (var i = 0; i < run.glyphCount; i++) {
  // run.glyphId(i), run.xAdvance(i), run.xOffset(i), run.yOffset(i)
}

font.dispose();
```

Results are in font units; divide by `font.metrics.unitsPerEm` and multiply by
the point size. Glyphs of a right-to-left run come back in visual order, so a
consumer advances the pen positively while emitting them in sequence.

`ShaperFont.attach(handle)` lets a background isolate use a font the main
isolate registered, by passing the integer handle rather than the bytes.

## Building

The Rust crate lives in `rust/` and is built by
[cargokit](https://github.com/irondash/cargokit) as part of the Flutter build.
Until precompiled binaries are published, a Rust toolchain is required. Adding
`rust/cargokit.yaml` with a `precompiled_binaries` block (release URL prefix and
the signing public key) switches consumers to downloading them instead; the
file must then hold that block, because cargokit rejects an empty one.

Tests need the compiled library and a font:

```sh
cargo build --release --manifest-path rust/Cargo.toml
OPENTYPE_SHAPER_TEST_FONT=/path/to/NotoSerifHebrew.ttf flutter test
```

The repository vendors no fonts. Continuous integration fetches an OFL font.

## License

MIT. See `LICENSE`.
