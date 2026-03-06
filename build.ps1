param(
    [ValidateSet("stage1", "image", "clean")]
    [string]$Target = "image"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $RepoRoot "build"

$Stage1Source = Join-Path $RepoRoot "boot.asm"
$Stage2Source = Join-Path $RepoRoot "boot\stage2.asm"
$KernelEntrySource = Join-Path $RepoRoot "kernel\entry.asm"
$KernelMainSource = Join-Path $RepoRoot "kernel\main.c"
$KernelLinkerScript = Join-Path $RepoRoot "kernel\link.ld"

$RootBootBin = Join-Path $RepoRoot "boot.bin"
$Stage1Bin = Join-Path $BuildDir "stage1.bin"
$Stage2Bin = Join-Path $BuildDir "stage2.bin"
$KernelEntryObject = Join-Path $BuildDir "kernel_entry.o"
$KernelMainObject = Join-Path $BuildDir "kernel_main.o"
$KernelElf = Join-Path $BuildDir "kernel.elf"
$Image = Join-Path $BuildDir "disk.img"
$MtoolsRc = Join-Path $BuildDir "mtoolsrc"

$ImageSectors = 131072
$PartitionLba = 2048
$PartitionOffset = 1048576
$Stage2ReservedSectors = 128

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

function Ensure-BuildDir {
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir | Out-Null
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

function Build-Stage1 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Nasm
    )

    Invoke-Tool -Tool $Nasm -Arguments @("-f", "bin", "-o", $Stage1Bin, $Stage1Source)

    if ((Get-Item $Stage1Bin).Length -ne 512) {
        throw "stage1.bin must be exactly 512 bytes."
    }

    Copy-Item -Path $Stage1Bin -Destination $RootBootBin -Force
}

function Build-Image {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Nasm,
        [Parameter(Mandatory = $true)]
        [string]$Clang,
        [Parameter(Mandatory = $true)]
        [string]$Ld,
        [Parameter(Mandatory = $true)]
        [string]$MkfsFat,
        [Parameter(Mandatory = $true)]
        [string]$Mmd,
        [Parameter(Mandatory = $true)]
        [string]$Mcopy
    )

    Invoke-Tool -Tool $Nasm -Arguments @("-f", "bin", "-o", $Stage2Bin, $Stage2Source)
    Invoke-Tool -Tool $Nasm -Arguments @("-f", "elf64", "-o", $KernelEntryObject, $KernelEntrySource)
    Invoke-Tool -Tool $Clang -Arguments @(
        "--target=x86_64-elf",
        "-ffreestanding",
        "-fno-pic",
        "-fno-stack-protector",
        "-mno-red-zone",
        "-Wall",
        "-Wextra",
        "-O2",
        "-Ikernel",
        "-c",
        "-o",
        $KernelMainObject,
        $KernelMainSource
    )
    Invoke-Tool -Tool $Ld -Arguments @(
        "-m",
        "elf_x86_64",
        "-T",
        $KernelLinkerScript,
        "-nostdlib",
        "-o",
        $KernelElf,
        $KernelEntryObject,
        $KernelMainObject
    )

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

Ensure-BuildDir

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

        Build-Image -Nasm $Nasm -Clang $Clang -Ld $Ld -MkfsFat $MkfsFat -Mmd $Mmd -Mcopy $Mcopy
        Write-Host "Built full USB image: $Image"
    }
    else {
        Write-Host "Built boot sector: $RootBootBin"
    }
}
finally {
    Pop-Location
}
