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
