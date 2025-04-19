use std::{
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
            Input::KeyboardAndMouse::VK_W,
            WindowsAndMessaging::{
                FindWindowW, MessageBoxW, PostMessageW, MB_OK, WM_KEYDOWN, WM_KEYUP
            },            
        },
    },
};

const PixelX: i32 = 100;
const PixelY: i32 = 200;
const TARGET_COLOR: u32 = 0x000000FF;

fn main() {
    unsafe {
        let hwnd = loop {
            if let Ok(hwnd_candidate) = FindWindowW(None, w!("World of Warcraft")) {
                if !hwnd_candidate.is_invalid() {
                    break hwnd_candidate;
                }
            }
            sleep(Duration::from_millis(100));
        };

        // Get target DC
        let hdc_target = GetDC(Some(hwnd));
        if hdc_target.is_invalid() {
            MessageBoxW(
                None,
                w!("Failed to get device context."),
                w!("Error"),
                MB_OK,
            );
            return;
        }

        // Create compatible DC and bitmap
        let hdc_mem_dc = CreateCompatibleDC(Some(hdc_target));
        if hdc_mem_dc.is_invalid() {
            MessageBoxW(
                None,
                w!("Failed to create memory device context."),
                w!("Error"),
                MB_OK,
            );
            ReleaseDC(Some(hwnd), hdc_target);
            return;
        }

        // Create 1x1 bitmap
        let hbm_screen_cap = CreateCompatibleBitmap(hdc_target, 1, 1);
        if hbm_screen_cap.is_invalid() {
            MessageBoxW(
                None,
                w!("Failed to create compatible bitmap."),
                w!("Error"),
                MB_OK,
            );
            DeleteDC(hdc_mem_dc);
            ReleaseDC(Some(hwnd), hdc_target);
            return;
        }

        // Select bitmap into memory DC
        SelectObject(hdc_mem_dc, hbm_screen_cap.into());
        loop {
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
            ).is_err()
            {
                MessageBoxW(
                    None,
                    w!("Failed to copy pixels."),
                    w!("Error"),
                    MB_OK,
                );
                DeleteObject(hbm_screen_cap.into());
                DeleteDC(hdc_mem_dc);
                ReleaseDC(Some(hwnd), hdc_target);
                return;
            }
    
            // Get pixel color
            let actual_color = GetPixel(hdc_mem_dc, 0, 0);
            println!("Actual color: {:x}", actual_color.0);
            sleep(Duration::from_millis(100));
        }

        // if actual_color == actual_color {
        //     PostMessageW(
        //         Some(hwnd),
        //         WM_KEYDOWN as u32,
        //         WPARAM(0x0026),
        //         LPARAM(0),
        //     );
        //     PostMessageW(
        //         Some(hwnd),
        //         WM_KEYUP as u32,
        //         WPARAM(0x0026),
        //         LPARAM(0),
        //     );
        // }
        // Cleanup resources
        DeleteObject(hbm_screen_cap.into());
        DeleteDC(hdc_mem_dc);
        ReleaseDC(Some(hwnd), hdc_target);
    }
}
