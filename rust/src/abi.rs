//! The C ABI.
//!
//! Every entry point catches panics and returns an error code: book printing
//! shapes user-installed system fonts, so a malformed font must not abort the
//! host process. Buffer-filling calls report the required length through
//! `out_count` alongside [`ERR_BUFFER_TOO_SMALL`], so the caller can grow a
//! reusable scratch buffer instead of allocating per call.

use std::panic::{catch_unwind, AssertUnwindSafe};

use crate::metrics;
use crate::registry;
use crate::shape::{self, ShapeOutcome, ShapeRequest};
use crate::{
    ERR_BUFFER_TOO_SMALL, ERR_FONT_PARSE, ERR_INVALID_ARG, ERR_PANIC, ERR_TABLE_MISSING,
    ERR_UNKNOWN_HANDLE, METRIC_FIELDS, OK, RECORD_FIELDS,
};

fn guard<F: FnOnce() -> i32>(body: F) -> i32 {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(ERR_PANIC)
}

/// # Safety
/// `ptr` must be null or point to `len` readable elements.
unsafe fn slice<'a, T>(ptr: *const T, len: usize) -> Option<&'a [T]> {
    if len == 0 {
        return Some(&[]);
    }
    if ptr.is_null() {
        return None;
    }
    Some(std::slice::from_raw_parts(ptr, len))
}

/// # Safety
/// `ptr` must be null or point to `len` writable elements.
unsafe fn slice_mut<'a, T>(ptr: *mut T, len: usize) -> Option<&'a mut [T]> {
    if len == 0 {
        return Some(&mut []);
    }
    if ptr.is_null() {
        return None;
    }
    Some(std::slice::from_raw_parts_mut(ptr, len))
}

/// # Safety
/// `ptr` must be null or point to `len` readable bytes holding UTF-8.
unsafe fn utf8<'a>(ptr: *const u8, len: usize) -> Option<&'a str> {
    if len == 0 || ptr.is_null() {
        return None;
    }
    std::str::from_utf8(std::slice::from_raw_parts(ptr, len)).ok()
}

#[no_mangle]
pub extern "C" fn opentype_shaper_abi_version() -> i32 {
    crate::ABI_VERSION
}

/// Int32 fields per shaped glyph, so the caller can size its buffer without
/// hardcoding the layout.
#[no_mangle]
pub extern "C" fn opentype_shaper_record_fields() -> i32 {
    RECORD_FIELDS as i32
}

#[no_mangle]
pub extern "C" fn opentype_shaper_metric_fields() -> i32 {
    METRIC_FIELDS as i32
}

/// Registers font bytes and returns a handle above zero, or a negative error
/// code. Identical bytes return the existing handle and add a reference.
///
/// # Safety
/// `data` must point to `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn opentype_shaper_register_font(
    data: *const u8,
    len: usize,
    face_index: u32,
) -> i64 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let Some(bytes) = slice(data, len) else {
            return ERR_INVALID_ARG as i64;
        };
        if bytes.is_empty() {
            return ERR_INVALID_ARG as i64;
        }
        match registry::register(bytes, face_index) {
            Ok(handle) => handle,
            Err(()) => ERR_FONT_PARSE as i64,
        }
    }));
    result.unwrap_or(ERR_PANIC as i64)
}

#[no_mangle]
pub extern "C" fn opentype_shaper_release_font(handle: i64) -> i32 {
    guard(|| match registry::release(handle) {
        Ok(()) => OK,
        Err(()) => ERR_UNKNOWN_HANDLE,
    })
}

/// # Safety
/// `out` must point to `cap` writable ints; `out_count` must be writable.
#[no_mangle]
pub unsafe extern "C" fn opentype_shaper_font_metrics(
    handle: i64,
    out: *mut i32,
    cap: usize,
    out_count: *mut u32,
) -> i32 {
    guard(|| {
        if out_count.is_null() {
            return ERR_INVALID_ARG;
        }
        *out_count = METRIC_FIELDS as u32;
        if cap < METRIC_FIELDS {
            return ERR_BUFFER_TOO_SMALL;
        }
        let Some(buffer) = slice_mut(out, cap) else {
            return ERR_INVALID_ARG;
        };
        let Some(entry) = registry::get(handle) else {
            return ERR_UNKNOWN_HANDLE;
        };
        let Ok(font) = entry.font() else {
            return ERR_FONT_PARSE;
        };
        match metrics::collect(&font, buffer) {
            Ok(()) => OK,
            Err(()) => ERR_TABLE_MISSING,
        }
    })
}

/// # Safety
/// `out` must point to `cap` writable u16 values; `out_count` must be writable.
#[no_mangle]
pub unsafe extern "C" fn opentype_shaper_glyph_advances(
    handle: i64,
    out: *mut u16,
    cap: usize,
    out_count: *mut u32,
) -> i32 {
    guard(|| {
        if out_count.is_null() {
            return ERR_INVALID_ARG;
        }
        *out_count = 0;
        let Some(entry) = registry::get(handle) else {
            return ERR_UNKNOWN_HANDLE;
        };
        let Ok(font) = entry.font() else {
            return ERR_FONT_PARSE;
        };
        let Ok(maxp) = read_fonts::TableProvider::maxp(&font) else {
            return ERR_TABLE_MISSING;
        };
        let needed = maxp.num_glyphs() as usize;
        *out_count = needed as u32;
        if cap < needed {
            return ERR_BUFFER_TOO_SMALL;
        }
        let Some(buffer) = slice_mut(out, cap) else {
            return ERR_INVALID_ARG;
        };
        match metrics::glyph_advances(&font, buffer) {
            Ok(written) => {
                *out_count = written as u32;
                OK
            }
            Err(()) => ERR_TABLE_MISSING,
        }
    })
}

/// # Safety
/// `out` must point to `cap` writable bytes; `out_count` must be writable.
#[no_mangle]
pub unsafe extern "C" fn opentype_shaper_postscript_name(
    handle: i64,
    out: *mut u8,
    cap: usize,
    out_count: *mut u32,
) -> i32 {
    guard(|| {
        if out_count.is_null() {
            return ERR_INVALID_ARG;
        }
        *out_count = 0;
        let Some(entry) = registry::get(handle) else {
            return ERR_UNKNOWN_HANDLE;
        };
        let Ok(font) = entry.font() else {
            return ERR_FONT_PARSE;
        };
        let Some(name) = metrics::postscript_name(&font) else {
            return ERR_TABLE_MISSING;
        };
        let bytes = name.as_bytes();
        *out_count = bytes.len() as u32;
        if cap < bytes.len() {
            return ERR_BUFFER_TOO_SMALL;
        }
        let Some(buffer) = slice_mut(out, cap) else {
            return ERR_INVALID_ARG;
        };
        buffer[..bytes.len()].copy_from_slice(bytes);
        OK
    })
}

/// Shapes one run. Writes [`RECORD_FIELDS`] ints per glyph into `out` and the
/// glyph count into `out_count`.
///
/// # Safety
/// All pointers must be null or point to the number of elements declared.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn opentype_shaper_shape(
    handle: i64,
    text: *const u16,
    text_len: usize,
    rtl: i32,
    script_tag: u32,
    language: *const u8,
    language_len: usize,
    features: *const u8,
    features_len: usize,
    out: *mut i32,
    out_cap_records: usize,
    out_count: *mut u32,
) -> i32 {
    guard(|| {
        if out_count.is_null() {
            return ERR_INVALID_ARG;
        }
        *out_count = 0;
        let Some(units) = slice(text, text_len) else {
            return ERR_INVALID_ARG;
        };
        if units.is_empty() {
            return OK;
        }
        let Some(buffer) = slice_mut(out, out_cap_records * RECORD_FIELDS) else {
            return ERR_INVALID_ARG;
        };
        let Some(entry) = registry::get(handle) else {
            return ERR_UNKNOWN_HANDLE;
        };
        let request = ShapeRequest {
            text: units,
            rtl: rtl != 0,
            script_tag,
            language: utf8(language, language_len),
            features: utf8(features, features_len),
        };
        match shape::shape(&entry, request, buffer) {
            Ok(ShapeOutcome::Written(count)) => {
                *out_count = count as u32;
                OK
            }
            Ok(ShapeOutcome::NeedsCapacity(count)) => {
                *out_count = count as u32;
                ERR_BUFFER_TOO_SMALL
            }
            Err(()) => ERR_FONT_PARSE,
        }
    })
}
