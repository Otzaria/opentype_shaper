//! Regression tests for thread-local buffer reuse. A fresh OS thread has a
//! fresh buffer, so it supplies a reference for alternating segment properties.

use opentype_shaper::*;

#[derive(Clone)]
struct Case {
    text: Vec<u16>,
    rtl: bool,
    script: u32,
    language: &'static str,
    features: &'static str,
}

fn font_bytes() -> Option<Vec<u8>> {
    let path = std::env::var("OPENTYPE_SHAPER_TEST_FONT").ok()?;
    std::fs::read(path).ok()
}

fn shape(handle: i64, case: &Case) -> Vec<i32> {
    let mut out = vec![0i32; case.text.len().max(1) * 4 * RECORD_FIELDS];
    let mut count = 0u32;
    let status = unsafe {
        opentype_shaper_shape(
            handle,
            case.text.as_ptr(),
            case.text.len(),
            i32::from(case.rtl),
            case.script,
            case.language.as_ptr(),
            case.language.len(),
            case.features.as_ptr(),
            case.features.len(),
            out.as_mut_ptr(),
            out.len() / RECORD_FIELDS,
            &mut count,
        )
    };
    assert_eq!(status, OK, "unexpected shaping status: {status}");
    out.truncate(count as usize * RECORD_FIELDS);
    out
}

fn cases() -> Vec<Case> {
    let hebrew = "שָׁ֖לוֹם".encode_utf16().collect();
    let latin = "Hello ABC 123".encode_utf16().collect();
    let mut cases = vec![
        Case {
            text: hebrew,
            rtl: true,
            script: u32::from_be_bytes(*b"hebr"),
            language: "he",
            features: "",
        },
        Case {
            text: latin,
            rtl: false,
            script: u32::from_be_bytes(*b"latn"),
            language: "en",
            features: "-liga",
        },
        Case {
            text: "אבג 123".encode_utf16().collect(),
            rtl: true,
            script: 0,
            language: "",
            features: "",
        },
        Case {
            text: "abc 123".encode_utf16().collect(),
            rtl: false,
            script: 0,
            language: "",
            features: "",
        },
        Case {
            text: "שָׁ֖לוֹם".encode_utf16().collect(),
            rtl: true,
            script: u32::from_be_bytes(*b"hebr"),
            language: "",
            features: "-mark",
        },
    ];
    for length in [4096, 4097] {
        let mut case = cases[0].clone();
        case.text = vec![0x05E9; length];
        cases.push(case);
    }
    let mut case = cases[1].clone();
    case.text = vec![0xD83D, 0xDE00, 0xD800, 0x0061, 0xDC00];
    cases.push(case);
    cases
}

#[test]
fn alternating_scripts_languages_and_features_match_fresh_threads() {
    let Some(font) = font_bytes() else {
        return;
    };
    let handle = unsafe { opentype_shaper_register_font(font.as_ptr(), font.len(), 0) };
    assert!(handle > 0);

    let cases = cases();
    let expected: Vec<Vec<i32>> = cases
        .iter()
        .cloned()
        .map(|case| {
            std::thread::spawn(move || shape(handle, &case))
                .join()
                .unwrap()
        })
        .collect();

    for _ in 0..20 {
        for (case, baseline) in cases.iter().zip(&expected) {
            assert_eq!(&shape(handle, case), baseline);
        }
    }
    assert_eq!(opentype_shaper_release_font(handle), OK);
}

#[test]
fn buffer_too_small_retry_and_concurrent_workers_keep_output_stable() {
    let Some(font) = font_bytes() else {
        return;
    };
    let handle = unsafe { opentype_shaper_register_font(font.as_ptr(), font.len(), 0) };
    assert!(handle > 0);
    let case = cases().remove(0);
    let expected = shape(handle, &case);

    let mut small = [0i32; RECORD_FIELDS];
    let mut count = 0u32;
    let status = unsafe {
        opentype_shaper_shape(
            handle,
            case.text.as_ptr(),
            case.text.len(),
            1,
            case.script,
            std::ptr::null(),
            0,
            std::ptr::null(),
            0,
            small.as_mut_ptr(),
            1,
            &mut count,
        )
    };
    assert_eq!(status, ERR_BUFFER_TOO_SMALL);
    assert!(count > 1);
    assert_eq!(shape(handle, &case), expected);

    let workers: Vec<_> = (0..8)
        .map(|_| {
            let case = case.clone();
            let expected = expected.clone();
            std::thread::spawn(move || {
                for _ in 0..100 {
                    assert_eq!(shape(handle, &case), expected);
                }
            })
        })
        .collect();
    for worker in workers {
        worker.join().unwrap();
    }
    assert_eq!(opentype_shaper_release_font(handle), OK);
}
