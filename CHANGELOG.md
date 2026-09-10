## 0.1.1

- Precompiled, signed native binaries for every platform; consumers no longer
  need a Rust toolchain. Removed the empty `cargokit.yaml` that broke the build.

## 0.1.0

- Initial release: GSUB and GPOS shaping through HarfRust over a C ABI.
- `ShaperFont.register` / `attach`, `shape` returning glyph ids with per-glyph
  offsets and advances in font units, cluster mapping back to UTF-16 offsets.
- Font metrics, glyph advances and PostScript name for PDF font embedding.
