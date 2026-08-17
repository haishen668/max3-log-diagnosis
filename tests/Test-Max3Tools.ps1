[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("max3-tests-{0}" -f [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $mobilelog = Join-Path $tempRoot 'sample/mobilelog'
    $logDir = Join-Path $mobilelog 'log'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $plainLines = @(
        '[I)20260817143913.000 network:1]:[Hcsq] [sysmode]=NOSERVICE SIG=[0]',
        '[I)20260817143914.000 network:2]:[NetServiceStateChange] no service',
        '[I)20260817143951.000 dialup:3]:ndisstat ipv4Status = 3',
        '[I)20260817143956.000 mqtt:4]:Failed to WJMqttConnect imei=123456789012345 ip=10.9.8.7 mac=AA:BB:CC:DD:EE:FF'
    )
    [IO.File]::WriteAllLines((Join-Path $logDir 'app.log'), $plainLines, [Text.UTF8Encoding]::new($false))

    $gzipPath = Join-Path $logDir 'app.log-2026-08-17-14_40_00.gz'
    $gzipFile = [IO.File]::Create($gzipPath)
    try {
        $gzip = [IO.Compression.GZipStream]::new($gzipFile, [IO.Compression.CompressionLevel]::Optimal, $true)
        try {
            $writer = [IO.StreamWriter]::new($gzip, [Text.UTF8Encoding]::new($false), 4096, $true)
            try {
                $writer.WriteLine('[E)20260817143947.000 atserver:5]:[AtReadCmdNas] No data from NAS')
                $writer.WriteLine('[I)20260817144000.000 network:6]:[Hcsq] [sysmode]=NR SIG=[5]')
            } finally {
                $writer.Dispose()
            }
        } finally {
            $gzip.Dispose()
        }
    } finally {
        $gzipFile.Dispose()
    }

    $indexOut = Join-Path $tempRoot 'index'
    & (Join-Path $repoRoot 'scripts/Build-Max3LogIndex.ps1') $mobilelog -OutDir $indexOut | Out-Null
    $summary = @(Import-Csv (Join-Path $indexOut '02-event-summary.csv'))
    $inventory = @(Import-Csv (Join-Path $indexOut '01-file-inventory.csv'))
    $allOutput = (Get-ChildItem -LiteralPath $indexOut -File | ForEach-Object {
        Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
    }) -join "`n"

    Assert-True (($summary | Where-Object category -eq 'cell_no_service').count -eq '1') 'no-service event count'
    Assert-True (($summary | Where-Object category -eq 'nas_no_data').count -eq '1') 'gzip NAS event count'
    Assert-True (($inventory | Where-Object kind -eq 'gzip').Count -eq 1) 'gzip file inventory'
    Assert-True ($allOutput -notmatch '123456789012345') 'IMEI redaction'
    Assert-True ($allOutput -notmatch '10\.9\.8\.7') 'IPv4 redaction'
    Assert-True ($allOutput -notmatch 'AA:BB:CC:DD:EE:FF') 'MAC redaction'

    $unknownContainer = Join-Path $tempRoot 'unknown-version.tar'
    [byte[]]$unknownBytes = [byte[]]::new(400)
    $unknownBytes[0] = 0x05
    $unknownBytes[1] = 0x05
    $unknownBytes[2] = 0x46
    $unknownBytes[3] = 0x08
    $unknownBytes[8] = 99
    [IO.File]::WriteAllBytes($unknownContainer, $unknownBytes)
    $rejected = $false
    try {
        & (Join-Path $repoRoot 'scripts/Decrypt-IC5980.ps1') $unknownContainer -OutDir (Join-Path $tempRoot 'decrypt') | Out-Null
    } catch {
        $rejected = $_.Exception.Message -match 'Unsupported encrypted container version 99'
    }
    Assert-True $rejected 'unknown encrypted-container version must be rejected'

    Write-Host 'All MAX3 tool tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
