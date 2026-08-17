<#
.SYNOPSIS
  IC5980 / CPE-MAX3 diagnostic package decryptor.

.DESCRIPTION
  Decrypts diagnose_enc.tar using the format implemented by dfx_common_new.exe:
  a 44-byte container header, RSA-OAEP wrapped AES material, AES-128-CBC payload,
  and PKCS#7 padding. It then extracts diagnose.tar and exportinfo.tar.gz with
  a built-in safe tar reader. No vendor executable, Python runtime, or tar command
  is required.

.PARAMETER InputPath
  Device export (.zip/.tar containing var/diagnose_enc.tar), or diagnose_enc.tar itself.

.PARAMETER OutDir
  Parent output directory. Defaults to Desktop\IC5980-Decrypted.

.PARAMETER Force
  Replace an existing output directory for the same package name.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$OutDir,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Decrypt-IC5980.ps1 requires PowerShell 7 or later.'
}
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}
$InputPath = (Resolve-Path -LiteralPath $InputPath).Path
if (-not $OutDir) {
    $defaultParent = [Environment]::GetFolderPath('Desktop')
    if (-not $defaultParent) {
        $defaultParent = (Get-Location).Path
    }
    $OutDir = Join-Path $defaultParent 'IC5980-Decrypted'
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
$work = Join-Path ([IO.Path]::GetTempPath()) ("max3-lite-{0}" -f [guid]::NewGuid().ToString('N'))
$keysDir = Join-Path $PSScriptRoot 'keys'
$maxArchiveEntries = 50000
[long]$maxArchiveEntryBytes = 2GB
[long]$maxArchiveExpandedBytes = 4GB

function Read-StreamExactly {
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][byte[]]$Buffer,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][int]$Count,
        [switch]$AllowEndOfStream
    )

    $total = 0
    while ($total -lt $Count) {
        $read = $Stream.Read($Buffer, $Offset + $total, $Count - $total)
        if ($read -eq 0) {
            if ($AllowEndOfStream -and $total -eq 0) {
                return $false
            }
            throw "Unexpected end of archive stream after $total of $Count bytes."
        }
        $total += $read
    }
    return $true
}

function Get-TarString {
    param(
        [Parameter(Mandatory)][byte[]]$Buffer,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][int]$Length
    )

    $end = $Offset
    $limit = $Offset + $Length
    while ($end -lt $limit -and $Buffer[$end] -ne 0) {
        $end++
    }
    if ($end -eq $Offset) {
        return ''
    }
    return [Text.Encoding]::UTF8.GetString($Buffer, $Offset, $end - $Offset).Trim()
}

function Get-TarNumber {
    param(
        [Parameter(Mandatory)][byte[]]$Buffer,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][int]$Length
    )

    if (($Buffer[$Offset] -band 0x80) -ne 0) {
        [long]$value = $Buffer[$Offset] -band 0x7f
        for ($index = 1; $index -lt $Length; $index++) {
            $value = ($value -shl 8) -bor $Buffer[$Offset + $index]
        }
        return $value
    }

    $text = (Get-TarString -Buffer $Buffer -Offset $Offset -Length $Length).Trim()
    if (-not $text) {
        return [long]0
    }
    try {
        return [Convert]::ToInt64($text, 8)
    } catch {
        throw "Invalid tar numeric field: '$text'"
    }
}

function Test-TarHeaderChecksum {
    param([Parameter(Mandatory)][byte[]]$Header)

    $stored = Get-TarNumber -Buffer $Header -Offset 148 -Length 8
    [long]$sum = 0
    for ($index = 0; $index -lt 512; $index++) {
        if ($index -ge 148 -and $index -lt 156) {
            $sum += 32
        } else {
            $sum += $Header[$index]
        }
    }
    return $stored -eq $sum
}

function Read-TarPayloadBytes {
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][long]$Size
    )

    if ($Size -gt [int]::MaxValue) {
        throw "Tar metadata entry is too large: $Size bytes"
    }
    [byte[]]$data = [byte[]]::new([int]$Size)
    if ($Size -gt 0) {
        Read-StreamExactly -Stream $Stream -Buffer $data -Offset 0 -Count ([int]$Size) | Out-Null
    }
    return ,$data
}

function Skip-TarPadding {
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][long]$Size
    )

    $padding = [int]((512 - ($Size % 512)) % 512)
    if ($padding -gt 0) {
        [byte[]]$discard = [byte[]]::new($padding)
        Read-StreamExactly -Stream $Stream -Buffer $discard -Offset 0 -Count $padding | Out-Null
    }
}

function Copy-TarPayload {
    param(
        [Parameter(Mandatory)][IO.Stream]$InputStream,
        [Parameter(Mandatory)][IO.Stream]$OutputStream,
        [Parameter(Mandatory)][long]$Size
    )

    [byte[]]$buffer = [byte[]]::new(65536)
    [long]$remaining = $Size
    while ($remaining -gt 0) {
        $count = [int][Math]::Min($buffer.Length, $remaining)
        Read-StreamExactly -Stream $InputStream -Buffer $buffer -Offset 0 -Count $count | Out-Null
        $OutputStream.Write($buffer, 0, $count)
        $remaining -= $count
    }
}

function Get-SafeTarTargetPath {
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$EntryPath
    )

    $normalized = $EntryPath.Replace('\', '/')
    while ($normalized.StartsWith('./')) {
        $normalized = $normalized.Substring(2)
    }
    if (-not $normalized -or $normalized.StartsWith('/')) {
        throw "Unsafe tar entry path: '$EntryPath'"
    }

    $root = [IO.Path]::GetFullPath($Destination)
    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    $safeSegments = foreach ($segment in $normalized.Split('/')) {
        if (-not $segment -or $segment -eq '.') {
            continue
        }
        if ($segment -eq '..') {
            throw "Tar entry escapes destination: '$EntryPath'"
        }

        $builder = [Text.StringBuilder]::new($segment.Length)
        foreach ($character in $segment.ToCharArray()) {
            if ($character -eq ':' -or $invalidChars -contains $character) {
                $null = $builder.Append('_')
            } else {
                $null = $builder.Append($character)
            }
        }
        $safeSegment = $builder.ToString()
        if (-not $safeSegment) {
            throw "Unsafe tar entry path: '$EntryPath'"
        }
        $safeSegment
    }
    if (-not $safeSegments) {
        throw "Unsafe tar entry path: '$EntryPath'"
    }

    $relative = $safeSegments -join [IO.Path]::DirectorySeparatorChar
    $target = [IO.Path]::GetFullPath((Join-Path $root $relative))
    $rootPrefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Tar entry escapes destination: '$EntryPath'"
    }
    return $target
}

function Get-PaxPath {
    param([Parameter(Mandatory)][byte[]]$Data)

    $text = [Text.Encoding]::UTF8.GetString($Data)
    foreach ($line in $text -split "`n") {
        $separator = $line.IndexOf(' ')
        if ($separator -lt 0) {
            continue
        }
        $record = $line.Substring($separator + 1).TrimEnd("`r")
        if ($record.StartsWith('path=')) {
            return $record.Substring(5)
        }
    }
    return $null
}

function Expand-TarStream {
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][string]$Destination
    )

    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    [byte[]]$header = [byte[]]::new(512)
    $pendingPath = $null
    $entryCount = 0
    [long]$expandedBytes = 0
    $writtenFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    while (Read-StreamExactly -Stream $Stream -Buffer $header -Offset 0 -Count 512 -AllowEndOfStream) {
        $hasContent = $false
        foreach ($value in $header) {
            if ($value -ne 0) {
                $hasContent = $true
                break
            }
        }
        if (-not $hasContent) {
            break
        }
        if (-not (Test-TarHeaderChecksum -Header $header)) {
            throw 'Tar header checksum validation failed.'
        }

        $entryCount++
        if ($entryCount -gt $maxArchiveEntries) {
            throw "Tar entry limit exceeded: $maxArchiveEntries"
        }

        $name = Get-TarString -Buffer $header -Offset 0 -Length 100
        $prefix = Get-TarString -Buffer $header -Offset 345 -Length 155
        if ($prefix) {
            $name = "$prefix/$name"
        }
        $size = Get-TarNumber -Buffer $header -Offset 124 -Length 12
        $typeFlag = [char]$header[156]
        if ($size -gt $maxArchiveEntryBytes) {
            throw "Tar entry is larger than the allowed limit: $size bytes"
        }
        $expandedBytes += $size
        if ($expandedBytes -gt $maxArchiveExpandedBytes) {
            throw "Tar expanded-size limit exceeded: $maxArchiveExpandedBytes bytes"
        }

        if ($typeFlag -eq 'L') {
            $longNameData = Read-TarPayloadBytes -Stream $Stream -Size $size
            $pendingPath = [Text.Encoding]::UTF8.GetString($longNameData).
                Trim([char[]]@([char]0, [char]13, [char]10))
            Skip-TarPadding -Stream $Stream -Size $size
            continue
        }
        if ($typeFlag -eq 'x' -or $typeFlag -eq 'g') {
            $paxData = Read-TarPayloadBytes -Stream $Stream -Size $size
            $paxPath = Get-PaxPath -Data $paxData
            if ($paxPath) {
                $pendingPath = $paxPath
            }
            Skip-TarPadding -Stream $Stream -Size $size
            continue
        }

        $entryPath = if ($pendingPath) { $pendingPath } else { $name }
        $pendingPath = $null

        if ($typeFlag -eq '5') {
            $directoryPath = Get-SafeTarTargetPath -Destination $Destination -EntryPath $entryPath
            [IO.Directory]::CreateDirectory($directoryPath) | Out-Null
        } elseif ($typeFlag -eq '0' -or $typeFlag -eq [char]0) {
            $filePath = Get-SafeTarTargetPath -Destination $Destination -EntryPath $entryPath
            if (-not $writtenFiles.Add($filePath)) {
                throw "Duplicate tar output path: '$entryPath'"
            }
            $parent = [IO.Path]::GetDirectoryName($filePath)
            if ($parent) {
                [IO.Directory]::CreateDirectory($parent) | Out-Null
            }
            $output = [IO.File]::Open($filePath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                Copy-TarPayload -InputStream $Stream -OutputStream $output -Size $size
            } finally {
                $output.Dispose()
            }
        } else {
            if ($size -gt 0) {
                [byte[]]$discard = [byte[]]::new(65536)
                [long]$remaining = $size
                while ($remaining -gt 0) {
                    $count = [int][Math]::Min($discard.Length, $remaining)
                    Read-StreamExactly -Stream $Stream -Buffer $discard -Offset 0 -Count $count | Out-Null
                    $remaining -= $count
                }
            }
        }
        Skip-TarPadding -Stream $Stream -Size $size
    }
}

function Expand-TarArchive {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$GZip
    )

    $fileStream = [IO.File]::OpenRead($ArchivePath)
    try {
        if ($GZip) {
            $archiveStream = [IO.Compression.GZipStream]::new(
                $fileStream,
                [IO.Compression.CompressionMode]::Decompress,
                $true
            )
            try {
                Expand-TarStream -Stream $archiveStream -Destination $Destination
            } finally {
                $archiveStream.Dispose()
            }
        } else {
            Expand-TarStream -Stream $fileStream -Destination $Destination
        }
    } finally {
        $fileStream.Dispose()
    }
}

function Get-DiagnoseEncPath {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Workspace
    )

    $sourceStream = [IO.File]::OpenRead($Source)
    try {
        [byte[]]$bytes = [byte[]]::new([int][Math]::Min(512, $sourceStream.Length))
        if ($bytes.Length -gt 0) {
            Read-StreamExactly -Stream $sourceStream -Buffer $bytes -Offset 0 -Count $bytes.Length | Out-Null
        }
    } finally {
        $sourceStream.Dispose()
    }
    if ($bytes.Length -lt 16) {
        throw 'Input file is too short.'
    }

    # Raw encrypted container: 05 05 46 08 ...
    if ($bytes[0] -eq 0x05 -and $bytes[1] -eq 0x05 -and $bytes[2] -eq 0x46 -and $bytes[3] -eq 0x08) {
        return $Source
    }

    $head = [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(16, $bytes.Length))
    if ($head.StartsWith('PK')) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($Source)
        try {
            $candidates = @($zip.Entries | Where-Object { [IO.Path]::GetFileName($_.FullName) -ieq 'diagnose_enc.tar' })
            if ($candidates.Count -ne 1) {
                throw "Expected exactly one diagnose_enc.tar in ZIP; found $($candidates.Count)."
            }
            if ($candidates[0].Length -gt $maxArchiveEntryBytes) {
                throw "diagnose_enc.tar is larger than the allowed limit: $($candidates[0].Length) bytes"
            }
            $target = Join-Path $Workspace 'diagnose_enc.tar'
            $input = $candidates[0].Open()
            $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $input.CopyTo($output)
            } finally {
                $output.Dispose()
                $input.Dispose()
            }
            return $target
        } finally {
            $zip.Dispose()
        }
    } else {
        try {
            Expand-TarArchive -ArchivePath $Source -Destination $Workspace
        } catch {
            throw ('Unsupported input format or invalid tar archive. First 16 bytes: {0}. {1}' -f [Convert]::ToHexString($bytes[0..15]), $_.Exception.Message)
        }
    }

    $found = @(Get-ChildItem -LiteralPath $Workspace -Recurse -File -Filter 'diagnose_enc.tar')
    if ($found.Count -ne 1) {
        throw "Expected exactly one diagnose_enc.tar in the device export; found $($found.Count)."
    }
    return $found[0].FullName
}

function Unprotect-DiagnoseContainer {
    param(
        [Parameter(Mandatory)][string]$EncryptedPath,
        [Parameter(Mandatory)][string]$PlainTarPath
    )

    $headerLength = 44
    $sourceStream = [IO.File]::OpenRead($EncryptedPath)
    try {
        if ($sourceStream.Length -lt ($headerLength + 256)) {
            throw 'Encrypted container is truncated.'
        }
        [byte[]]$header = [byte[]]::new($headerLength)
        Read-StreamExactly -Stream $sourceStream -Buffer $header -Offset 0 -Count $headerLength | Out-Null
        if ($header[0] -ne 0x05 -or $header[1] -ne 0x05 -or $header[2] -ne 0x46 -or $header[3] -ne 0x08) {
            throw 'Encrypted container magic is not supported.'
        }

        $version = [int]$header[8]
        if ($version -notin @(1, 3)) {
            $inputHash = (Get-FileHash -LiteralPath $EncryptedPath -Algorithm SHA256).Hash.ToLowerInvariant()
            throw "Unsupported encrypted container version $version (length=$($sourceStream.Length), sha256=$inputHash)."
        }
        $rsaLength = if ($version -eq 3) { 384 } else { 256 }
    $keyFile = if ($version -eq 3) { 'rsa-3072.txt' } else { 'rsa-2048.txt' }
    $keyPath = Join-Path $keysDir $keyFile
    if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) {
        throw "Compatibility key file not found: $keyPath"
    }
        if ($sourceStream.Length -le ($headerLength + $rsaLength)) {
            throw 'Encrypted container has no AES payload.'
        }

        [byte[]]$wrappedMaterial = [byte[]]::new($rsaLength)
        Read-StreamExactly -Stream $sourceStream -Buffer $wrappedMaterial -Offset 0 -Count $rsaLength | Out-Null

        $rsa = [Security.Cryptography.RSA]::Create()
        try {
            $pem = [IO.File]::ReadAllText($keyPath, [Text.Encoding]::ASCII)
            $base64Key = $pem.Replace('-----BEGIN RSA PRIVATE KEY-----', '').
                Replace('-----END RSA PRIVATE KEY-----', '') -replace '\s', ''
            [byte[]]$derKey = [Convert]::FromBase64String($base64Key)
            $bytesRead = 0
            $rsa.ImportRSAPrivateKey($derKey, [ref]$bytesRead)
            if ($bytesRead -ne $derKey.Length) {
                throw "RSA key import consumed $bytesRead of $($derKey.Length) bytes."
            }
            [byte[]]$aesMaterial = $rsa.Decrypt(
                $wrappedMaterial,
                [Security.Cryptography.RSAEncryptionPadding]::OaepSHA1
            )
        } finally {
            $rsa.Dispose()
        }
        if ($aesMaterial.Length -lt 32) {
            throw "Invalid AES material length: $($aesMaterial.Length)"
        }

        [byte[]]$iv = [byte[]]::new(16)
        [byte[]]$aesKey = [byte[]]::new(16)
        [Array]::Copy($aesMaterial, 0, $iv, 0, 16)
        [Array]::Copy($aesMaterial, 16, $aesKey, 0, 16)

        $cipherLength = $sourceStream.Length - $headerLength - $rsaLength
        if (($cipherLength % 16) -ne 0) {
            throw "AES-CBC payload is not block-aligned: $cipherLength bytes"
        }

        $aes = [Security.Cryptography.Aes]::Create()
        try {
            $aes.Mode = [Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
            $aes.Key = $aesKey
            $aes.IV = $iv
            $decryptor = $aes.CreateDecryptor()
            $crypto = [Security.Cryptography.CryptoStream]::new(
                $sourceStream,
                $decryptor,
                [Security.Cryptography.CryptoStreamMode]::Read,
                $true
            )
            $plainStream = [IO.File]::Open($PlainTarPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $crypto.CopyTo($plainStream, 65536)
            } finally {
                $plainStream.Dispose()
                $crypto.Dispose()
                $decryptor.Dispose()
            }
        } finally {
            $aes.Dispose()
        }
    } finally {
        $sourceStream.Dispose()
    }
    return $version
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    Write-Host '[1/4] Locating diagnose_enc.tar ...' -ForegroundColor Cyan
    $encryptedPath = Get-DiagnoseEncPath -Source $InputPath -Workspace $work

    Write-Host '[2/4] Decrypting RSA-OAEP + AES-CBC container ...' -ForegroundColor Cyan
    $plainTar = Join-Path $work 'diagnose.tar'
    $formatVersion = Unprotect-DiagnoseContainer -EncryptedPath $encryptedPath -PlainTarPath $plainTar

    Write-Host '[3/4] Extracting diagnose.tar and exportinfo.tar.gz ...' -ForegroundColor Cyan
    $layer1 = Join-Path $work 'layer1'
    $layer2 = Join-Path $work 'layer2'
    New-Item -ItemType Directory -Path $layer1, $layer2 -Force | Out-Null
    Expand-TarArchive -ArchivePath $plainTar -Destination $layer1
    $exportArchives = @(Get-ChildItem -LiteralPath $layer1 -Recurse -File -Filter 'exportinfo.tar.gz')
    if ($exportArchives.Count -ne 1) {
        throw "Expected exactly one exportinfo.tar.gz after decryption; found $($exportArchives.Count)."
    }
    Expand-TarArchive -ArchivePath $exportArchives[0].FullName -Destination $layer2 -GZip

    $mobilelogs = @(Get-ChildItem -LiteralPath $layer2 -Recurse -Directory -Filter 'mobilelog')
    if ($mobilelogs.Count -ne 1) {
        throw "Expected exactly one mobilelog directory; found $($mobilelogs.Count)."
    }

    Write-Host '[4/4] Copying decrypted logs ...' -ForegroundColor Cyan
    $finalOut = Join-Path $OutDir $baseName
    if (Test-Path -LiteralPath $finalOut) {
        if (-not $Force) {
            throw "Output already exists: $finalOut (use -Force to replace it)"
        }
        Remove-Item -LiteralPath $finalOut -Recurse -Force
    }
    New-Item -ItemType Directory -Path $finalOut -Force | Out-Null
    Copy-Item -LiteralPath $mobilelogs[0].FullName -Destination (Join-Path $finalOut 'mobilelog') -Recurse

    Write-Host ''
    Write-Host "Decryption complete (format version $formatVersion)." -ForegroundColor Green
    Write-Host "Logs: $finalOut\mobilelog" -ForegroundColor Yellow
    return $finalOut
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
