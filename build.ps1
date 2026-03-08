param(
    [ValidateSet("stage1", "image", "clean")]
    [string]$Target = "image"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $RepoRoot "build"
$ObjDir = Join-Path $BuildDir "obj"

$Stage1Source = Join-Path $RepoRoot "boot.asm"
$Stage2Source = Join-Path $RepoRoot "boot\stage2.asm"
$KernelEntrySource = Join-Path $RepoRoot "kernel\entry.asm"
$KernelLinkerScript = Join-Path $RepoRoot "kernel\link.ld"
$BootWad = Join-Path $RepoRoot "assets\DOOM2.WAD"

$KernelSources = @(
    "kernel\main.c",
    "kernel\platform.c",
    "kernel\interrupts.c",
    "kernel\heap.c",
    "kernel\timer.c",
    "kernel\vga.c",
    "kernel\keyboard.c",
    "kernel\doom_wad.c",
    "kernel\doom_d_iwad.c",
    "kernel\doom_platform.c",
    "kernel\libc_core.c",
    "kernel\libc_stdio.c"
)

$DoomSources = @(
    "third_party\doomgeneric\dummy.c",
    "third_party\doomgeneric\am_map.c",
    "third_party\doomgeneric\doomdef.c",
    "third_party\doomgeneric\doomstat.c",
    "third_party\doomgeneric\dstrings.c",
    "third_party\doomgeneric\d_event.c",
    "third_party\doomgeneric\d_items.c",
    "third_party\doomgeneric\d_loop.c",
    "third_party\doomgeneric\d_main.c",
    "third_party\doomgeneric\d_mode.c",
    "third_party\doomgeneric\d_net.c",
    "third_party\doomgeneric\f_finale.c",
    "third_party\doomgeneric\f_wipe.c",
    "third_party\doomgeneric\g_game.c",
    "third_party\doomgeneric\hu_lib.c",
    "third_party\doomgeneric\hu_stuff.c",
    "third_party\doomgeneric\info.c",
    "third_party\doomgeneric\i_cdmus.c",
    "third_party\doomgeneric\i_endoom.c",
    "third_party\doomgeneric\i_input.c",
    "third_party\doomgeneric\i_joystick.c",
    "third_party\doomgeneric\i_scale.c",
    "third_party\doomgeneric\i_sound.c",
    "third_party\doomgeneric\i_system.c",
    "third_party\doomgeneric\i_timer.c",
    "third_party\doomgeneric\i_video.c",
    "third_party\doomgeneric\memio.c",
    "third_party\doomgeneric\m_argv.c",
    "third_party\doomgeneric\m_bbox.c",
    "third_party\doomgeneric\m_cheat.c",
    "third_party\doomgeneric\m_config.c",
    "third_party\doomgeneric\m_controls.c",
    "third_party\doomgeneric\m_fixed.c",
    "third_party\doomgeneric\m_menu.c",
    "third_party\doomgeneric\m_misc.c",
    "third_party\doomgeneric\m_random.c",
    "third_party\doomgeneric\p_ceilng.c",
    "third_party\doomgeneric\p_doors.c",
    "third_party\doomgeneric\p_enemy.c",
    "third_party\doomgeneric\p_floor.c",
    "third_party\doomgeneric\p_inter.c",
    "third_party\doomgeneric\p_lights.c",
    "third_party\doomgeneric\p_map.c",
    "third_party\doomgeneric\p_maputl.c",
    "third_party\doomgeneric\p_mobj.c",
    "third_party\doomgeneric\p_plats.c",
    "third_party\doomgeneric\p_pspr.c",
    "third_party\doomgeneric\p_saveg.c",
    "third_party\doomgeneric\p_setup.c",
    "third_party\doomgeneric\p_sight.c",
    "third_party\doomgeneric\p_spec.c",
    "third_party\doomgeneric\p_switch.c",
    "third_party\doomgeneric\p_telept.c",
    "third_party\doomgeneric\p_tick.c",
    "third_party\doomgeneric\p_user.c",
    "third_party\doomgeneric\r_bsp.c",
    "third_party\doomgeneric\r_data.c",
    "third_party\doomgeneric\r_draw.c",
    "third_party\doomgeneric\r_main.c",
    "third_party\doomgeneric\r_plane.c",
    "third_party\doomgeneric\r_segs.c",
    "third_party\doomgeneric\r_sky.c",
    "third_party\doomgeneric\r_things.c",
    "third_party\doomgeneric\sha1.c",
    "third_party\doomgeneric\sounds.c",
    "third_party\doomgeneric\statdump.c",
    "third_party\doomgeneric\st_lib.c",
    "third_party\doomgeneric\st_stuff.c",
    "third_party\doomgeneric\s_sound.c",
    "third_party\doomgeneric\tables.c",
    "third_party\doomgeneric\v_video.c",
    "third_party\doomgeneric\wi_stuff.c",
    "third_party\doomgeneric\w_checksum.c",
    "third_party\doomgeneric\w_file.c",
    "third_party\doomgeneric\w_main.c",
    "third_party\doomgeneric\w_wad.c",
    "third_party\doomgeneric\z_zone.c",
    "third_party\doomgeneric\doomgeneric.c"
)

$RootBootBin = Join-Path $RepoRoot "boot.bin"
$Stage1Bin = Join-Path $BuildDir "stage1.bin"
$Stage2Bin = Join-Path $BuildDir "stage2.bin"
$KernelEntryObject = Join-Path $ObjDir "kernel_entry.o"
$KernelElf = Join-Path $BuildDir "kernel.elf"
$Image = Join-Path $BuildDir "disk.img"
$MtoolsRc = Join-Path $BuildDir "mtoolsrc"

$ImageSectors = 131072
$PartitionLba = 2048
$PartitionOffset = 1048576
$Stage2ReservedSectors = 128
$WadMetadataLba = 129

$DefaultMsys2Root = Join-Path $env:LOCALAPPDATA "msys64"
$Msys2Root = if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { $DefaultMsys2Root }

function Resolve-Tool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string[]]$CandidatePaths = @()
    )

    foreach ($candidate in $CandidatePaths) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Could not find $Name. Install MSYS2 tools or set MSYS2_ROOT."
}

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tool,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$([System.IO.Path]::GetFileName($Tool)) failed with exit code $LASTEXITCODE."
    }
}

function Ensure-Dir {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Write-BytesToImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [long]$Offset
    )

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $stream.Position = $Offset
        $stream.Write($Bytes, 0, $Bytes.Length)
    }
    finally {
        $stream.Dispose()
    }
}

function Get-Fat32Geometry {
    param([Parameter(Mandatory = $true)][string]$ImagePath)

    $sector = New-Object byte[] 512
    $stream = [System.IO.File]::Open($ImagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $stream.Position = $PartitionOffset
        $read = $stream.Read($sector, 0, $sector.Length)
        if ($read -ne $sector.Length) {
            throw "Could not read the FAT32 boot sector from $ImagePath."
        }
    }
    finally {
        $stream.Dispose()
    }

    $sectorsPerCluster = [int]$sector[13]
    $reservedSectors = [int][BitConverter]::ToUInt16($sector, 14)
    $fatCount = [int]$sector[16]
    $sectorsPerFat = [int][BitConverter]::ToUInt32($sector, 36)

    if ($sectorsPerCluster -le 0 -or $fatCount -le 0 -or $sectorsPerFat -le 0) {
        throw "Invalid FAT32 geometry in $ImagePath."
    }

    return @{
        SectorsPerCluster = $sectorsPerCluster
        DataStartLba = $PartitionLba + $reservedSectors + ($fatCount * $sectorsPerFat)
    }
}

function Get-ContiguousWadMapping {
    param(
        [Parameter(Mandatory = $true)][string]$Mshowfat,
        [Parameter(Mandatory = $true)][string]$ImagePath
    )

    $output = & $Mshowfat "-i" "$ImagePath@@$PartitionOffset" "::DOOM2.WAD" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "mshowfat failed while locating DOOM2.WAD in the image."
    }

    $joined = ($output | Out-String)
    $matches = [regex]::Matches($joined, "<(\d+)-(\d+)>")
    if ($matches.Count -ne 1) {
        throw "DOOM2.WAD must occupy one contiguous FAT32 extent in the image."
    }

    return @{
        StartCluster = [uint32]$matches[0].Groups[1].Value
        EndCluster = [uint32]$matches[0].Groups[2].Value
    }
}

function Write-WadMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$ImagePath,
        [Parameter(Mandatory = $true)][uint32]$StartLba,
        [Parameter(Mandatory = $true)][uint32]$SizeBytes
    )

    $sector = New-Object byte[] 512
    [System.Text.Encoding]::ASCII.GetBytes("WADM").CopyTo($sector, 0)
    [BitConverter]::GetBytes($StartLba).CopyTo($sector, 4)
    [BitConverter]::GetBytes($SizeBytes).CopyTo($sector, 8)
    Write-BytesToImage -Path $ImagePath -Bytes $sector -Offset (512L * $WadMetadataLba)
}

function Get-ObjectPath {
    param([Parameter(Mandatory = $true)][string]$Source)

    $safeName = $Source.Replace("\", "_").Replace("/", "_").Replace(":", "").Replace(".", "_")
    return Join-Path $ObjDir "$safeName.o"
}

function Build-Stage1 {
    param([Parameter(Mandatory = $true)][string]$Nasm)

    Invoke-Tool -Tool $Nasm -Arguments @("-f", "bin", "-o", $Stage1Bin, $Stage1Source)

    if ((Get-Item $Stage1Bin).Length -ne 512) {
        throw "stage1.bin must be exactly 512 bytes."
    }

    Copy-Item -Path $Stage1Bin -Destination $RootBootBin -Force
}

function Compile-CSource {
    param(
        [Parameter(Mandatory = $true)][string]$Clang,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $sourcePath = Join-Path $RepoRoot $Source
    $objectPath = Get-ObjectPath -Source $Source

    Invoke-Tool -Tool $Clang -Arguments @(
        "--target=x86_64-elf",
        "-ffreestanding",
        "-fno-pic",
        "-fno-stack-protector",
        "-mno-red-zone",
        "-Wall",
        "-Wextra",
        "-Wno-unused-parameter",
        "-Wno-sign-compare",
        "-Wno-unused-variable",
        "-Wno-unused-function",
        "-Wno-pointer-sign",
        "-O2",
        "-DCMAP256",
        "-DDOOMGENERIC_RESX=320",
        "-DDOOMGENERIC_RESY=200",
        "-Ikernel\libc",
        "-Ikernel",
        "-Ithird_party\doomgeneric",
        "-c",
        "-o",
        $objectPath,
        $sourcePath
    )

    return $objectPath
}

function Build-Image {
    param(
        [Parameter(Mandatory = $true)][string]$Nasm,
        [Parameter(Mandatory = $true)][string]$Clang,
        [Parameter(Mandatory = $true)][string]$Ld,
        [Parameter(Mandatory = $true)][string]$MkfsFat,
        [Parameter(Mandatory = $true)][string]$Mmd,
        [Parameter(Mandatory = $true)][string]$Mcopy,
        [Parameter(Mandatory = $true)][string]$Mshowfat
    )

    $objectFiles = @()

    if (-not (Test-Path $BootWad)) {
        throw "Missing assets\DOOM2.WAD. Copy your local Doom II WAD there before running .\build.ps1 image."
    }

    Invoke-Tool -Tool $Nasm -Arguments @("-f", "bin", "-o", $Stage2Bin, $Stage2Source)
    Invoke-Tool -Tool $Nasm -Arguments @("-f", "elf64", "-o", $KernelEntryObject, $KernelEntrySource)

    foreach ($source in $KernelSources + $DoomSources) {
        $objectFiles += Compile-CSource -Clang $Clang -Source $source
    }

    $linkArgs = @(
        "-m", "elf_x86_64",
        "-T", $KernelLinkerScript,
        "-nostdlib",
        "-o", $KernelElf,
        $KernelEntryObject
    ) + $objectFiles
    Invoke-Tool -Tool $Ld -Arguments $linkArgs

    $stage2Bytes = [System.IO.File]::ReadAllBytes($Stage2Bin)
    $maxStage2Bytes = 512 * $Stage2ReservedSectors
    if ($stage2Bytes.Length -gt $maxStage2Bytes) {
        throw "stage2.bin is larger than the reserved $Stage2ReservedSectors sectors."
    }

    $imageStream = [System.IO.File]::Open($Image, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $imageStream.SetLength(512L * $ImageSectors)
    }
    finally {
        $imageStream.Dispose()
    }

    Write-BytesToImage -Path $Image -Bytes ([System.IO.File]::ReadAllBytes($Stage1Bin)) -Offset 0
    Write-BytesToImage -Path $Image -Bytes $stage2Bytes -Offset 512

    Invoke-Tool -Tool $MkfsFat -Arguments @("-F", "32", "-s", "1", "--offset=$PartitionLba", $Image)

    $mtoolsImagePath = $Image.Replace("\", "/")
    Set-Content -Path $MtoolsRc -Value "drive z: file=`"$mtoolsImagePath`" offset=$PartitionOffset" -NoNewline

    $previousMtoolsRc = $env:MTOOLSRC
    try {
        $env:MTOOLSRC = $MtoolsRc
        Invoke-Tool -Tool $Mmd -Arguments @("z:/BOOT")
        Invoke-Tool -Tool $Mcopy -Arguments @($KernelElf, "z:/BOOT/KERNEL.ELF")
        Invoke-Tool -Tool $Mcopy -Arguments @($BootWad, "z:/DOOM2.WAD")

        $geometry = Get-Fat32Geometry -ImagePath $Image
        $wadExtent = Get-ContiguousWadMapping -Mshowfat $Mshowfat -ImagePath $Image
        $wadStartLba = [uint32]($geometry.DataStartLba + (($wadExtent.StartCluster - 2) * $geometry.SectorsPerCluster))
        $wadSize = [uint32](Get-Item $BootWad).Length
        Write-WadMetadata -ImagePath $Image -StartLba $wadStartLba -SizeBytes $wadSize
    }
    finally {
        if ($null -eq $previousMtoolsRc) {
            Remove-Item Env:\MTOOLSRC -ErrorAction SilentlyContinue
        }
        else {
            $env:MTOOLSRC = $previousMtoolsRc
        }
    }
}

if ($Target -eq "clean") {
    if (Test-Path $BuildDir) {
        Remove-Item -Path $BuildDir -Recurse -Force
    }
    if (Test-Path $RootBootBin) {
        Remove-Item -Path $RootBootBin -Force
    }
    exit 0
}

Ensure-Dir -Path $BuildDir
Ensure-Dir -Path $ObjDir

$Nasm = Resolve-Tool -Name "nasm" -CandidatePaths @(
    (Join-Path $Msys2Root "usr\bin\nasm.exe")
)

Push-Location $RepoRoot
try {
    Build-Stage1 -Nasm $Nasm

    if ($Target -eq "image") {
        $Clang = Resolve-Tool -Name "clang" -CandidatePaths @(
            (Join-Path $Msys2Root "ucrt64\bin\clang.exe")
        )
        $Ld = Resolve-Tool -Name "ld.lld" -CandidatePaths @(
            (Join-Path $Msys2Root "ucrt64\bin\ld.lld.exe")
        )
        $MkfsFat = Resolve-Tool -Name "mkfs.fat" -CandidatePaths @(
            (Join-Path $Msys2Root "usr\bin\mkfs.fat.exe")
        )
        $Mmd = Resolve-Tool -Name "mmd" -CandidatePaths @(
            (Join-Path $Msys2Root "ucrt64\bin\mmd.exe"),
            (Join-Path $Msys2Root "usr\bin\mmd.exe")
        )
        $Mcopy = Resolve-Tool -Name "mcopy" -CandidatePaths @(
            (Join-Path $Msys2Root "ucrt64\bin\mcopy.exe"),
            (Join-Path $Msys2Root "usr\bin\mcopy.exe")
        )
        $Mshowfat = Resolve-Tool -Name "mshowfat" -CandidatePaths @(
            (Join-Path $Msys2Root "ucrt64\bin\mshowfat.exe"),
            (Join-Path $Msys2Root "usr\bin\mshowfat.exe")
        )

        Build-Image -Nasm $Nasm -Clang $Clang -Ld $Ld -MkfsFat $MkfsFat -Mmd $Mmd -Mcopy $Mcopy -Mshowfat $Mshowfat
        Write-Host "Built full USB image: $Image"
    }
    else {
        Write-Host "Built boot sector: $RootBootBin"
    }
}
finally {
    Pop-Location
}
