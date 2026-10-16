use tauri::WebviewWindow;

const CAPTION: u32 = 0x000a_0a0a;
const CAPTION_TEXT: u32 = 0x00c8_c8c8;
const BORDER: u32 = 0x0024_2424;

#[cfg(windows)]
pub fn paint_title_bar(window: &WebviewWindow) {
    use windows_sys::Win32::Foundation::HWND;
    use windows_sys::Win32::Graphics::Dwm::{DwmSetWindowAttribute, DWMWA_BORDER_COLOR, DWMWA_CAPTION_COLOR, DWMWA_TEXT_COLOR};

    let Ok(handle) = window.hwnd() else {
        return;
    };
    let hwnd = handle.0 as HWND;
    for (attribute, color) in [(DWMWA_CAPTION_COLOR, CAPTION), (DWMWA_TEXT_COLOR, CAPTION_TEXT), (DWMWA_BORDER_COLOR, BORDER)] {
        unsafe {
            DwmSetWindowAttribute(hwnd, attribute as u32, &color as *const u32 as *const std::ffi::c_void, std::mem::size_of::<u32>() as u32);
        }
    }
}

#[cfg(not(windows))]
pub fn paint_title_bar(_window: &WebviewWindow) {}
