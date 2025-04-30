use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex},
    thread::sleep,
    time::Duration,
};

use windows::{
    core::*,
    Win32::{
        Foundation::{HWND, LPARAM, WPARAM},
        Graphics::Gdi::{
            BitBlt, CreateCompatibleBitmap, CreateCompatibleDC, DeleteDC, DeleteObject, GetDC, GetPixel, ReleaseDC, SelectObject, SRCCOPY
        },
        UI::{
            Input::KeyboardAndMouse::{VIRTUAL_KEY, VK_F1, VK_F2},
            WindowsAndMessaging::{
                PostMessageW, WM_KEYDOWN, WM_KEYUP,
                IsWindow, EnumWindows, GetWindowTextLengthW, GetWindowTextW
            },
        },
    },
};

// Define a wrapper type for HWND to make it hashable
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct HwndWrapper(HWND);

impl std::hash::Hash for HwndWrapper {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.0.0.hash(state);
    }
}

// Manually implement Send for HwndWrapper
unsafe impl Send for HwndWrapper {}

const PixelX: i32 = 0;
const PixelY: i32 = 0;

// Static mutable vector to collect HWNDs during window enumeration
static mut HWNDS: Vec<HWND> = vec![];

// Helper function to get all windows with a specific title
fn find_all_windows_with_title() -> Vec<HWND> {
    unsafe {
        // Clear the static vector before enumerating
        HWNDS.clear();

        EnumWindows(Some(enum_window_callback), LPARAM(0));

        // Return a copy of collected HWNDs
        HWNDS.clone()
    }
}

// Callback for EnumWindows to collect hwnds matching the target title
unsafe extern "system" fn enum_window_callback(hwnd: HWND, _: LPARAM) -> BOOL {
    let len = GetWindowTextLengthW(hwnd);

    if len > 0 {
        let mut title_buf = vec![0u16; (len + 1) as usize];
        GetWindowTextW(hwnd, &mut title_buf);

        let title_str = String::from_utf16_lossy(&title_buf);
        if title_str == "World of Warcraft\0" {
            HWNDS.push(hwnd);
        }
    }

    windows::core::BOOL::from(true)
}

fn main() {
    unsafe {
        // Initialize scancode mapping
        let mut scancode_map: HashMap<u8, VIRTUAL_KEY> = HashMap::new();
        scancode_map.insert(0x00, VK_F1);  // Red = 0 → 'F1' key
        scancode_map.insert(0x01, VK_F2);  // Red = 255 → 'F2' key

        let scancode_map_arc = Arc::new(Mutex::new(scancode_map));

        // Track currently active HWNDs using our wrapper type
        let hwnd_set: Arc<Mutex<HashSet<HwndWrapper>>> = Arc::new(Mutex::new(HashSet::new()));

        // Start the watcher thread
        std::thread::spawn(move || {
            loop {
                sleep(Duration::from_millis(100));

                // Find all current windows with target title
                let hwnds = find_all_windows_with_title();

                for &hwnd in &hwnds {
                    let mut set = hwnd_set.lock().unwrap();
                    let wrapped = HwndWrapper(hwnd);
                    if !set.contains(&wrapped) {
                        println!("Spawning new handler thread");
                        set.insert(wrapped);

                        // Spawn a new thread to handle this HWND
                        let scancode_arc_clone = Arc::clone(&scancode_map_arc);
                        std::thread::spawn(move || process_window(wrapped, &scancode_arc_clone));
                    }
                }
            }
        });

        // Keep main thread alive (to prevent early exit)
        loop {
            sleep(Duration::from_secs(1));
        }
    }
}

// Process a single HWND
fn process_window(wrapped: HwndWrapper, scancode_map_arc: &Arc<Mutex<HashMap<u8, VIRTUAL_KEY>>>) {
    let hwnd = wrapped.0;
    unsafe {
        loop {
            // Check if the window still exists
            let is_valid: BOOL = IsWindow(Some(hwnd)).into();
            if !is_valid.as_bool() {
                break;
            }

            // Get device context for this window
            let hdc_target = GetDC(Some(hwnd));
            if hdc_target.is_invalid() {
                break;
            }

            // Create memory DC and compatible bitmap
            let hdc_mem_dc = CreateCompatibleDC(Some(hdc_target));
            if hdc_mem_dc.is_invalid() {
                ReleaseDC(Some(hwnd), hdc_target);
                break;
            }

            let hbm_screen_cap = CreateCompatibleBitmap(hdc_target, 1, 1);
            if hbm_screen_cap.is_invalid() {
                DeleteDC(hdc_mem_dc);
                ReleaseDC(Some(hwnd), hdc_target);
                break;
            }

            // Select the bitmap into memory DC
            SelectObject(hdc_mem_dc, hbm_screen_cap.into());

            loop {
                // Copy pixel to memory DC
                if BitBlt(
                    hdc_mem_dc,
                    0,
                    0,
                    1,
                    1,
                    Some(hdc_target),
                    PixelX,
                    PixelY,
                    SRCCOPY,
                ).is_err() {
                    break;
                }

                // Get the pixel color (in BGR format)
                let actual_color = GetPixel(hdc_mem_dc, 0, 0);

                // Extract red component
                let blue = ((actual_color.0 >> 24) & 0xFF) as u8;
                let red = (actual_color.0 & 0xFF) as u8;

                // Press the corresponding key if found in map
                let scancode_map = scancode_map_arc.lock().unwrap();
                if let Some(&scancode) = scancode_map.get(&red) {
                    PostMessageW(
                        Some(hwnd),
                        WM_KEYDOWN as u32,
                        WPARAM(scancode.0.into()),
                        LPARAM(0)
                    );
                    // print!("Sending key {:x}")
                    sleep(Duration::from_millis(10));
                    PostMessageW(
                        Some(hwnd),
                        WM_KEYUP as u32,
                        WPARAM(scancode.0.into()),
                        LPARAM(0)
                    );
                }

                // Sleep between checks
                sleep(Duration::from_millis(100));
            }

            // Clean up GDI resources
            DeleteObject(hbm_screen_cap.into());
            DeleteDC(hdc_mem_dc);
            ReleaseDC(Some(hwnd), hdc_target);
        }
    }
}
