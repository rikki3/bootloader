# bootloader-doom

This is a small BIOS bootloader project for x86 that boots a freestanding Doom port.

The boot process is split into parts:

- `boot.asm` is stage 1, the very first boot sector
- `boot/stage2.asm` is stage 2, which does more setup and loads the kernel
- `kernel/main.c` is the freestanding kernel code that runs after the bootloader

## Build and write to USB

Before building, place your local Doom II IWAD at `assets/DOOM2.WAD`.
That file is intentionally ignored and is not included in the repository.

Run:

```powershell
.\build.ps1 image
```

This creates `build/disk.img`, which is the full bootable image.

Write `build/disk.img` to the USB with Rufus. If Rufus asks, choose raw or DD image mode.

By default, `build.ps1` looks for MSYS2 in `%LOCALAPPDATA%\msys64`.
If your MSYS2 installation is somewhere else, set the `MSYS2_ROOT` environment variable before running the script.

Example:

```powershell
$env:MSYS2_ROOT = "C:\msys64"
.\build.ps1 image
```
