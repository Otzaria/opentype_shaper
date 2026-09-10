//! Shaping behaviour that the Dart side and the PDF writer depend on.
//!
//! The font comes from `OPENTYPE_SHAPER_TEST_FONT`; font-dependent tests skip
//! when it is unset, so the repository needs to vendor no font of its own.

use opentype_shaper::*;

/// Hebrew letters carrying nikud and one ta'am, as escapes.
const SAMPLE: &[u16] = &[
    0x05E9, 0x05C1, 0x05B8, 0x0596, // shin + shin dot + qamats + tipeha
    0x05DC, 0x05B9, // lamed + holam
    0x05DD, // final mem
];

const HEBREW_TAG: u32 = u32::from_be_bytes(*b"hebr");

fn test_font() -> Option<Vec<u8>> {
    let path = std::env::var("OPENTYPE_SHAPER_TEST_FONT").ok()?;
    std::fs::read(path).ok()
}

fn register(bytes: &[u8]) -> i64 {
    let handle = unsafe { opentype_shaper_register_font(bytes.as_ptr(), bytes.len(), 0) };
    assert!(handle > 0, "register failed: {handle}");
    handle
}

fn shape(handle: i64, text: &[u16], rtl: bool) -> Vec<[i32; RECORD_FIELDS]> {
    let mut buffer = vec![0i32; text.len() * 4 * RECORD_FIELDS];
    let mut count = 0u32;
    let status = unsafe {
        opentype_shaper_shape(
            handle,
            text.as_ptr(),
            text.len(),
            i32::from(rtl),
            HEBREW_TAG,
            std::ptr::null(),
            0,
            std::ptr::null(),
            0,
            buffer.as_mut_ptr(),
            buffer.len() / RECORD_FIELDS,
            &mut count,
        )
    };
    assert_eq!(status, OK, "shape failed");
    (0..count as usize)
        .map(|index| {
            let base = index * RECORD_FIELDS;
            let mut record = [0i32; RECORD_FIELDS];
            record.copy_from_slice(&buffer[base..base + RECORD_FIELDS]);
            record
        })
        .collect()
}

#[test]
fn abi_surface_is_stable() {
    assert_eq!(opentype_shaper_abi_version(), ABI_VERSION);
    assert_eq!(opentype_shaper_record_fields(), RECORD_FIELDS as i32);
    assert_eq!(opentype_shaper_metric_fields(), METRIC_FIELDS as i32);
}

#[test]
fn rejects_invalid_input_without_panicking() {
    assert_eq!(
        unsafe { opentype_shaper_register_font(std::ptr::null(), 10, 0) },
        ERR_INVALID_ARG as i64
    );
    // Not a font: parsing must fail rather than abort the host process.
    let junk = [0u8; 64];
    assert_eq!(
        unsafe { opentype_shaper_register_font(junk.as_ptr(), junk.len(), 0) },
        ERR_FONT_PARSE as i64
    );
    assert_eq!(opentype_shaper_release_font(4242), ERR_UNKNOWN_HANDLE);

    let mut count = 0u32;
    assert_eq!(
        unsafe { opentype_shaper_font_metrics(4242, std::ptr::null_mut(), 0, &mut count) },
        ERR_BUFFER_TOO_SMALL
    );
    assert_eq!(count, METRIC_FIELDS as u32);
}

#[test]
fn reports_required_capacity_instead_of_truncating() {
    let Some(bytes) = test_font() else {
        return;
    };
    let handle = register(&bytes);

    let mut tiny = [0i32; RECORD_FIELDS];
    let mut count = 0u32;
    let status = unsafe {
        opentype_shaper_shape(
            handle,
            SAMPLE.as_ptr(),
            SAMPLE.len(),
            1,
            HEBREW_TAG,
            std::ptr::null(),
            0,
            std::ptr::null(),
            0,
            tiny.as_mut_ptr(),
            1,
            &mut count,
        )
    };
    assert_eq!(status, ERR_BUFFER_TOO_SMALL);
    assert!(count > 1, "needed count must be reported");

    opentype_shaper_release_font(handle);
}

#[test]
fn positions_every_mark_through_gpos() {
    let Some(bytes) = test_font() else {
        return;
    };
    let handle = register(&bytes);
    let glyphs = shape(handle, SAMPLE, true);

    assert!(!glyphs.is_empty());

    let marks: Vec<_> = glyphs.iter().filter(|record| record[2] == 0).collect();
    assert!(
        !marks.is_empty(),
        "a nikud sample must produce zero-advance marks"
    );
    // The whole point of shaping: a mark must carry an offset rather than sit at
    // the pen position, which is where an unshaped writer would draw it.
    assert!(
        marks.iter().any(|record| record[4] != 0 || record[5] != 0),
        "no mark received a GPOS offset"
    );

    opentype_shaper_release_font(handle);
}

#[test]
fn clusters_are_utf16_indices_in_visual_order() {
    let Some(bytes) = test_font() else {
        return;
    };
    let handle = register(&bytes);
    let glyphs = shape(handle, SAMPLE, true);

    for record in &glyphs {
        let cluster = record[1];
        assert!(
            cluster >= 0 && (cluster as usize) < SAMPLE.len(),
            "cluster {cluster} outside the UTF-16 input"
        );
    }

    // Right-to-left output runs from the visually leftmost glyph, so clusters
    // are non-increasing. The PDF writer relies on this to advance the pen.
    let clusters: Vec<i32> = glyphs.iter().map(|record| record[1]).collect();
    assert!(
        clusters.windows(2).all(|pair| pair[0] >= pair[1]),
        "RTL clusters must not increase: {clusters:?}"
    );

    opentype_shaper_release_font(handle);
}

#[test]
fn surrogate_pairs_keep_one_cluster() {
    let Some(bytes) = test_font() else {
        return;
    };
    let handle = register(&bytes);
    // U+1D160 is outside the BMP; it must consume both code units as one cluster.
    let text: &[u16] = &[0xD834, 0xDD60, 0x05D0];
    let glyphs = shape(handle, text, false);
    assert!(glyphs.iter().all(|record| record[1] != 1));
    opentype_shaper_release_font(handle);
}

#[test]
fn metrics_describe_the_font() {
    let Some(bytes) = test_font() else {
        return;
    };
    let handle = register(&bytes);

    let mut metrics = vec![0i32; METRIC_FIELDS];
    let mut count = 0u32;
    assert_eq!(
        unsafe {
            opentype_shaper_font_metrics(handle, metrics.as_mut_ptr(), metrics.len(), &mut count)
        },
        OK
    );
    assert_eq!(count, METRIC_FIELDS as u32);
    assert!(metrics[0] > 0, "upem");
    assert!(metrics[1] > 0, "num_glyphs");
    assert!(metrics[2] > 0, "ascender");
    assert!(metrics[3] < 0, "descender");

    // A font that shapes Hebrew marks must advertise GPOS.
    assert_ne!(metrics[14] & 1, 0, "FLAG_HAS_GPOS");

    let num_glyphs = metrics[1] as usize;
    let mut advances = vec![0u16; num_glyphs];
    assert_eq!(
        unsafe {
            opentype_shaper_glyph_advances(
                handle,
                advances.as_mut_ptr(),
                advances.len(),
                &mut count,
            )
        },
        OK
    );
    assert_eq!(count as usize, num_glyphs);

    let mut name = vec![0u8; 128];
    let status = unsafe {
        opentype_shaper_postscript_name(handle, name.as_mut_ptr(), name.len(), &mut count)
    };
    assert_eq!(status, OK);
    assert!(count > 0, "PostScript name");

    opentype_shaper_release_font(handle);
}
