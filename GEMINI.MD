# MultiboxSoftware

This project is a multiboxing tool for World of Warcraft. It consists of a Rust application that interacts with a WoW addon.

## How it Works

The addon and the Rust application communicate through a clever mechanism: the addon sets the color of a single pixel on the screen, and the Rust application reads the color of that pixel.

1.  **The Addon**: The WoW addon (`addon/`) creates a 1x1 pixel frame in the top-left corner of the screen. Based on the player's class, specialization, and the current state of the game, the addon determines which macro to run and on which target. It then encodes this information into the color of the 1x1 pixel frame. The macro is encoded in the red component of the color, and the target is encoded in the green component.

2.  **The Rust Application**: The Rust application (`src/main.rs`) continuously scans for all open "World of Warcraft" windows. For each window, it reads the color of the pixel at the top-left corner. It then decodes the red and green components of the color to determine which key to press and on which target. Finally, it sends the corresponding key presses to the WoW window.

## Project Structure

*   `addon/`: Contains the World of Warcraft addon.
    *   `Multibox.toc`: The addon's table of contents.
    *   `Multibox.lua`: The main addon file.
    *   `*.lua`: Files containing the logic for different classes and specializations.
*   `src/`: Contains the Rust application.
    *   `main.rs`: The main entry point of the application.
*   `Cargo.toml`: The manifest for the Rust project.

## Technologies

*   [Rust](https://www.rust-lang.org/)
*   [Lua](https://www.lua.org/) (for the WoW addon)
*   [iced](https://github.com/iced-rs/iced): A cross-platform GUI library for Rust.
*   [windows-rs](https://github.com/microsoft/windows-rs): Rust bindings for the Windows API.

## How to Build and Run

### Addon

1.  Copy the `addon/` directory to your `World of Warcraft/_classic_/Interface/AddOns/` directory.
2.  Rename the copied directory to `Multibox`.

### Application

1.  Install Rust: https://www.rust-lang.org/tools/install
2.  Build the application:
    ```
    cargo build --release
    ```
3.  Run the application:
    ```
    cargo run --release
    ```
