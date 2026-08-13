<#
.SYNOPSIS
  IC5980 加密诊断包一键解密工具

.DESCRIPTION
  输入 IC5980 下载的 .zip / .tar 包（内部含 var/diagnose_enc.tar 加密文件），
  自动判断格式、解包、调用 dfx_common_new.exe 解密，输出明文日志目录路径。

.PARAMETER InputPath
  IC5980 诊断包路径（.zip 或 .tar，下载下来的原始文件）。

.PARAMETER ToolDir
  dfx_common_new.exe 所在目录（默认脚本同级的 decrypt-tool 子目录）。

.PARAMETER OutDir
  解密结果输出目录（默认 Desktop\IC5980-Decrypted）。

.EXAMPLE
  .\Decrypt-IC5980.ps1 'C:\Downloads\IC5980_xxxx_20260813101710.zip'

.EXAMPLE
  .\Decrypt-IC5980.ps1 'C:\Downloads\IC5980_xxxx.zip' -OutDir 'D:\logs'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$ToolDir,

    [Parameter(Position = 2)]
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InputPath)) {
    Write-Error "找不到输入文件: $InputPath"
    exit 1
}
$InputPath = (Resolve-Path -LiteralPath $InputPath).Path

if (-not $ToolDir) {
    $ToolDir = Join-Path $PSScriptRoot 'decrypt-tool'
}
if (-not (Test-Path -LiteralPath $ToolDir)) {
    Write-Error "找不到解密工具目录: $ToolDir`n请把 dfx_common_new.exe、7za.exe 和两个 XML 放到该目录。"
    exit 1
}

$exe   = Join-Path $ToolDir 'dfx_common_new.exe'
$sevenZ = Join-Path $ToolDir '7za.exe'
foreach ($f in @($exe, $sevenZ)) {
    if (-not (Test-Path -LiteralPath $f)) {
        Write-Error "工具目录缺少文件: $f"
        exit 1
    }
}

if (-not $OutDir) {
    $OutDir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'IC5980-Decrypted'
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
$work = Join-Path ([IO.Path]::GetTempPath()) ("ic5980_" + $baseName)
if (Test-Path -LiteralPath $work) { Remove-Item -Recurse -Force -LiteralPath $work }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$staging = Join-Path $work 'staging'
$varDir  = Join-Path $staging 'var'
New-Item -ItemType Directory -Force -Path $varDir | Out-Null

Write-Host '[1/4] 读取输入文件并提取 diagnose_enc.tar ...' -ForegroundColor Cyan

$bytes = [IO.File]::ReadAllBytes($InputPath)
$head  = [Text.Encoding]::ASCII.GetString($bytes[0..15])

$encTar = $null
if ($head.StartsWith('var/') -or $head.StartsWith('var\')) {
    # 输入本身就是 tar
    tar -xf $InputPath -C $work 'var/diagnose_enc.tar' 2>$null
    $encTar = Join-Path $work 'var\diagnose_enc.tar'
    if (-not (Test-Path -LiteralPath $encTar)) {
        # tar 解压到 work/var 下
        tar -xf $InputPath -C $work
        $encTar = Get-ChildItem -LiteralPath $work -Recurse -Filter 'diagnose_enc.tar' | Select-Object -First 1 -ExpandProperty FullName
    }
} elseif ($head.Substring(0,2) -eq 'PK') {
    # 输入是 zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($InputPath, $work, $true)
    $encTar = Get-ChildItem -LiteralPath $work -Recurse -Filter 'diagnose_enc.tar' | Select-Object -First 1 -ExpandProperty FullName
} else {
    Write-Error "无法识别的文件格式。前16字节: $head"
    exit 1
}

if (-not $encTar -or -not (Test-Path -LiteralPath $encTar)) {
    Write-Error '未在输入文件中找到 diagnose_enc.tar'
    exit 1
}
Write-Host "      -> $encTar"

Write-Host '[2/4] 构建 dfx 工具所需的 zip 结构 ...' -ForegroundColor Cyan
Copy-Item -LiteralPath $encTar -Destination (Join-Path $varDir 'diagnose_enc.tar') -Force

$zipName = $baseName + '.zip'
$zipPath = Join-Path $work $zipName
Push-Location $staging
try {
    & $sevenZ a -tzip $zipPath 'var\diagnose_enc.tar' 2>&1 | Out-Null
} finally {
    Pop-Location
}

Write-Host '[3/4] 调用 dfx_common_new.exe 解密 ...' -ForegroundColor Cyan

# 工具把 decompress 输出到 exe 所在目录，所以直接在 ToolDir 内操作
Copy-Item -LiteralPath $zipPath -Destination (Join-Path $ToolDir $zipName) -Force

# 清理上次的 decompress 残留
$oldDecompress = Join-Path $ToolDir 'decompress'
if (Test-Path -LiteralPath $oldDecompress) { Remove-Item -Recurse -Force -LiteralPath $oldDecompress }

$logFile = Join-Path $work 'dfx-output.txt'
$proc = Start-Process -FilePath $exe -ArgumentList '-p', (Join-Path $ToolDir $zipName) `
    -NoNewWindow -PassThru -Wait `
    -WorkingDirectory $ToolDir `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError (Join-Path $work 'dfx-error.txt')

# 清理 ToolDir 里的临时 zip
Remove-Item -LiteralPath (Join-Path $ToolDir $zipName) -Force -ErrorAction SilentlyContinue

if ($proc.ExitCode -ne 0) {
    Write-Host (Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue) -ForegroundColor DarkGray
    Write-Error "dfx_common_new.exe 退出码: $($proc.ExitCode)"
    exit 1
}

$decryptedRoot = Join-Path $ToolDir ("decompress\" + $zipName)
if (-not (Test-Path -LiteralPath $decryptedRoot)) {
    Write-Error "解密完成但未找到输出目录: $decryptedRoot"
    exit 1
}

Write-Host '[4/4] 复制解密结果到输出目录 ...' -ForegroundColor Cyan
$finalOut = Join-Path $OutDir $baseName
if (Test-Path -LiteralPath $finalOut) { Remove-Item -Recurse -Force -LiteralPath $finalOut }
New-Item -ItemType Directory -Force -Path $finalOut | Out-Null

$mobilelog = Get-ChildItem -LiteralPath $decryptedRoot -Recurse -Directory -Filter 'mobilelog' |
    Select-Object -First 1 -ExpandProperty FullName
if ($mobilelog) {
    Copy-Item -Recurse -LiteralPath $mobilelog -Destination (Join-Path $finalOut 'mobilelog')
} else {
    Copy-Item -Recurse -LiteralPath $decryptedRoot -Destination $finalOut
}

Write-Host ''
Write-Host '解密完成。' -ForegroundColor Green
Write-Host "日志目录: $finalOut\mobilelog" -ForegroundColor Yellow
Write-Host ''
Write-Host '常用子目录:' -ForegroundColor DarkGray
Write-Host '  log\          应用日志 (app.log-*.gz)' -ForegroundColor DarkGray
Write-Host '  kernel\       内核日志 (kmsg.log-*.gz)' -ForegroundColor DarkGray
Write-Host '  pstore\       重启记录 (console-ramoops)' -ForegroundColor DarkGray
Write-Host '  modem_log\    基带日志' -ForegroundColor DarkGray
Write-Host ''
Write-Host '提示: 临时工作目录可安全删除' -ForegroundColor DarkGray
Write-Host "  $work" -ForegroundColor DarkGray

Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue

return $finalOut
