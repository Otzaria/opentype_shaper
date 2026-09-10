//! Font-level values Dart needs for line layout and for writing a PDF
//! `/FontDescriptor`. Everything is in font units; Dart scales by `upem`.

use harfrust::FontRef;
use read_fonts::TableProvider;

use crate::METRIC_FIELDS;

pub const FLAG_HAS_GPOS: i32 = 1 << 0;
pub const FLAG_HAS_GSUB: i32 = 1 << 1;
pub const FLAG_HAS_GDEF: i32 = 1 << 2;
pub const FLAG_IS_ITALIC: i32 = 1 << 3;
pub const FLAG_IS_SERIF: i32 = 1 << 4;

/// Writes [`METRIC_FIELDS`] values into `out`. Field order is mirrored by
/// `FontMetrics` on the Dart side; append only, never reorder.
pub fn collect(font: &FontRef<'_>, out: &mut [i32]) -> Result<(), ()> {
    debug_assert!(out.len() >= METRIC_FIELDS);

    let head = font.head().map_err(|_| ())?;
    let upem = head.units_per_em();
    if upem == 0 {
        return Err(());
    }

    let num_glyphs = font.maxp().map(|m| m.num_glyphs()).unwrap_or(0);
    let hhea = font.hhea().ok();
    let os2 = font.os2().ok();
    let post = font.post().ok();

    let mut flags = 0;
    if font.gpos().is_ok() {
        flags |= FLAG_HAS_GPOS;
    }
    if font.gsub().is_ok() {
        flags |= FLAG_HAS_GSUB;
    }
    if font.gdef().is_ok() {
        flags |= FLAG_HAS_GDEF;
    }
    // mac_style bit 1 is italic; OS/2 fs_selection bit 0 says the same.
    if head.mac_style().bits() & 0x0002 != 0 {
        flags |= FLAG_IS_ITALIC;
    }
    if let Some(os2) = os2.as_ref() {
        let family_class = (os2.s_family_class() >> 8) as u8;
        // Classes 1-7 are the serif families in the OS/2 registry.
        if (1..=7).contains(&family_class) {
            flags |= FLAG_IS_SERIF;
        }
    }

    let italic_angle = post
        .as_ref()
        .map(|p| p.italic_angle().to_f32())
        .unwrap_or(0.0);

    out[0] = upem as i32;
    out[1] = num_glyphs as i32;
    out[2] = hhea.as_ref().map(|h| h.ascender().to_i16()).unwrap_or(0) as i32;
    out[3] = hhea.as_ref().map(|h| h.descender().to_i16()).unwrap_or(0) as i32;
    out[4] = hhea.as_ref().map(|h| h.line_gap().to_i16()).unwrap_or(0) as i32;
    out[5] = head.x_min() as i32;
    out[6] = head.y_min() as i32;
    out[7] = head.x_max() as i32;
    out[8] = head.y_max() as i32;
    out[9] = os2.as_ref().and_then(|o| o.s_cap_height()).unwrap_or(0) as i32;
    out[10] = os2.as_ref().and_then(|o| o.sx_height()).unwrap_or(0) as i32;
    out[11] = (italic_angle * 100.0).round() as i32;
    out[12] = post.as_ref().map(|p| p.is_fixed_pitch()).unwrap_or(0) as i32;
    out[13] = os2.as_ref().map(|o| o.us_weight_class()).unwrap_or(400) as i32;
    out[14] = flags;
    out[15] = os2.as_ref().map(|o| o.s_typo_ascender()).unwrap_or(0) as i32;
    out[16] = os2.as_ref().map(|o| o.s_typo_descender()).unwrap_or(0) as i32;

    Ok(())
}

/// Advance width per glyph id, in font units.
pub fn glyph_advances(font: &FontRef<'_>, out: &mut [u16]) -> Result<usize, ()> {
    let num_glyphs = font.maxp().map_err(|_| ())?.num_glyphs() as usize;
    let hmtx = font.hmtx().map_err(|_| ())?;
    let count = num_glyphs.min(out.len());
    for (gid, slot) in out[..count].iter_mut().enumerate() {
        *slot = hmtx
            .advance(read_fonts::types::GlyphId::new(gid as u32))
            .unwrap_or(0);
    }
    Ok(count)
}

/// The PostScript name (name id 6), which becomes the PDF `/BaseFont`.
pub fn postscript_name(font: &FontRef<'_>) -> Option<String> {
    let name = font.name().ok()?;
    let data = name.string_data();
    let mut fallback = None;
    for record in name.name_record() {
        if record.name_id() != read_fonts::types::NameId::POSTSCRIPT_NAME {
            continue;
        }
        let Ok(string) = record.string(data) else {
            continue;
        };
        let text: String = string.chars().collect();
        if text.is_empty() {
            continue;
        }
        // Prefer the Windows/Unicode record, but take anything rather than none.
        if record.platform_id() == 3 {
            return Some(text);
        }
        fallback.get_or_insert(text);
    }
    fallback
}
