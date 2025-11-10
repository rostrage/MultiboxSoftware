use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, LazyLock, Mutex},
    thread::sleep,
    time::{Duration, Instant},
};

use serde::{Deserialize, Serialize};

use windows::{    core::*,    Win32::{        Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, RECT, WPARAM},        Graphics::Gdi::{            CreateCompatibleBitmap, CreateCompatibleDC, DeleteDC, DeleteObject, GetDC, GetPixel,            ReleaseDC, SelectObject,        },        Storage::Xps::{PrintWindow, PW_CLIENTONLY},        System::LibraryLoader::GetModuleHandleW,        UI::{            Input::KeyboardAndMouse::{                VIRTUAL_KEY, VK_F1, VK_F10, VK_F11, VK_F12, VK_F2, VK_F3, VK_F4, VK_F5, VK_F6,                VK_F7, VK_F8, VK_F9, VK_LCONTROL, VK_LMENU, VK_LSHIFT, VK_NUMPAD0,            },            WindowsAndMessaging::{                CallNextHookEx, DispatchMessageW, EnumWindows, GetClientRect, GetForegroundWindow,                GetMessageW, GetWindowRect, GetWindowTextLengthW, GetWindowTextW, IsWindow,                KBDLLHOOKSTRUCT, LLKHF_INJECTED, PostMessageW, SetWindowPos, SetWindowTextW,                SetWindowsHookExW, TranslateMessage, UnhookWindowsHookEx, HWND_TOP, MSG,                SWP_NOZORDER, WH_KEYBOARD_LL, WM_KEYDOWN, WM_KEYUP,            },        },    },};

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
const SENTINEL_X: i32 = 1;
// In-game addon sets sentinel pixels to check if the addon is active.
// Lua (r=0x12, g=0x34, b=0x56) -> BGR 0x563412
const SENTINEL_COLOR: u32 = 0x563412;

// Global configuration storage
static mut CONFIG: Option<Vec<ConfigFile>> = None;

static HWND_SET: LazyLock<Mutex<HashSet<HwndWrapper>>> =
    LazyLock::new(|| Mutex::new(HashSet::new()));

static BROADCAST_ENABLED: LazyLock<Mutex<bool>> = LazyLock::new(|| Mutex::new(false));

static PRESSED_KEYS: LazyLock<Mutex<HashSet<u32>>> =
    LazyLock::new(|| Mutex::new(HashSet::new()));

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

    for hwnd in HWND_SET.lock().unwrap().iter() {
        unsafe {
            if !IsWindow(Some(hwnd.0)).as_bool() {
                HWND_SET.lock().unwrap().remove(hwnd);
                continue;
            }
        }
        let (title_str, number) = get_window_title_and_omb_number(hwnd.0);
        if title_str.starts_with("OMB ") && Some(number).is_some() {
            println!("Found used OMB number: {}", title_str);
            used_numbers.insert(number.unwrap());
        }
    }

    // Find the smallest number not in use
    for i in 1.. {
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
            1280, //currently hardcoded to always match in game resolution of 1280x720
            720,
            // config.width,
            // config.height,
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
            if HWND_SET.lock().unwrap().contains(&HwndWrapper(hwnd)) {
                return windows::core::BOOL::from(true);
            }
            let num_str_opt = title_str
                .strip_prefix("OMB ")
                .and_then(|s| s.strip_suffix("\0"));
            // Extract the number from "OMB X" format
            if let Some(num_str) = num_str_opt {
                if let Ok(index) = num_str.parse::<usize>() {
                    if let Some(config) = get_window_config(index - 1) {
                        set_window_position(hwnd, config);
                    }
                } else {
                    let err = num_str.parse::<usize>();
                    println!("Failed to parse OMB number from title: {:?}", err);
                }
            }
        }
        // Handle "World of Warcraft" windows - rename to lowest available OMB number
        else if title_str == "World of Warcraft\0" {
            if let Some(lowest_num) = find_lowest_omb_number() {
                let new_title = format!("OMB {}", lowest_num);
                rename_window(hwnd, &new_title);

                // Apply position configuration for the new OMB number
                if let Some(config) = get_window_config(lowest_num - 1) {
                    println!("Applying config for {}", new_title);
                    set_window_position(hwnd, config);
                }

                HWNDS.push(hwnd);
            }
        }
    }

    windows::core::BOOL::from(true)
}

unsafe extern "system" fn keyboard_hook_proc(n_code: i32, w_param: WPARAM, l_param: LPARAM) -> LRESULT {
    if n_code >= 0 {
        let kbd_struct = *(l_param.0 as *const KBDLLHOOKSTRUCT);
        let vk_code = kbd_struct.vkCode;
        let event_type = w_param.0 as u32;

        // Do not broadcast injected keypresses
        if (kbd_struct.flags.0 & LLKHF_INJECTED.0) != 0 {
            return CallNextHookEx(None, n_code, w_param, l_param);
        }

        // Only handle keydown and keyup events
        if event_type != WM_KEYDOWN && event_type != WM_KEYUP {
            println!("Ignoring non-key event: {}", event_type);
            return CallNextHookEx(None, n_code, w_param, l_param);
        }

        // Get current key state
        let mut pressed_keys = PRESSED_KEYS.lock().unwrap();
        let is_key_pressed = pressed_keys.contains(&vk_code);

        // Handle key down events
        if event_type == WM_KEYDOWN {
            // If key is already pressed, this is a repeat - ignore it
            if is_key_pressed {
                return CallNextHookEx(None, n_code, w_param, l_param);
            }
            // Add key to pressed set
            pressed_keys.insert(vk_code);
        }
        // Handle key up events
        else if event_type == WM_KEYUP {
            // Remove key from pressed set
            pressed_keys.remove(&vk_code);
            // for some reason sending a keyup event also emits a keydown event, so we ignore it here
            return CallNextHookEx(None, n_code, w_param, l_param);
        }

        if *BROADCAST_ENABLED.lock().unwrap() {
            let foreground_hwnd = GetForegroundWindow();
            let wow_windows = HWND_SET.lock().unwrap();

            if wow_windows.contains(&HwndWrapper(foreground_hwnd)) {
                for &window in wow_windows.iter() {
                    if window.0 != foreground_hwnd {
                        let _ = PostMessageW(
                            Some(window.0),
                            event_type,
                            WPARAM(vk_code as usize),
                            LPARAM(1),
                        );
                    }
                }
            }
        }
    }

    CallNextHookEx(None, n_code, w_param, l_param)
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
    let window_map: Arc<Mutex<HashMap<usize, HwndWrapper>>> = Arc::new(Mutex::new(HashMap::new()));

    // Track currently active HWNDs using our wrapper type

    // Start the watcher thread
    std::thread::spawn(move || {
        loop {
            sleep(Duration::from_millis(1000));

            // Find all current windows with target title
            let hwnds = find_all_windows_with_title();

            for &hwnd in &hwnds {
                let mut set = HWND_SET.lock().unwrap();
                let wrapped = HwndWrapper(hwnd);
                if !set.contains(&wrapped) {
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

    // Keep main thread alive by setting up a message loop for the keyboard hook
    unsafe {
        let hook = match SetWindowsHookExW(
            WH_KEYBOARD_LL,
            Some(keyboard_hook_proc),
            GetModuleHandleW(None).ok().map(|h| HINSTANCE(h.0)),
            0,
        ) {
            Ok(h) => h,
            Err(e) => {
                println!("Failed to set keyboard hook: {}", e);
                return;
            }
        };

        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        let _ = UnhookWindowsHookEx(hook);
    }
}

fn get_window_title_and_omb_number(hwnd: HWND) -> (String, Option<usize>) {
    unsafe {
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
    }
}

fn capture_pixel_colors(hwnd: HWND) -> Option<(u32, u32)> {
    unsafe {
        // Get the window's device context
        let hdc_window = GetDC(Some(hwnd));
        if hdc_window.is_invalid() {
            return None;
        }

        // Create a compatible DC for the memory bitmap
        let hdc_mem_dc = CreateCompatibleDC(Some(hdc_window));
        if hdc_mem_dc.is_invalid() {
            ReleaseDC(Some(hwnd), hdc_window);
            return None;
        }

        // Get client rect to determine size
        let mut client_rect = RECT::default();
        if GetClientRect(hwnd, &mut client_rect).is_err() {
            let _ = DeleteDC(hdc_mem_dc);
            ReleaseDC(Some(hwnd), hdc_window);
            return None;
        }

        let width = client_rect.right - client_rect.left;
        let height = client_rect.bottom - client_rect.top;

        // Create a bitmap compatible with the window DC
        // We only need a small area but let's capture a bit more to be safe
        let capture_width = 10.max(width);
        let capture_height = 10.max(height);

        let hbm_screen_cap = CreateCompatibleBitmap(hdc_window, capture_width, capture_height);
        if hbm_screen_cap.is_invalid() {
            let _ = DeleteDC(hdc_mem_dc);
            ReleaseDC(Some(hwnd), hdc_window);
            return None;
        }

        let old_bitmap = SelectObject(hdc_mem_dc, hbm_screen_cap.into());

        // Use PrintWindow to capture the window contents directly from the window's
        // rendering buffer, bypassing DWM composition and scaling
        // This captures at the game's native resolution
        if !PrintWindow(hwnd, hdc_mem_dc, PW_CLIENTONLY).as_bool() {
            println!("PrintWindow failed");
        }

        // Now read the pixels at the game's native coordinates
        let sentinel = GetPixel(hdc_mem_dc, SENTINEL_X, PIXEL_Y).0;
        let command = GetPixel(hdc_mem_dc, PIXEL_X, PIXEL_Y).0;

        // Cleanup
        SelectObject(hdc_mem_dc, old_bitmap);
        let _ = DeleteObject(hbm_screen_cap.into());
        let _ = DeleteDC(hdc_mem_dc);
        ReleaseDC(Some(hwnd), hdc_window);

        Some((sentinel, command))
    }
}
fn handle_key_toggle_command(blue: u8, keys_enabled: &mut bool, title_string: &str) {
    if blue == 1 && *keys_enabled {
        *keys_enabled = false;
        println!("[{}] Keys disabled", title_string);
    } else if blue == 2 && !*keys_enabled {
        *keys_enabled = true;
        println!("[{}] Keys enabled", title_string);
    }

    let mut broadcast_enabled = BROADCAST_ENABLED.lock().unwrap();
    if blue == 3 && !*broadcast_enabled {
        *broadcast_enabled = true;
        println!("[{}] Broadcast enabled", title_string);
    } else if blue == 4 && *broadcast_enabled {
        *broadcast_enabled = false;
        println!("[{}] Broadcast disabled", title_string);
    }
}

fn swap_window_positions(hwnd1: HWND, hwnd2: HWND) {
    unsafe {
        let mut rect1 = RECT::default();
        let mut rect2 = RECT::default();

        if GetWindowRect(hwnd1, &mut rect1).is_ok() && GetWindowRect(hwnd2, &mut rect2).is_ok() {
            let width1 = rect1.right - rect1.left;
            let height1 = rect1.bottom - rect1.top;
            let width2 = rect2.right - rect2.left;
            let height2 = rect2.bottom - rect2.top;

            let _ = SetWindowPos(
                hwnd1,
                None,
                rect2.left,
                rect2.top,
                width2,
                height2,
                SWP_NOZORDER,
            );
            let _ = SetWindowPos(
                hwnd2,
                None,
                rect1.left,
                rect1.top,
                width1,
                height1,
                SWP_NOZORDER,
            );
        }
    }
}

fn handle_window_swap(
    title_string: &str,
    own_omb_num: Option<usize>,
    wrapped: HwndWrapper,
    blue: u8,
    last_swap_time: &mut Instant,
    window_map: &Arc<Mutex<HashMap<usize, HwndWrapper>>>,
) {
    if last_swap_time.elapsed() <= Duration::from_secs(1) {
        return;
    }

    let target_omb_num = (blue - 4) as usize;
    println!(
        "[{}] Received swap command with window {}",
        title_string, target_omb_num
    );

    if let Some(own_num) = own_omb_num {
        if own_num != target_omb_num {
            let map = window_map.lock().unwrap();
            if let Some(&target_hwnd_wrapper) = map.get(&target_omb_num) {
                swap_window_positions(wrapped.0, target_hwnd_wrapper.0);
            }
        }
    }
    *last_swap_time = Instant::now();
}

fn send_keypress(hwnd: HWND, vk: VIRTUAL_KEY) {
    unsafe {
        let _ = PostMessageW(
            Some(hwnd),
            WM_KEYDOWN as u32,
            WPARAM(vk.0.into()),
            LPARAM(0),
        );
        sleep(Duration::from_millis(10));
        let _ = PostMessageW(Some(hwnd), WM_KEYUP as u32, WPARAM(vk.0.into()), LPARAM(0));
    }
}

fn handle_key_press(
    hwnd: HWND,
    red: u8,
    green: u8,
    scancode_map_arc: &Arc<Mutex<HashMap<u8, VIRTUAL_KEY>>>,
) {
    let scancode_map = scancode_map_arc.lock().unwrap();
    if let Some(&scancode) = scancode_map.get(&red) {
        send_target_combination(hwnd, green);
        send_keypress(hwnd, scancode);
        sleep(Duration::from_millis(100));
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

    let (title_string, own_omb_num) = get_window_title_and_omb_number(hwnd);

    if let Some(num) = own_omb_num {
        window_map.lock().unwrap().insert(num, wrapped);
    }

    loop {
        unsafe {
            if !IsWindow(Some(hwnd)).as_bool() {
                break;
            }
        }

        if let Some((sentinel, actual_color)) = capture_pixel_colors(hwnd) {
            // Check sentinel color to ensure addon is active
            if sentinel == SENTINEL_COLOR {
                let blue = ((actual_color >> 16) & 0xFF) as u8;
                let green = ((actual_color >> 8) & 0xFF) as u8;
                let red = (actual_color & 0xFF) as u8;

                handle_key_toggle_command(blue, &mut keys_enabled, &title_string);

                // 0 = do nothing, 1/2 = keys, 3/4 = broadcast, >4 = swap
                if blue > 4 {
                    handle_window_swap(
                        &title_string,
                        own_omb_num,
                        wrapped,
                        blue,
                        &mut last_swap_time,
                        window_map,
                    );
                }

                if keys_enabled {
                    handle_key_press(hwnd, red, green, scancode_map_arc);
                }
            } else {
                // println!(
                //     "[{}] Sentinel color mismatch. Expected {:06x}, got {:06x}. Exiting thread.",
                //     title_string, SENTINEL_COLOR, sentinel
                // );
            }
        }

        // Sleep between checks
        sleep(Duration::from_millis(15));
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
