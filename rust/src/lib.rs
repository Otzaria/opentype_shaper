//! OpenType text shaping for Otzaria, exposed over a plain C ABI.
//!
//! Hebrew with nikud and te'amim needs GPOS mark positioning, which no Dart PDF
//! or text library performs. This crate hands Dart the shaped result: a glyph id
//! plus an offset and advance per glyph, in font units.

mod abi;
mod metrics;
mod registry;
mod shape;

pub use abi::*;

/// Bumped whenever the ABI changes shape. Dart refuses to load a mismatch.
pub const ABI_VERSION: i32 = 1;

/// Int32 fields written per shaped glyph.
pub const RECORD_FIELDS: usize = 6;

/// Int32 fields written by [`abi::otzaria_shaper_font_metrics`].
pub const METRIC_FIELDS: usize = 17;

pub const OK: i32 = 0;
pub const ERR_INVALID_ARG: i32 = -1;
pub const ERR_FONT_PARSE: i32 = -2;
pub const ERR_UNKNOWN_HANDLE: i32 = -3;
pub const ERR_PANIC: i32 = -4;
pub const ERR_TABLE_MISSING: i32 = -5;
pub const ERR_BUFFER_TOO_SMALL: i32 = -10;
