## 0.3.2

- Added an example (`example/main.dart`) that shapes a Hebrew word and subsets
  the font for a PDF.

## 0.3.1

- Precompiled iOS device libraries target iOS 12, the framework minimum Flutter
  3.38.1 writes, so App Store validation accepts them; the publisher checks the
  final Mach-O before signing. ARM64 simulator libraries target iOS 14.
- The build hook compiles only the library (`cargo build --lib`).

## 0.3.0

- **Breaking:** the native library is built and bundled by a Dart build hook
  (native assets) instead of cargokit, so apps can enable Swift Package
  Manager. The hook downloads the signed precompiled binary for the crate and
  falls back to cargo only when none is published; set
  `hooks: user_defines: opentype_shaper: build_from_source: true` to force a
  source build.
- **Breaking:** `ShaperLibrary.path` is removed. The bindings use `@Native`
  and load in every isolate, including `flutter test` on the host.
- Requires Flutter 3.38.1 or later.

## 0.2.0

- `subsetFontForPdf`: a PDF font program subset by glyph id, keeping ids in
  place and dropping the shaping, variation and naming tables a PDF never reads.
- Shape plans are cached per font instead of rebuilt on every call: 1.3 to 5
  times faster per Hebrew word in measurement.
- The shaping call is a leaf FFI call, and the language and feature strings are
  encoded once per font instead of on every call.

## 0.1.1

- Precompiled, signed native binaries for every platform; consumers no longer
  need a Rust toolchain. Removed the empty `cargokit.yaml` that broke the build.

## 0.1.0

- Initial release: GSUB and GPOS shaping through HarfRust over a C ABI.
- `ShaperFont.register` / `attach`, `shape` returning glyph ids with per-glyph
  offsets and advances in font units, cluster mapping back to UTF-16 offsets.
- Font metrics, glyph advances and PostScript name for PDF font embedding.
