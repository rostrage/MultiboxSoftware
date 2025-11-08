use std::{
    collections::{HashMap, HashSet},
    fs::File,
    io::Read,
    sync::{Arc, Mutex},
    thread::sleep,
    time::Duration,
};

use serde::{Deserialize, Serialize};

use iced::widget::{button, column, text, Column};
use windows::{
    core::*,
    Win32::{
        Foundation::{HWND, LPARAM, WPARAM},
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
                EnumWindows, GetWindowTextLengthW, GetWindowTextW, IsWindow, PostMessageW,
                SetWindowPos, SetWindowTextW, HWND_TOP, SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER,
                WM_KEYDOWN, WM_KEYUP,
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

const PixelX: i32 = 0;
const PixelY: i32 = 0;

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
        SetWindowPos(
            hwnd,
            Some(HWND_TOP),
            config.x,
            config.y,
            config.width,
            config.height,
            SWP_NOZORDER | SWP_NOMOVE,
        );
    }
}

// Rename window to OMB format
fn rename_window(hwnd: HWND, new_title: &str) {
    unsafe {
        let mut title_wide: Vec<u16> = new_title.encode_utf16().collect();
        title_wide.push(0);
        SetWindowTextW(hwnd, windows::core::PCWSTR::from_raw(title_wide.as_ptr()));
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

#[derive(Default)]
struct Counter {
    value: i32,
}
#[derive(Debug, Clone, Copy)]
pub enum Message {
    Increment,
    Decrement,
}
impl Counter {
    pub fn view(&self) -> Column<Message> {
        // We use a column: a simple vertical layout
        column![
            // The increment button. We tell it to produce an
            // `Increment` message when pressed
            button("+").on_press(Message::Increment),
            // We show the value of the counter here
            text(self.value).size(50),
            // The decrement button. We tell it to produce a
            // `Decrement` message when pressed
            button("-").on_press(Message::Decrement),
        ]
    }
    pub fn update(&mut self, message: Message) {
        match message {
            Message::Increment => {
                self.value += 1;
            }
            Message::Decrement => {
                self.value -= 1;
            }
        }
    }
}

fn main() {
    // iced::run("A cool counter", Counter::update, Counter::view);

    // Load configuration from JSON file
    load_config();

    unsafe {
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
        let len = GetWindowTextLengthW(hwnd);
        let mut title_buf = vec![0u16; (len + 1) as usize];
        GetWindowTextW(hwnd, &mut title_buf);
        let title_string = String::from_utf16_lossy(&title_buf);
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
                )
                .is_err()
                {
                    break;
                }

                // Get the pixel color (in BGR format)
                let actual_color = GetPixel(hdc_mem_dc, 0, 0);

                // Extract red component
                let blue = ((actual_color.0 >> 16) & 0xFF) as u8;
                let green = ((actual_color.0 >> 8) & 0xFF) as u8;
                let red = (actual_color.0 & 0xFF) as u8;
                // println!("color {:x} {:x} {:x} {:x}", actual_color.0, blue, green, red);

                // Press the corresponding key if found in map
                let scancode_map = scancode_map_arc.lock().unwrap();
                if let Some(&scancode) = scancode_map.get(&red) {
                    send_target_combination(hwnd, green);
                    PostMessageW(
                        Some(hwnd),
                        WM_KEYDOWN as u32,
                        WPARAM(scancode.0.into()),
                        LPARAM(0),
                    );
                    println!("Sending key {:x} to window {1}", scancode.0, title_string);
                    sleep(Duration::from_millis(10));
                    PostMessageW(
                        Some(hwnd),
                        WM_KEYUP as u32,
                        WPARAM(scancode.0.into()),
                        LPARAM(0),
                    );
                    sleep(Duration::from_millis(100));
                }

                // Sleep between checks
                sleep(Duration::from_millis(15));
            }

            // Clean up GDI resources
            DeleteObject(hbm_screen_cap.into());
            DeleteDC(hdc_mem_dc);
            ReleaseDC(Some(hwnd), hdc_target);
        }
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
            PostMessageW(
                Some(hwnd),
                WM_KEYDOWN as u32,
                WPARAM(modifier.0.into()),
                LPARAM(0),
            );
        }

        // Send keydown for numpad
        PostMessageW(Some(hwnd), WM_KEYDOWN as u32, WPARAM(numpad_key), LPARAM(0));

        // Wait a bit to ensure the key is registered
        std::thread::sleep(std::time::Duration::from_millis(10));

        // Send keyup for numpad
        PostMessageW(Some(hwnd), WM_KEYUP as u32, WPARAM(numpad_key), LPARAM(0));

        // Send keyup for modifier (if present)
        if let Some(modifier) = modifier_vk {
            PostMessageW(
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
