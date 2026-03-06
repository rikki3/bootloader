# Bootloader

This project produces two different binary artifacts:

- `boot.bin`: the 512-byte stage 1 boot sector assembled from `boot.asm`
- `build/disk.img`: the full bootable raw disk image that includes stage 1, stage 2, and the kernel

If you want to write the project to a USB stick with Rufus, use `build/disk.img`. `boot.bin` on its own is not enough for the full boot flow.

## Build on Windows

From PowerShell:

```powershell
.\build.ps1 stage1
.\build.ps1 image
```

The default target is `image`, so `.\build.ps1` also builds `build/disk.img`.

`build.ps1` expects MSYS2 tools under `%LOCALAPPDATA%\msys64`. If yours is elsewhere, set `MSYS2_ROOT` first.

## Git

Initialize the repository and create the first commit:

```powershell
git init
git add .
git commit -m "Initial import"
```
