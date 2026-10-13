use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

use base64::Engine;
use nsm_core::net::site::TokenStore;

#[cfg(windows)]
mod dpapi {
    use windows_sys::Win32::Foundation::LocalFree;
    use windows_sys::Win32::Security::Cryptography::{CryptProtectData, CryptUnprotectData, CRYPT_INTEGER_BLOB};

    pub fn protect(data: &[u8]) -> Option<Vec<u8>> {
        unsafe {
            let input = CRYPT_INTEGER_BLOB { cbData: data.len() as u32, pbData: data.as_ptr() as *mut u8 };
            let mut output = CRYPT_INTEGER_BLOB { cbData: 0, pbData: std::ptr::null_mut() };
            let ok = CryptProtectData(&input, std::ptr::null(), std::ptr::null(), std::ptr::null(), std::ptr::null(), 0, &mut output);
            if ok == 0 || output.pbData.is_null() {
                return None;
            }
            let bytes = std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec();
            LocalFree(output.pbData as _);
            Some(bytes)
        }
    }

    pub fn unprotect(data: &[u8]) -> Option<Vec<u8>> {
        unsafe {
            let input = CRYPT_INTEGER_BLOB { cbData: data.len() as u32, pbData: data.as_ptr() as *mut u8 };
            let mut output = CRYPT_INTEGER_BLOB { cbData: 0, pbData: std::ptr::null_mut() };
            let ok = CryptUnprotectData(&input, std::ptr::null_mut(), std::ptr::null(), std::ptr::null(), std::ptr::null(), 0, &mut output);
            if ok == 0 || output.pbData.is_null() {
                return None;
            }
            let bytes = std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec();
            LocalFree(output.pbData as _);
            Some(bytes)
        }
    }
}

#[cfg(not(windows))]
mod dpapi {
    pub fn protect(data: &[u8]) -> Option<Vec<u8>> {
        Some(data.to_vec())
    }

    pub fn unprotect(data: &[u8]) -> Option<Vec<u8>> {
        Some(data.to_vec())
    }
}

pub struct DpapiStore {
    path: PathBuf,
    values: Mutex<HashMap<String, String>>,
}

impl DpapiStore {
    pub fn open(path: PathBuf) -> Self {
        let engine = base64::engine::general_purpose::STANDARD;
        let stored: HashMap<String, String> = std::fs::read_to_string(&path).ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_default();
        let mut values = HashMap::new();
        for (key, encoded) in stored {
            let plain = engine.decode(encoded).ok().and_then(|bytes| dpapi::unprotect(&bytes)).and_then(|bytes| String::from_utf8(bytes).ok());
            if let Some(plain) = plain {
                values.insert(key, plain);
            }
        }
        Self { path, values: Mutex::new(values) }
    }

    fn persist(&self, values: &HashMap<String, String>) {
        let engine = base64::engine::general_purpose::STANDARD;
        let encoded: HashMap<String, String> = values
            .iter()
            .filter_map(|(key, value)| dpapi::protect(value.as_bytes()).map(|bytes| (key.clone(), engine.encode(bytes))))
            .collect();
        if let Ok(text) = serde_json::to_string(&encoded) {
            let _ = std::fs::write(&self.path, text);
        }
    }
}

impl TokenStore for DpapiStore {
    fn get(&self, key: &str) -> Option<String> {
        self.values.lock().ok()?.get(key).cloned()
    }

    fn set(&self, key: &str, value: &str) {
        if let Ok(mut values) = self.values.lock() {
            values.insert(key.to_string(), value.to_string());
            self.persist(&values);
        }
    }

    fn remove(&self, key: &str) {
        if let Ok(mut values) = self.values.lock() {
            values.remove(key);
            self.persist(&values);
        }
    }
}
