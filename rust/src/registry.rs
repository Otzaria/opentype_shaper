//! Process-wide font registry.
//!
//! An entry owns its bytes and the parsed [`ShaperData`], which is the only
//! expensive step (~60us; building a `FontRef` and a `Shaper` per shaping call
//! measured free, so neither is cached and the entry needs no self-reference).

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, OnceLock, RwLock};

use harfrust::{FontRef, ShaperData};

pub struct FontEntry {
    data: Box<[u8]>,
    face_index: u32,
    shaper_data: ShaperData,
    /// Identity of the bytes, so re-registering the same font reuses the entry.
    fingerprint: u64,
}

impl FontEntry {
    pub fn font(&self) -> Result<FontRef<'_>, ()> {
        FontRef::from_index(&self.data, self.face_index).map_err(|_| ())
    }

    pub fn shaper_data(&self) -> &ShaperData {
        &self.shaper_data
    }
}

struct Registry {
    handles: HashMap<i64, Arc<FontEntry>>,
    /// fingerprint -> (handle, reference count)
    by_fingerprint: HashMap<u64, (i64, u32)>,
}

fn registry() -> &'static RwLock<Registry> {
    static REGISTRY: OnceLock<RwLock<Registry>> = OnceLock::new();
    REGISTRY.get_or_init(|| {
        RwLock::new(Registry {
            handles: HashMap::new(),
            by_fingerprint: HashMap::new(),
        })
    })
}

fn next_handle() -> i64 {
    static NEXT: AtomicI64 = AtomicI64::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

fn fingerprint(data: &[u8], face_index: u32) -> u64 {
    // Hashes every byte on purpose: a sampled hash could share one entry between
    // two different fonts of equal length, which would shape with the wrong font
    // silently. Registration happens a handful of times per session.
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    face_index.hash(&mut hasher);
    data.hash(&mut hasher);
    hasher.finish()
}

/// Registers `data`, returning a positive handle. Identical bytes reuse the
/// existing entry and bump its reference count.
pub fn register(data: &[u8], face_index: u32) -> Result<i64, ()> {
    let fp = fingerprint(data, face_index);

    {
        let mut reg = registry().write().map_err(|_| ())?;
        if let Some((handle, count)) = reg.by_fingerprint.get_mut(&fp) {
            *count += 1;
            return Ok(*handle);
        }
    }

    let owned: Box<[u8]> = data.to_vec().into_boxed_slice();
    let shaper_data = {
        let font = FontRef::from_index(&owned, face_index).map_err(|_| ())?;
        ShaperData::new(&font)
    };

    let entry = Arc::new(FontEntry {
        data: owned,
        face_index,
        shaper_data,
        fingerprint: fp,
    });

    let mut reg = registry().write().map_err(|_| ())?;
    // Another thread may have registered the same bytes while we parsed.
    if let Some((handle, count)) = reg.by_fingerprint.get_mut(&fp) {
        *count += 1;
        return Ok(*handle);
    }
    let handle = next_handle();
    reg.handles.insert(handle, entry);
    reg.by_fingerprint.insert(fp, (handle, 1));
    Ok(handle)
}

/// Drops one reference. The entry is freed once the last one goes.
pub fn release(handle: i64) -> Result<(), ()> {
    let mut reg = registry().write().map_err(|_| ())?;
    let entry = match reg.handles.get(&handle) {
        Some(entry) => entry.clone(),
        None => return Err(()),
    };
    let fp = entry.fingerprint;
    drop(entry);

    let remove = match reg.by_fingerprint.get_mut(&fp) {
        Some((_, count)) => {
            *count = count.saturating_sub(1);
            *count == 0
        }
        None => true,
    };
    if remove {
        reg.by_fingerprint.remove(&fp);
        reg.handles.remove(&handle);
    }
    Ok(())
}

pub fn get(handle: i64) -> Option<Arc<FontEntry>> {
    registry().read().ok()?.handles.get(&handle).cloned()
}
