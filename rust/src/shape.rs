//! Shaping one run of text.

use std::str::FromStr;

use harfrust::{Direction, Feature, Language, Script, ShapeOptions, Tag, UnicodeBuffer};

use crate::registry::FontEntry;
use crate::RECORD_FIELDS;

pub struct ShapeRequest<'a> {
    /// UTF-16 code units, as Dart stores strings.
    pub text: &'a [u16],
    pub rtl: bool,
    /// Big-endian ISO 15924 tag, or 0 to let the shaper guess.
    pub script_tag: u32,
    pub language: Option<&'a str>,
    /// Comma-separated OpenType feature list, e.g. `-liga,+dlig`.
    pub features: Option<&'a str>,
}

pub enum ShapeOutcome {
    /// Number of glyph records written to the caller's buffer.
    Written(usize),
    /// The buffer was too small; this many records are needed.
    NeedsCapacity(usize),
}

/// Decodes UTF-16 into the buffer, keeping each glyph's cluster equal to the
/// UTF-16 index of its first code unit so Dart can map glyphs back to string
/// offsets without re-encoding.
fn fill_buffer(text: &[u16], buffer: &mut UnicodeBuffer) {
    let mut index = 0usize;
    while index < text.len() {
        let unit = text[index];
        let cluster = index as u32;
        let (codepoint, consumed) = if (0xD800..0xDC00).contains(&unit) && index + 1 < text.len() {
            let low = text[index + 1];
            if (0xDC00..0xE000).contains(&low) {
                let value = 0x10000 + (((unit as u32) - 0xD800) << 10) + ((low as u32) - 0xDC00);
                (value, 2)
            } else {
                (unit as u32, 1)
            }
        } else {
            (unit as u32, 1)
        };
        // Lone surrogates cannot be a char; U+FFFD keeps clusters aligned.
        let ch = char::from_u32(codepoint).unwrap_or('\u{FFFD}');
        buffer.add(ch, cluster);
        index += consumed;
    }
}

fn parse_features(spec: Option<&str>) -> Vec<Feature> {
    let Some(spec) = spec else {
        return Vec::new();
    };
    spec.split(',')
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .filter_map(|part| Feature::from_str(part).ok())
        .collect()
}

pub fn shape(
    entry: &FontEntry,
    request: ShapeRequest<'_>,
    out: &mut [i32],
) -> Result<ShapeOutcome, ()> {
    let font = entry.font()?;
    let shaper = entry.shaper_data().shaper(&font).build();

    let mut buffer = UnicodeBuffer::new();
    buffer.reserve(request.text.len());
    fill_buffer(request.text, &mut buffer);

    buffer.set_direction(if request.rtl {
        Direction::RightToLeft
    } else {
        Direction::LeftToRight
    });
    if request.script_tag != 0 {
        if let Some(script) = Script::from_iso15924_tag(Tag::from_u32(request.script_tag)) {
            buffer.set_script(script);
        }
    }
    if let Some(language) = request.language.and_then(Language::new) {
        buffer.set_language(language);
    }
    if request.script_tag == 0 {
        buffer.guess_segment_properties();
    }

    let features = parse_features(request.features);
    let glyphs = shaper.shape(buffer, ShapeOptions::default().features(&features));

    let infos = glyphs.glyph_infos();
    let positions = glyphs.glyph_positions();
    let count = infos.len().min(positions.len());

    if out.len() < count * RECORD_FIELDS {
        return Ok(ShapeOutcome::NeedsCapacity(count));
    }

    for (index, (info, position)) in infos.iter().zip(positions.iter()).enumerate() {
        let base = index * RECORD_FIELDS;
        out[base] = info.glyph_id as i32;
        out[base + 1] = info.cluster as i32;
        out[base + 2] = position.x_advance;
        out[base + 3] = position.y_advance;
        out[base + 4] = position.x_offset;
        out[base + 5] = position.y_offset;
    }

    Ok(ShapeOutcome::Written(count))
}
