use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex},
    thread::sleep,
    time::{Duration, Instant},
};

use serde::{Deserialize, Serialize};

use windows::{
    core::*,
    Win32::{
        Foundation::{HWND, LPARAM, RECT, WPARAM},
        Graphics::Gdi::{
            BitBlt, CreateCompatibleBitmap, CreateCompatibleDC, DeleteDC, DeleteObject, GetDC,
            GetPixel, ReleaseDC, SelectObject, SRCCOPY,
        },
        UI::{
            Input::KeyboardAndMouse::{
                VIRTUAL_KEY, VK_F1, VK_F10, VK_F11, VK_F12, VK_F2, VK_F3, VK_F4, VK_F5, VK_F6,
                VK_F7, VK_F8, VK_F9, VK_LCONTROL, VK_LMENU, VK_LSHIFT, VK_NUMPAD0,
            },
            WindowsAndMessaging::{
                EnumWindows, GetWindowRect, GetWindowTextLengthW, GetWindowTextW, IsWindow,
                PostMessageW, SetWindowPos, SetWindowTextW, HWND_TOP, SWP_NOZORDER, WM_KEYDOWN,
                WM_KEYUP,
            },
        },
    },
};

// Configuration structs for window positions and sizes
#[derive(Debug, Clone, Serialize, Deserialize)]
struct WindowConfig {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ConfigFile {
    positions: Vec<WindowConfig>,
}

// Define a wrapper type for HWND to make it hashable
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct HwndWrapper(HWND);

impl std::hash::Hash for HwndWrapper {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.0 .0.hash(state);
    }
}

// Manually implement Send for HwndWrapper
unsafe impl Send for HwndWrapper {}

const PIXEL_X: i32 = 0;
const PIXEL_Y: i32 = 0;

// Global configuration storage
static mut CONFIG: Option<Vec<ConfigFile>> = None;

// Load configuration from JSON file
fn load_config() {
    match std::fs::read_to_string("window_config.json") {
        Ok(contents) => match serde_json::from_str::<Vec<ConfigFile>>(&contents) {
            Ok(config) => unsafe {
                CONFIG = Some(config);
            },
            Err(e) => println!("Failed to parse JSON: {}", e),
        },
        Err(e) => println!("Failed to read config file: {}", e),
    }
}

// Get window configuration by index
fn get_window_config(index: usize) -> Option<&'static WindowConfig> {
    unsafe {
        if let Some(ref config) = CONFIG {
            if index < config.len() {
                return config[index].positions.first();
            }
        }
    }
    None
}

// Find the lowest available OMB number
fn find_lowest_omb_number() -> Option<usize> {
    let mut used_numbers = HashSet::new();

    unsafe {
        if let Some(ref config) = CONFIG {
            for config_file in config.iter() {
                for (i, _) in config_file.positions.iter().enumerate() {
                    used_numbers.insert(i);
                }
            }
        }
    }

    // Find the smallest number not in use
    for i in 0.. {
        if !used_numbers.contains(&i) {
            return Some(i);
        }
    }
    None
}

// Set window position and size
fn set_window_position(hwnd: HWND, config: &WindowConfig) {
    unsafe {
        let _ = SetWindowPos(
            hwnd,
            Some(HWND_TOP),
            config.x,
            config.y,
            config.width,
            config.height,
            SWP_NOZORDER,
        );
    }
}

// Rename window to OMB format
fn rename_window(hwnd: HWND, new_title: &str) {
    unsafe {
        let mut title_wide: Vec<u16> = new_title.encode_utf16().collect();
        title_wide.push(0);
        let _ = SetWindowTextW(hwnd, windows::core::PCWSTR::from_raw(title_wide.as_ptr()));
        println!("Renamed window to: {}", new_title);
    }
}

// Static mutable vector to collect HWNDs during window enumeration
static mut HWNDS: Vec<HWND> = vec![];

// Helper function to get all windows with a specific title
fn find_all_windows_with_title() -> Vec<HWND> {
    unsafe {
        // Clear the static vector before enumerating
        HWNDS.clear();

        let _ = EnumWindows(Some(enum_window_callback), LPARAM(0));

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

        // Handle "OMB" prefix windows
        if title_str.starts_with("OMB ") {
            HWNDS.push(hwnd);

            // Extract the number from "OMB X" format
            if let Some(num_str) = title_str[4..].split_whitespace().next() {
                if let Ok(index) = num_str.parse::<usize>() {
                    if let Some(config) = get_window_config(index - 1) {
                        set_window_position(hwnd, config);
                    }
                }
            }
        }
        // Handle "World of Warcraft" windows - rename to lowest available OMB number
        else if title_str.starts_with("World of Warcraft") {
            if let Some(lowest_num) = find_lowest_omb_number() {
                let new_title = format!("OMB {}", lowest_num + 1);
                rename_window(hwnd, &new_title);

                // Apply position configuration for the new OMB number
                if let Some(config) = get_window_config(lowest_num) {
                    set_window_position(hwnd, config);
                }

                HWNDS.push(hwnd);
            }
        }
    }

    windows::core::BOOL::from(true)
}



fn main() {
    // iced::run("A cool counter", Counter::update, Counter::view);

    // Load configuration from JSON file
    load_config();

    // Initialize scancode mapping
    let mut scancode_map: HashMap<u8, VIRTUAL_KEY> = HashMap::new();
    scancode_map.insert(0x01, VK_F1);
    scancode_map.insert(0x02, VK_F2);
    scancode_map.insert(0x03, VK_F3);
    scancode_map.insert(0x04, VK_F4);
    scancode_map.insert(0x05, VK_F5);
    scancode_map.insert(0x06, VK_F6);
    scancode_map.insert(0x07, VK_F7);
    scancode_map.insert(0x08, VK_F8);
    scancode_map.insert(0x09, VK_F9);
    scancode_map.insert(0x0A, VK_F10);
    scancode_map.insert(0x0B, VK_F11);
    scancode_map.insert(0x0C, VK_F12);

    let scancode_map_arc = Arc::new(Mutex::new(scancode_map));
    let window_map: Arc<Mutex<HashMap<usize, HwndWrapper>>> =
        Arc::new(Mutex::new(HashMap::new()));

    // Track currently active HWNDs using our wrapper type
    let hwnd_set: Arc<Mutex<HashSet<HwndWrapper>>> = Arc::new(Mutex::new(HashSet::new()));

    // Start the watcher thread
    std::thread::spawn(move || {
        loop {
            sleep(Duration::from_millis(1000));

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
                    let window_map_clone = Arc::clone(&window_map);
                    std::thread::spawn(move || {
                        process_window(wrapped, &scancode_arc_clone, &window_map_clone)
                    });
                }
            }
        }
    });

    // Keep main thread alive (to prevent early exit)
    loop {
        sleep(Duration::from_secs(1));
    }
}

// Process a single HWND
fn process_window(
    wrapped: HwndWrapper,
    scancode_map_arc: &Arc<Mutex<HashMap<u8, VIRTUAL_KEY>>>,
    window_map: &Arc<Mutex<HashMap<usize, HwndWrapper>>>,
) {
    let hwnd = wrapped.0;
    let mut keys_enabled = true;
    let mut last_swap_time = Instant::now();

    let (title_string, own_omb_num) = unsafe {
        let len = GetWindowTextLengthW(hwnd);
        let mut title_buf = vec![0u16; (len + 1) as usize];
        GetWindowTextW(hwnd, &mut title_buf);
        let title = String::from_utf16_lossy(&title_buf)
            .trim_end_matches('\0')
            .to_string();
        let number = title
            .strip_prefix("OMB ")
            .and_then(|s| s.split_whitespace().next())
            .and_then(|s| s.parse().ok());
        (title, number)
    };

    if let Some(num) = own_omb_num {
        window_map.lock().unwrap().insert(num, wrapped);
    }

    unsafe {
        loop {
            // Check if the window still exists
            if !IsWindow(Some(hwnd)).as_bool() {
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
                let _ = DeleteDC(hdc_mem_dc);
                ReleaseDC(Some(hwnd), hdc_target);
                break;
            }

            // Select the bitmap into memory DC
            let old_bitmap = SelectObject(hdc_mem_dc, hbm_screen_cap.into());

            // Copy pixel to memory DC
            if BitBlt(
                hdc_mem_dc,
                0,
                0,
                1,
                1,
                Some(hdc_target),
                PIXEL_X,
                PIXEL_Y,
                SRCCOPY,
            )
            .is_err()
            {
                SelectObject(hdc_mem_dc, old_bitmap);
                let _ = DeleteObject(hbm_screen_cap.into());
                let _ = DeleteDC(hdc_mem_dc);
                ReleaseDC(Some(hwnd), hdc_target);
                continue; // Continue to next iteration
            }

            // Get the pixel color (in BGR format)
            let actual_color = GetPixel(hdc_mem_dc, 0, 0);

            // Extract color components
            let blue = ((actual_color.0 >> 16) & 0xFF) as u8;
            let green = ((actual_color.0 >> 8) & 0xFF) as u8;
            let red = (actual_color.0 & 0xFF) as u8;

            if blue == 1 && keys_enabled {
                keys_enabled = false;
                println!("[{}] Keys disabled", title_string);
            } else if blue == 2 && !keys_enabled {
                keys_enabled = true;
                println!("[{}] Keys enabled", title_string);
            } else if blue > 2 {
                if last_swap_time.elapsed() > Duration::from_secs(1) {
                    let target_omb_num = (blue - 2) as usize;
                    println!(
                        "[{}] Received swap command with window {}",
                        title_string, target_omb_num
                    );
                    if let Some(own_num) = own_omb_num {
                        if own_num != target_omb_num {
                            let map = window_map.lock().unwrap();
                            if let Some(&target_hwnd_wrapper) = map.get(&target_omb_num) {
                                let target_hwnd = target_hwnd_wrapper.0;
                                let own_hwnd = wrapped.0;

                                let mut own_rect = RECT::default();
                                let mut target_rect = RECT::default();

                                if GetWindowRect(own_hwnd, &mut own_rect).is_ok()
                                    && GetWindowRect(target_hwnd, &mut target_rect).is_ok()
                                {
                                    let own_width = own_rect.right - own_rect.left;
                                    let own_height = own_rect.bottom - own_rect.top;
                                    let target_width = target_rect.right - target_rect.left;
                                    let target_height = target_rect.bottom - target_rect.top;

                                    let _ = SetWindowPos(
                                        own_hwnd,
                                        None,
                                        target_rect.left,
                                        target_rect.top,
                                        target_width,
                                        target_height,
                                        SWP_NOZORDER,
                                    );
                                    let _ = SetWindowPos(
                                        target_hwnd,
                                        None,
                                        own_rect.left,
                                        own_rect.top,
                                        own_width,
                                        own_height,
                                        SWP_NOZORDER,
                                    );
                                }
                            }
                        }
                    }
                    last_swap_time = Instant::now();
                }
            }

            if keys_enabled {
                let scancode_map = scancode_map_arc.lock().unwrap();
                if let Some(&scancode) = scancode_map.get(&red) {
                    send_target_combination(hwnd, green);
                    let _ = PostMessageW(
                        Some(hwnd),
                        WM_KEYDOWN as u32,
                        WPARAM(scancode.0.into()),
                        LPARAM(0),
                    );
                    sleep(Duration::from_millis(10));
                    let _ = PostMessageW(
                        Some(hwnd),
                        WM_KEYUP as u32,
                        WPARAM(scancode.0.into()),
                        LPARAM(0),
                    );
                    sleep(Duration::from_millis(100));
                }
            }

            // Clean up GDI resources
            SelectObject(hdc_mem_dc, old_bitmap);
            let _ = DeleteObject(hbm_screen_cap.into());
            let _ = DeleteDC(hdc_mem_dc);
            ReleaseDC(Some(hwnd), hdc_target);

            // Sleep between checks
            sleep(Duration::from_millis(15));
        }
    }

    if let Some(num) = own_omb_num {
        window_map.lock().unwrap().remove(&num);
        println!("[{}] Unregistered window.", title_string);
    }
}

fn send_target_combination(hwnd: HWND, input: u8) {
    // 0 = untargeted
    if input == 0 {
        return;
    }
    // Calculate target index and modifier based on Lua logic
    let mod_index = (input - 1) % 4;
    let numpad_index = (input - 1) / 4;
    // println!("Targeting {:x} {:x} {:x}", input, mod_index, numpad_index);

    // Determine the modifier virtual key
    let modifier_vk: Option<VIRTUAL_KEY> = match mod_index {
        1 => Some(VK_LCONTROL),
        2 => Some(VK_LSHIFT),
        3 => Some(VK_LMENU),
        _ => None,
    };

    // Calculate numpad key (0-9)
    let numpad_key: usize = <u16 as Into<usize>>::into(VK_NUMPAD0.0) + (numpad_index as usize);
    unsafe {
        // Send keydown for modifier (if present)
        if let Some(modifier) = modifier_vk {
            let _ = PostMessageW(
                Some(hwnd),
                WM_KEYDOWN as u32,
                WPARAM(modifier.0.into()),
                LPARAM(0),
            );
        }

        // Send keydown for numpad
        let _ = PostMessageW(Some(hwnd), WM_KEYDOWN as u32, WPARAM(numpad_key), LPARAM(0));

        // Wait a bit to ensure the key is registered
        std::thread::sleep(std::time::Duration::from_millis(10));

        // Send keyup for numpad
        let _ = PostMessageW(Some(hwnd), WM_KEYUP as u32, WPARAM(numpad_key), LPARAM(0));

        // Send keyup for modifier (if present)
        if let Some(modifier) = modifier_vk {
            let _ = PostMessageW(
                Some(hwnd),
                WM_KEYUP as u32,
                WPARAM(modifier.0.into()),
                LPARAM(0),
            );
        }

        // Optional: add delay after all actions
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
}
