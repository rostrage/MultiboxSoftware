use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, LazyLock, Mutex},
    thread::sleep,
    time::{Duration, Instant},
};

use serde::{Deserialize, Serialize};

use windows::{
    Win32::{
        Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, RECT, WPARAM},
        Graphics::Gdi::{
            CreateCompatibleBitmap, CreateCompatibleDC, DeleteDC, DeleteObject, GetDC, GetPixel,
            HBITMAP, HDC, HGDIOBJ, ReleaseDC, SelectObject,
        },
        Storage::Xps::{PW_CLIENTONLY, PrintWindow},
        System::LibraryLoader::GetModuleHandleW,
        UI::{
            Input::KeyboardAndMouse::{
                VIRTUAL_KEY, VK_F1, VK_F2, VK_F3, VK_F4, VK_F5, VK_F6, VK_F7, VK_F8, VK_F9, VK_F10, VK_F11, VK_F12, VK_F13, VK_F14, VK_F15, VK_F16, VK_F17, VK_F18, VK_F19, VK_F20, VK_F21, VK_F22, VK_F23, VK_F24, VK_LCONTROL, VK_LMENU, VK_LSHIFT, VK_NUMPAD0
            },
            WindowsAndMessaging::{
                CallNextHookEx, DispatchMessageW, EnumWindows, GetClientRect, GetForegroundWindow, GetMessageW, GetWindowRect, GetWindowTextLengthW, GetWindowTextW, HWND_TOP, IsWindow, KBDLLHOOKSTRUCT, LLKHF_INJECTED, MSG, PostMessageW, SWP_NOZORDER, SetWindowPos, SetWindowTextW, SetWindowsHookExW, TranslateMessage, UnhookWindowsHookEx, WH_KEYBOARD_LL, WM_KEYDOWN, WM_KEYUP
            },
        },
    }, core::*
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
const SENTINEL_X: i32 = 1;
// In-game addon sets sentinel pixels to check if the addon is active.
// Lua (r=0x12, g=0x34, b=0x56) -> BGR 0x563412
const SENTINEL_COLOR: u32 = 0x563412;

// Global configuration storage
static mut CONFIG: Option<Vec<ConfigFile>> = None;

static HWND_SET: LazyLock<Mutex<HashSet<HwndWrapper>>> =
    LazyLock::new(|| Mutex::new(HashSet::new()));

static BROADCAST_ENABLED: LazyLock<Mutex<bool>> = LazyLock::new(|| Mutex::new(false));

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
    let mut to_remove = Vec::new();

    // Scope the lock to avoid deadlock when removing
    {
        let set = HWND_SET.lock().unwrap();
        for hwnd in set.iter() {
            unsafe {
                if !IsWindow(Some(hwnd.0)).as_bool() {
                    to_remove.push(*hwnd);
                    continue;
                }
            }
            let (title_str, number) = get_window_title_and_omb_number(hwnd.0);
            if title_str.starts_with("OMB ") && Some(number).is_some() {
                println!("Found used OMB number: {}", title_str);
                used_numbers.insert(number.unwrap());
            }
        }
    } // Lock released here

    // Remove dead windows safely
    if !to_remove.is_empty() {
        let mut set = HWND_SET.lock().unwrap();
        for hwnd in to_remove {
            set.remove(&hwnd);
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

unsafe extern "system" fn keyboard_hook_proc(
    n_code: i32,
    w_param: WPARAM,
    l_param: LPARAM,
) -> LRESULT {
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
            return CallNextHookEx(None, n_code, w_param, l_param);
        }

        if *BROADCAST_ENABLED.lock().unwrap() {
            let foreground_hwnd = GetForegroundWindow();
            let wow_windows = HWND_SET.lock().unwrap();

            if wow_windows.contains(&HwndWrapper(foreground_hwnd)) {
                for &window in wow_windows.iter() {
                    if window.0 != foreground_hwnd {
                        println!(
                            "Broadcasting key {}, event {} to window {:?}",
                            vk_code, event_type, window.0
                        );
                        let mut l_param = 1;
                        if event_type == WM_KEYUP {
                            // Key up lParam needs to have the 0xC0000000 flag set
                            l_param = l_param | 0xC0000000;
                        }
                        let _ = PostMessageW(
                            Some(window.0),
                            event_type,
                            WPARAM(vk_code as usize),
                            LPARAM(l_param),
                        );
                    }
                }
            }
        }
    }

    CallNextHookEx(None, n_code, w_param, l_param)
}

fn main() {
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
    scancode_map.insert(0x0D, VK_F13);
    scancode_map.insert(0x0E, VK_F14);
    scancode_map.insert(0x0F, VK_F15);
    scancode_map.insert(0x10, VK_F16);
    scancode_map.insert(0x11, VK_F17);
    scancode_map.insert(0x12, VK_F18);
    scancode_map.insert(0x13, VK_F18);
    scancode_map.insert(0x14, VK_F19);
    scancode_map.insert(0x15, VK_F20);
    scancode_map.insert(0x16, VK_F21);
    scancode_map.insert(0x17, VK_F22);
    scancode_map.insert(0x18, VK_F23);
    scancode_map.insert(0x19, VK_F24);


    let scancode_map_arc = Arc::new(Mutex::new(scancode_map));
    let window_map: Arc<Mutex<HashMap<usize, HwndWrapper>>> = Arc::new(Mutex::new(HashMap::new()));

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
                        process_window(wrapped, scancode_arc_clone, window_map_clone)
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

// Struct to manage GDI resources safely and efficiently
struct WindowCapturer {
    hwnd: HWND,
    hdc_window: HDC,
    hdc_mem: HDC,
    hbm: HBITMAP,
    old_hbm: HGDIOBJ,
}

impl WindowCapturer {
    // Initialize GDI objects ONCE per window
    fn new(hwnd: HWND) -> Option<Self> {
        unsafe {
            let hdc_window = GetDC(Some(hwnd));
            if hdc_window.is_invalid() {
                return None;
            }

            let hdc_mem = CreateCompatibleDC(Some(hdc_window));
            if hdc_mem.is_invalid() {
                ReleaseDC(Some(hwnd), hdc_window);
                return None;
            }

            // Optimization: Create a tiny bitmap (2x1) just enough for our pixels.
            // This prevents allocating ~4MB per frame, fixing the memory leak.
            let hbm = CreateCompatibleBitmap(hdc_window, 2, 1);
            if hbm.is_invalid() {
                DeleteDC(hdc_mem);
                ReleaseDC(Some(hwnd), hdc_window);
                return None;
            }

            let old_hbm = SelectObject(hdc_mem, hbm.into());

            Some(Self {
                hwnd,
                hdc_window,
                hdc_mem,
                hbm,
                old_hbm,
            })
        }
    }

    // Reuse the existing GDI objects to capture pixels
    fn capture(&self) -> Option<(u32, u32)> {
        unsafe {
            // Use PrintWindow with PW_CLIENTONLY. This works for minimized/occluded windows.
            // It renders into our tiny 2x1 bitmap (clipped automatically).
            if PrintWindow(self.hwnd, self.hdc_mem, PW_CLIENTONLY).as_bool() {
                let sentinel = GetPixel(self.hdc_mem, SENTINEL_X, PIXEL_Y).0;
                let command = GetPixel(self.hdc_mem, PIXEL_X, PIXEL_Y).0;
                Some((sentinel, command))
            } else {
                None
            }
        }
    }
}

// Clean up GDI objects automatically when the struct goes out of scope
impl Drop for WindowCapturer {
    fn drop(&mut self) {
        unsafe {
            SelectObject(self.hdc_mem, self.old_hbm);
            DeleteObject(self.hbm.into());
            DeleteDC(self.hdc_mem);
            ReleaseDC(Some(self.hwnd), self.hdc_window);
        }
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
        // sleep(Duration::from_millis(10));
        let _ = PostMessageW(Some(hwnd), WM_KEYUP as u32, WPARAM(vk.0.into()), LPARAM(0));
    }
}

fn handle_key_press(
    hwnd: HWND,
    red: u8,
    green: u8,
    scancode_map_arc: &Arc<Mutex<HashMap<u8, VIRTUAL_KEY>>>,
) -> bool {
    let scancode_map = scancode_map_arc.lock().unwrap();
    if let Some(&scancode) = scancode_map.get(&red) {
        send_target_combination(hwnd, green);
        send_keypress(hwnd, scancode);
        sleep(Duration::from_millis(100));
        return true
    }
    false
}

// Process a single HWND
fn process_window(
    wrapped: HwndWrapper,
    scancode_map_arc: Arc<Mutex<HashMap<u8, VIRTUAL_KEY>>>,
    window_map: Arc<Mutex<HashMap<usize, HwndWrapper>>>,
) {
    let hwnd = wrapped.0;
    let mut keys_enabled = true;
    let mut last_swap_time = Instant::now();

    let (title_string, own_omb_num) = get_window_title_and_omb_number(hwnd);

    if let Some(num) = own_omb_num {
        window_map.lock().unwrap().insert(num, wrapped);
    }

    // Initialize the GDI capturer once.
    // This moves the heavy allocation out of the loop.
    let mut capturer = WindowCapturer::new(hwnd);

    if capturer.is_none() {
        println!("[{}] Failed to initialize GDI capturer.", title_string);
    } else {
        let capturer = capturer.as_ref().unwrap();
        let mut loops_since_last_keypress = 0;
        loop {
            unsafe {
                if !IsWindow(Some(hwnd)).as_bool() {
                    break;
                }
            }
    
            // Reuse the existing GDI context
            if let Some((sentinel, actual_color)) = capturer.capture() {
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
                            &window_map,
                        );
                    }
    
                    if keys_enabled && loops_since_last_keypress >= 5 {
                        let has_pressed_key = handle_key_press(hwnd, red, green, &scancode_map_arc);
                        if has_pressed_key {
                            // Reset loop counter on keypress
                            loops_since_last_keypress = 0;
                        }
                    }
                }
            }
            loops_since_last_keypress += 1;
            // Sleep between checks
            sleep(Duration::from_millis(15));
        }
    }
    // GDI resources in 'capturer' are automatically cleaned up here via Drop

    if let Some(num) = own_omb_num {
        window_map.lock().unwrap().remove(&num);
        println!("[{}] Unregistered window.", title_string);
    }
}

fn send_target_combination(hwnd: HWND, input: u8) {
    if input == 0 {
        return;
    }
    let mod_index = (input - 1) % 4;
    let numpad_index = (input - 1) / 4;

    let modifier_vk: Option<VIRTUAL_KEY> = match mod_index {
        1 => Some(VK_LCONTROL),
        2 => Some(VK_LSHIFT),
        3 => Some(VK_LMENU),
        _ => None,
    };
  
    let numpad_key: usize = <u16 as Into<usize>>::into(VK_NUMPAD0.0) + (numpad_index as usize);
    unsafe {
        if let Some(modifier) = modifier_vk {
            let _ = PostMessageW(
                Some(hwnd),
                WM_KEYDOWN as u32,
                WPARAM(modifier.0.into()),
                LPARAM(0),
            );
        }

        let _ = PostMessageW(Some(hwnd), WM_KEYDOWN as u32, WPARAM(numpad_key), LPARAM(0));
        // std::thread::sleep(std::time::Duration::from_millis(10));
        let _ = PostMessageW(Some(hwnd), WM_KEYUP as u32, WPARAM(numpad_key), LPARAM(0));

        if let Some(modifier) = modifier_vk {
            let _ = PostMessageW(
                Some(hwnd),
                WM_KEYUP as u32,
                WPARAM(modifier.0.into()),
                LPARAM(0),
            );
        }
        // std::thread::sleep(std::time::Duration::from_millis(10));
    }
}