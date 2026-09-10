//! Reference counting in the font registry.
//!
//! Its own integration test file on purpose: the registry is process-wide and
//! tests inside one file run concurrently, so reference-count assertions must
//! not share a process with tests that register the same font.

use opentype_shaper::*;

fn test_font() -> Option<Vec<u8>> {
    let path = std::env::var("OPENTYPE_SHAPER_TEST_FONT").ok()?;
    std::fs::read(path).ok()
}

fn register(bytes: &[u8]) -> i64 {
    let handle = unsafe { opentype_shaper_register_font(bytes.as_ptr(), bytes.len(), 0) };
    assert!(handle > 0, "register failed: {handle}");
    handle
}

#[test]
fn registering_identical_bytes_reuses_one_handle() {
    let Some(bytes) = test_font() else {
        return;
    };
    let first = register(&bytes);
    let second = register(&bytes);
    assert_eq!(first, second, "identical bytes must share an entry");

    // One release leaves the entry alive for the other reference.
    assert_eq!(opentype_shaper_release_font(first), OK);
    let mut metrics = vec![0i32; METRIC_FIELDS];
    let mut count = 0u32;
    assert_eq!(
        unsafe {
            opentype_shaper_font_metrics(second, metrics.as_mut_ptr(), metrics.len(), &mut count)
        },
        OK
    );
    assert_eq!(opentype_shaper_release_font(second), OK);
    assert_eq!(opentype_shaper_release_font(second), ERR_UNKNOWN_HANDLE);
}
