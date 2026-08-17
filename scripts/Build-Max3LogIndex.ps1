<#
.SYNOPSIS
  Builds a compact, redacted AI index for decrypted MAX3/IC5980 logs.

.DESCRIPTION
  Streams the mobilelog tree once and produces a small evidence package:
  file inventory, event counts, a de-duplicated timeline, representative
  evidence, and a JSON manifest. Original logs are never modified.

.PARAMETER InputPath
  A mobilelog directory, or a parent directory containing mobilelog.

.PARAMETER OutDir
  Output directory. Defaults to <package>\ai-index.

.PARAMETER StartTime
  Optional inclusive local device-log time, for example 2026-08-17 14:30:00.

.PARAMETER EndTime
  Optional inclusive local device-log time.

.PARAMETER MaxTimelineRows
  Maximum rows written to the compact timeline. Defaults to 5000.

.PARAMETER Force
  Replace an existing index directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$OutDir,

    [string]$StartTime,

    [string]$EndTime,

    [ValidateRange(100, 50000)]
    [int]$MaxTimelineRows = 2000,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Build-Max3LogIndex.ps1 requires PowerShell 7 or later.'
}
if (-not (Test-Path -LiteralPath $InputPath -PathType Container)) {
    throw "Input directory not found: $InputPath"
}

$InputPath = (Resolve-Path -LiteralPath $InputPath).Path
$mobilelog = if ((Split-Path -Leaf $InputPath) -ieq 'mobilelog') {
    $InputPath
} else {
    Get-ChildItem -LiteralPath $InputPath -Recurse -Directory -Filter 'mobilelog' |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $mobilelog) {
    throw "No mobilelog directory was found below: $InputPath"
}

$packageRoot = Split-Path -Parent $mobilelog
if (-not $OutDir) {
    $OutDir = Join-Path $packageRoot 'ai-index'
}
$OutDir = [IO.Path]::GetFullPath($OutDir)
if (Test-Path -LiteralPath $OutDir) {
    if (-not $Force) {
        throw "Output already exists: $OutDir (use -Force to replace it)"
    }
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$culture = [Globalization.CultureInfo]::InvariantCulture
$timeStyles = [Globalization.DateTimeStyles]::AllowWhiteSpaces

function ConvertTo-OptionalDateTime {
    param([string]$Value, [string]$Name)

    if (-not $Value) {
        return $null
    }
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Value, $culture, $timeStyles, [ref]$parsed)) {
        throw "Invalid $Name value: '$Value'"
    }
    return $parsed
}

$start = ConvertTo-OptionalDateTime -Value $StartTime -Name 'StartTime'
$end = ConvertTo-OptionalDateTime -Value $EndTime -Name 'EndTime'
if ($start -and $end -and $start -gt $end) {
    throw 'StartTime must not be later than EndTime.'
}

function Get-RelativePathSafe {
    param([string]$BasePath, [string]$Path)
    return [IO.Path]::GetRelativePath($BasePath, $Path).Replace('\', '/')
}

function Get-LogFileKind {
    param([string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -ge 2) {
            $first = $stream.ReadByte()
            $second = $stream.ReadByte()
            if ($first -eq 0x1f -and $second -eq 0x8b) {
                return 'gzip'
            }
            $stream.Position = 0
        }
        $length = [int][Math]::Min(4096, $stream.Length)
        if ($length -eq 0) {
            return 'text'
        }
        [byte[]]$buffer = [byte[]]::new($length)
        $read = $stream.Read($buffer, 0, $length)
        for ($index = 0; $index -lt $read; $index++) {
            if ($buffer[$index] -eq 0) {
                return 'binary'
            }
        }
        return 'text'
    } finally {
        $stream.Dispose()
    }
}

function Get-StringSha256 {
    param([string]$Value)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [byte[]]$bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return [Convert]::ToHexString($sha.ComputeHash($bytes)).ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-LogTimestamp {
    param([string]$Line)

    $match = [regex]::Match($Line, '(?<!\d)(?<ts>20\d{12}(?:\.\d{1,6})?)(?!\d)')
    if ($match.Success) {
        $raw = $match.Groups['ts'].Value
        foreach ($format in @('yyyyMMddHHmmss.ffffff', 'yyyyMMddHHmmss.fff', 'yyyyMMddHHmmss')) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParseExact($raw, $format, $culture, $timeStyles, [ref]$parsed)) {
                return $parsed
            }
        }
    }

    $match = [regex]::Match(
        $Line,
        '(?<!\d)(?<ts>20\d{2}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[\.,]\d{1,6})?)(?!\d)'
    )
    if ($match.Success) {
        $raw = $match.Groups['ts'].Value.Replace('/', '-').Replace(',', '.')
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($raw, $culture, $timeStyles, [ref]$parsed)) {
            return $parsed
        }
    }
    return $null
}

function Protect-LogText {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }
    $value = $Text
    $value = [regex]::Replace(
        $value,
        '(?i)(\b(?:imei|imsi|iccid|deviceid|serial(?:number)?|webpwd|password|passwd|token|api[_ -]?key)\b\s*["''=: ]+)([^,;\s"'']+)',
        '$1<REDACTED>'
    )
    $value = [regex]::Replace($value, '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])', '<IP>')
    $value = [regex]::Replace($value, '(?i)(?<![0-9a-f])(?:[0-9a-f]{2}:){5}[0-9a-f]{2}(?![0-9a-f])', '<MAC>')
    return $value
}

function Get-NormalizedMessage {
    param([string]$Line)

    $message = Protect-LogText -Text $Line
    $message = [regex]::Replace($message, '^\[[A-Z]\)20\d{12}(?:\.\d+)?\s+[^\]]+\]:', '')
    $message = [regex]::Replace($message, '^20\d{2}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[\.,]\d+)?\s*', '')
    $message = [regex]::Replace($message, '\s+', ' ').Trim()
    if ($message.Length -gt 500) {
        $message = $message.Substring(0, 500) + '...'
    }
    return $message
}

function Get-TimelineState {
    param([string]$Category, [string]$Message)

    switch ($Category) {
        'reboot_self_healing' { return 'system self-healing reboot' }
        'reboot_webui' { return 'WebUI reboot' }
        'reboot_upgrade' { return 'system upgrade reboot' }
        'reboot_cold_start' { return 'cold start' }
        'reboot_restart_system' { return 'controlled restart sequence' }
        'kernel_panic' { return $Message }
        'kernel_oom' { return $Message }
        'cell_no_service' { return 'network service lost' }
        'cell_sysmode_noservice' { return 'sysmode=NOSERVICE' }
        'cell_sysmode_nr' { return 'sysmode=NR' }
        'cell_sysmode_lte' { return 'sysmode=LTE' }
        'cell_signal_zero' { return 'signal=0' }
        'dialup_disconnected' { return 'dialup disconnected' }
        'dialup_connect_start' { return 'dialup connect attempt' }
        'nas_no_data' { return 'NAS query returned no data' }
        'mqtt_connect_failed' { return 'vendor MQTT connect failed' }
        'mqtt_connected' { return 'vendor MQTT connected' }
        'dialup_ipv4_status' {
            $match = [regex]::Match($Message, 'ipv4Status\s*=\s*(?<state>\d+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($match.Success) { return 'ipv4Status=' + $match.Groups['state'].Value }
            return $Message
        }
        'cell_registration' {
            if ($Message -match '\bCEREG\b') { return $Message }
            if ($Message -match 'AtChooseOperatorsExecute') { return 'automatic operator selection' }
            return 'automatic network registration'
        }
        default { return $Message }
    }
}

$patterns = @(
    [pscustomobject]@{ Id = 'reboot_self_healing'; Layer = 'reboot'; Severity = 'high'; Timeline = $true; Regex = 'abnormal reboot=>\s*system self-healing' },
    [pscustomobject]@{ Id = 'reboot_webui'; Layer = 'reboot'; Severity = 'medium'; Timeline = $true; Regex = 'normal reboot=>\s*system WebUI' },
    [pscustomobject]@{ Id = 'reboot_upgrade'; Layer = 'reboot'; Severity = 'info'; Timeline = $true; Regex = 'normal reboot=>\s*system upgrade' },
    [pscustomobject]@{ Id = 'reboot_cold_start'; Layer = 'reboot'; Severity = 'info'; Timeline = $true; Regex = 'normal reboot=>\s*Cold Start Up' },
    [pscustomobject]@{ Id = 'reboot_restart_system'; Layer = 'reboot'; Severity = 'medium'; Timeline = $true; Regex = 'reboot:\s*Restarting system|stop feed watchdog' },
    [pscustomobject]@{ Id = 'scheduled_reboot'; Layer = 'reboot'; Severity = 'info'; Timeline = $true; Regex = 'Scheduled reboot config' },
    [pscustomobject]@{ Id = 'kernel_panic'; Layer = 'kernel'; Severity = 'critical'; Timeline = $true; Regex = '\bKernel panic\b|panic_on_oops|Unable to handle kernel|(?:^|\s)BUG:\s' },
    [pscustomobject]@{ Id = 'kernel_oom'; Layer = 'kernel'; Severity = 'critical'; Timeline = $true; Regex = 'Out of memory:|oom-kill|Killed process \d+' },
    [pscustomobject]@{ Id = 'cell_no_service'; Layer = 'cellular'; Severity = 'high'; Timeline = $true; Regex = 'NetServiceStateChange\].*no service' },
    [pscustomobject]@{ Id = 'cell_sysmode_noservice'; Layer = 'cellular'; Severity = 'high'; Timeline = $true; Regex = 'Hcsq.*\[sysmode\]=NOSERVICE' },
    [pscustomobject]@{ Id = 'cell_sysmode_nr'; Layer = 'cellular'; Severity = 'info'; Timeline = $true; Regex = 'Hcsq.*\[sysmode\]=NR' },
    [pscustomobject]@{ Id = 'cell_sysmode_lte'; Layer = 'cellular'; Severity = 'info'; Timeline = $true; Regex = 'Hcsq.*\[sysmode\]=LTE' },
    [pscustomobject]@{ Id = 'cell_registration'; Layer = 'cellular'; Severity = 'medium'; Timeline = $true; Regex = '\bCEREG\b|AtChooseOperatorsExecute|automatic network registration' },
    [pscustomobject]@{ Id = 'cell_signal_zero'; Layer = 'cellular'; Severity = 'high'; Timeline = $true; Regex = 'SIG=\[0\]|\bsignal\s*=\s*0\b' },
    [pscustomobject]@{ Id = 'cell_parameters'; Layer = 'cellular'; Severity = 'info'; Timeline = $true; Regex = '\b(?:EARFCN|NR-ARFCN|ARFCN|Cell ID|CellID|ECI|NCI|TAC|RSRP|RSRQ|SINR)\b|(?:MONSC|MONSSC|LCACELL|serving cell|cellinfo).*\bPCI\b' },
    [pscustomobject]@{ Id = 'dialup_disconnected'; Layer = 'dialup'; Severity = 'high'; Timeline = $true; Regex = 'DIALUP_STATE_DISCONNECTED' },
    [pscustomobject]@{ Id = 'dialup_connect_start'; Layer = 'dialup'; Severity = 'medium'; Timeline = $true; Regex = 'AtpDialupConnectStart|start connect' },
    [pscustomobject]@{ Id = 'dialup_ipv4_status'; Layer = 'dialup'; Severity = 'medium'; Timeline = $true; Regex = 'ndisstat.*ipv4Status\s*=\s*\d+' },
    [pscustomobject]@{ Id = 'nas_no_data'; Layer = 'modem'; Severity = 'high'; Timeline = $false; Regex = 'No data from NAS' },
    [pscustomobject]@{ Id = 'mqtt_connect_failed'; Layer = 'mqtt'; Severity = 'high'; Timeline = $true; Regex = 'Failed to WJMqttConnect|WJMqttConnect.*fail|wj_mqtt.*fail' },
    [pscustomobject]@{ Id = 'mqtt_connected'; Layer = 'mqtt'; Severity = 'info'; Timeline = $true; Regex = 'WJMqttConnect.*success|wj_mqtt.*connected' }
)

$compiledPatterns = foreach ($pattern in $patterns) {
    [pscustomobject]@{
        Id = $pattern.Id
        Layer = $pattern.Layer
        Severity = $pattern.Severity
        Timeline = $pattern.Timeline
        Regex = [regex]::new($pattern.Regex, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
}
$eventPrefilter = [regex]::new(
    'reboot|Scheduled|panic|oom|Out of memory|NetService|Hcsq|CEREG|ChooseOperators|network registration|SIG=|EARFCN|ARFCN|Cell.?ID|\bECI\b|\bNCI\b|\bTAC\b|RSRP|RSRQ|SINR|MONSC|MONSSC|LCACELL|DIALUP_STATE|AtpDialup|ndisstat|No data from NAS|WJMqtt|wj_mqtt',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)

$summaries = @{}
foreach ($pattern in $compiledPatterns) {
    $summaries[$pattern.Id] = [ordered]@{
        category = $pattern.Id
        layer = $pattern.Layer
        severity = $pattern.Severity
        count = 0L
        first_time = $null
        first_file = $null
        first_line = $null
        last_time = $null
        last_file = $null
        last_line = $null
        first_samples = [Collections.Generic.List[object]]::new()
        last_samples = [Collections.Generic.Queue[object]]::new()
    }
}

$timelineBuckets = @{}
$fileInventory = [Collections.Generic.List[object]]::new()
$globalFirst = $null
$globalLast = $null
$textFileCount = 0
$binaryFileCount = 0
$gzipFileCount = 0
$totalBytes = 0L
$totalLines = 0L
$sampleLimit = 3
$yearCounts = @{}

$files = Get-ChildItem -LiteralPath $mobilelog -Recurse -File | Sort-Object FullName
foreach ($file in $files) {
    $relativePath = Get-RelativePathSafe -BasePath $mobilelog -Path $file.FullName
    $totalBytes += $file.Length
    $kind = Get-LogFileKind -Path $file.FullName
    $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($kind -eq 'binary') {
        $binaryFileCount++
        $fileInventory.Add([pscustomobject]@{
            file = $relativePath
            bytes = $file.Length
            sha256 = $fileHash
            kind = $kind
            lines = $null
            first_time = $null
            last_time = $null
            scanned = $false
            scan_error = $null
        })
        continue
    }

    $textFileCount++
    if ($kind -eq 'gzip') {
        $gzipFileCount++
    }
    $lineNumber = 0L
    $fileFirst = $null
    $fileLast = $null
    $scanError = $null
    $fileStream = $null
    $contentStream = $null
    $reader = $null
    try {
        $fileStream = [IO.File]::OpenRead($file.FullName)
        $contentStream = if ($kind -eq 'gzip') {
            [IO.Compression.GZipStream]::new($fileStream, [IO.Compression.CompressionMode]::Decompress, $true)
        } else {
            $fileStream
        }
        $reader = [IO.StreamReader]::new(
            $contentStream,
            [Text.UTF8Encoding]::new($false, $false),
            $true,
            65536,
            $true
        )
        while ($null -ne ($line = $reader.ReadLine())) {
        $lineNumber++
        $timestamp = Get-LogTimestamp -Line $line
        if ($timestamp) {
            if (-not $yearCounts.ContainsKey($timestamp.Year)) { $yearCounts[$timestamp.Year] = 0L }
            $yearCounts[$timestamp.Year]++
            if (-not $fileFirst -or $timestamp -lt $fileFirst) { $fileFirst = $timestamp }
            if (-not $fileLast -or $timestamp -gt $fileLast) { $fileLast = $timestamp }
            if (-not $globalFirst -or $timestamp -lt $globalFirst) { $globalFirst = $timestamp }
            if (-not $globalLast -or $timestamp -gt $globalLast) { $globalLast = $timestamp }
        }

        $insideWindow = (-not $timestamp) -or
            ((-not $start -or $timestamp -ge $start) -and (-not $end -or $timestamp -le $end))
        if (-not $insideWindow) {
            continue
        }
        if (-not $eventPrefilter.IsMatch($line)) {
            continue
        }

        foreach ($pattern in $compiledPatterns) {
            if (-not $pattern.Regex.IsMatch($line)) {
                continue
            }

            $summary = $summaries[$pattern.Id]
            $summary.count++
            $sample = [pscustomobject]@{
                time = if ($timestamp) { $timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { 'UNDATED' }
                file = $relativePath
                line = $lineNumber
                message = Get-NormalizedMessage -Line $line
            }
            if ($summary.first_samples.Count -lt $sampleLimit) {
                $summary.first_samples.Add($sample)
            }
            $summary.last_samples.Enqueue($sample)
            while ($summary.last_samples.Count -gt $sampleLimit) {
                $null = $summary.last_samples.Dequeue()
            }

            if ($timestamp) {
                if (-not $summary.first_time -or $timestamp -lt $summary.first_time) {
                    $summary.first_time = $timestamp
                    $summary.first_file = $relativePath
                    $summary.first_line = $lineNumber
                }
                if (-not $summary.last_time -or $timestamp -gt $summary.last_time) {
                    $summary.last_time = $timestamp
                    $summary.last_file = $relativePath
                    $summary.last_line = $lineNumber
                }
            } elseif (-not $summary.first_file) {
                $summary.first_file = $relativePath
                $summary.first_line = $lineNumber
                $summary.last_file = $relativePath
                $summary.last_line = $lineNumber
            }

            if ($pattern.Timeline) {
                $message = Get-TimelineState -Category $pattern.Id -Message $sample.message
                $bucketTime = if ($timestamp) { $timestamp.ToString('yyyy-MM-dd HH:mm') } else { 'UNDATED' }
                $key = '{0}|{1}|{2}' -f $bucketTime, $pattern.Id, $message
                if (-not $timelineBuckets.ContainsKey($key)) {
                    $timelineBuckets[$key] = [ordered]@{
                        sort_time = $timestamp
                        time = $bucketTime
                        category = $pattern.Id
                        layer = $pattern.Layer
                        severity = $pattern.Severity
                        count = 0L
                        file = $relativePath
                        line = $lineNumber
                        message = $message
                    }
                }
                $timelineBuckets[$key].count++
            }
        }
        }
    } catch {
        $scanError = Protect-LogText -Text $_.Exception.Message
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($kind -eq 'gzip' -and $contentStream) { $contentStream.Dispose() }
        if ($fileStream) { $fileStream.Dispose() }
    }
    $totalLines += $lineNumber
    $fileInventory.Add([pscustomobject]@{
        file = $relativePath
        bytes = $file.Length
        sha256 = $fileHash
        kind = $kind
        lines = $lineNumber
        first_time = if ($fileFirst) { $fileFirst.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { $null }
        last_time = if ($fileLast) { $fileLast.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { $null }
        scanned = $true
        scan_error = $scanError
    })
}

$summaryRows = foreach ($pattern in $compiledPatterns) {
    $summary = $summaries[$pattern.Id]
    [pscustomobject]@{
        category = $summary.category
        layer = $summary.layer
        severity = $summary.severity
        count = $summary.count
        first_time = if ($summary.first_time) { $summary.first_time.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { $null }
        first_location = if ($summary.first_file) { '{0}:{1}' -f $summary.first_file, $summary.first_line } else { $null }
        last_time = if ($summary.last_time) { $summary.last_time.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { $null }
        last_location = if ($summary.last_file) { '{0}:{1}' -f $summary.last_file, $summary.last_line } else { $null }
    }
}

$timelineRows = @($timelineBuckets.Values | Sort-Object @{
    Expression = {
        if ($_.sort_time) { $_.sort_time } else { [datetime]::MinValue }
    }
}, category, message)
$timelineTruncated = $false
if ($timelineRows.Count -gt $MaxTimelineRows) {
    $timelineTruncated = $true
    $priorityRows = @($timelineRows | Where-Object severity -in @('critical', 'high'))
    $normalRows = @($timelineRows | Where-Object severity -notin @('critical', 'high'))
    $sampledRows = [Collections.Generic.List[object]]::new()
    if ($priorityRows.Count -ge $MaxTimelineRows) {
        $step = [Math]::Ceiling($priorityRows.Count / [double]$MaxTimelineRows)
        for ($index = 0; $index -lt $priorityRows.Count; $index += $step) {
            $sampledRows.Add($priorityRows[$index])
        }
    } else {
        foreach ($row in $priorityRows) {
            $sampledRows.Add($row)
        }
        $remaining = $MaxTimelineRows - $priorityRows.Count
        if ($remaining -gt 0 -and $normalRows.Count -gt 0) {
            $step = [Math]::Max(1, [Math]::Ceiling($normalRows.Count / [double]$remaining))
            for ($index = 0; $index -lt $normalRows.Count; $index += $step) {
                $sampledRows.Add($normalRows[$index])
            }
        }
    }
    $timelineRows = @($sampledRows | Sort-Object @{
        Expression = {
            if ($_.sort_time) { $_.sort_time } else { [datetime]::MinValue }
        }
    }, category, message | Select-Object -First $MaxTimelineRows)
}

$fileInventory | Export-Csv -LiteralPath (Join-Path $OutDir '01-file-inventory.csv') -NoTypeInformation -Encoding utf8
$summaryRows | Export-Csv -LiteralPath (Join-Path $OutDir '02-event-summary.csv') -NoTypeInformation -Encoding utf8

$timelinePath = Join-Path $OutDir '03-timeline.tsv'
"time`tcategory`tlayer`tseverity`tcount`tlocation`tmessage" | Set-Content -LiteralPath $timelinePath -Encoding utf8
foreach ($row in $timelineRows) {
    $fields = @(
        $row.time,
        $row.category,
        $row.layer,
        $row.severity,
        $row.count,
        ('{0}:{1}' -f $row.file, $row.line),
        ($row.message -replace "`t", ' ')
    )
    ($fields -join "`t") | Add-Content -LiteralPath $timelinePath -Encoding utf8
}

$evidence = [Text.StringBuilder]::new()
$null = $evidence.AppendLine('# Representative evidence')
$null = $evidence.AppendLine()
$null = $evidence.AppendLine('Evidence is redacted. Use each `file:line` location to inspect the original log only when needed.')
$null = $evidence.AppendLine()
foreach ($pattern in $compiledPatterns) {
    $summary = $summaries[$pattern.Id]
    if ($summary.count -eq 0) {
        continue
    }
    $null = $evidence.AppendLine(('## {0} ({1})' -f $pattern.Id, $summary.count))
    $seen = [Collections.Generic.HashSet[string]]::new()
    $samples = @($summary.first_samples) + @($summary.last_samples.ToArray())
    foreach ($sample in $samples) {
        $identity = '{0}:{1}:{2}' -f $sample.file, $sample.line, $sample.message
        if (-not $seen.Add($identity)) {
            continue
        }
        $null = $evidence.AppendLine(('- `{0}` `{1}:{2}` {3}' -f $sample.time, $sample.file, $sample.line, $sample.message))
    }
    $null = $evidence.AppendLine()
}
[IO.File]::WriteAllText((Join-Path $OutDir '04-evidence.md'), $evidence.ToString(), [Text.UTF8Encoding]::new($false))

$severityRank = @{ critical = 4; high = 3; medium = 2; info = 1 }
$notable = @($summaryRows | Where-Object count -gt 0 | Sort-Object @{ Expression = { $severityRank[$_.severity] }; Descending = $true }, @{ Expression = 'count'; Descending = $true })
$overview = [Text.StringBuilder]::new()
$null = $overview.AppendLine('# MAX3 log index')
$null = $overview.AppendLine()
$null = $overview.AppendLine(('- Source: `{0}`' -f $mobilelog))
$null = $overview.AppendLine(('- Files: {0} ({1} readable, including {2} gzip; {3} skipped as binary)' -f $files.Count, $textFileCount, $gzipFileCount, $binaryFileCount))
$null = $overview.AppendLine(('- Bytes: {0:N0}' -f $totalBytes))
$null = $overview.AppendLine(('- Scanned lines: {0:N0}' -f $totalLines))
$null = $overview.AppendLine(('- Parsed time range: `{0}` to `{1}`' -f (
    $(if ($globalFirst) { $globalFirst.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { 'unknown' })
), (
    $(if ($globalLast) { $globalLast.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { 'unknown' })
)))
$null = $overview.AppendLine(('- Event filter: `{0}` to `{1}`; undated pstore/kernel evidence remains included.' -f (
    $(if ($start) { $start.ToString('yyyy-MM-dd HH:mm:ss') } else { 'unbounded' })
), (
    $(if ($end) { $end.ToString('yyyy-MM-dd HH:mm:ss') } else { 'unbounded' })
)))
$null = $overview.AppendLine(('- Timeline rows: {0}{1}' -f $timelineRows.Count, $(if ($timelineTruncated) { ' (sampled because the limit was reached)' } else { '' })))
$null = $overview.AppendLine(('- Timestamp years: {0}' -f (($yearCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { '{0}={1:N0}' -f $_.Name, $_.Value }) -join ', ')))
$null = $overview.AppendLine()
$null = $overview.AppendLine('## AI reading order')
$null = $overview.AppendLine()
$null = $overview.AppendLine('1. Read this file and `02-event-summary.csv`.')
$null = $overview.AppendLine('2. Read `03-timeline.tsv` around the reported incident time.')
$null = $overview.AppendLine('3. Read `04-evidence.md` for first/last representative records.')
$null = $overview.AppendLine('4. Use `file:line` locations to retrieve narrow context from original logs.')
$null = $overview.AppendLine('5. Read raw files in full only when the index indicates missing evidence or an unknown format.')
$null = $overview.AppendLine()
$null = $overview.AppendLine('## Non-zero event categories')
$null = $overview.AppendLine()
$null = $overview.AppendLine('| Category | Layer | Severity | Count | First | Last |')
$null = $overview.AppendLine('|---|---|---:|---:|---|---|')
foreach ($row in $notable) {
    $null = $overview.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $row.category, $row.layer, $row.severity, $row.count, $row.first_time, $row.last_time))
}
$null = $overview.AppendLine()
$null = $overview.AppendLine('## Interpretation boundaries')
$null = $overview.AppendLine()
$null = $overview.AppendLine('- Counts show repeated log records, not necessarily the same number of user-visible outages.')
$null = $overview.AppendLine('- Rotated/current files may overlap, so counts are physical matching records rather than de-duplicated incidents.')
$null = $overview.AppendLine('- `2022-08-01` is a common uncalibrated device clock in these packages; keep it separate from confirmed wall-clock time.')
$null = $overview.AppendLine('- `sysmode` or signal changes alone do not prove a base-station change.')
$null = $overview.AppendLine('- Undated pstore records can confirm reboot mechanisms but not their wall-clock time.')
$null = $overview.AppendLine('- `wj_mqtt` is the vendor channel and is not automatically the user MQTT platform.')
$null = $overview.AppendLine('- The index redacts identifiers and IP addresses; original logs remain unchanged.')
[IO.File]::WriteAllText((Join-Path $OutDir '00-AI-READ-ME.md'), $overview.ToString(), [Text.UTF8Encoding]::new($false))

$manifest = [ordered]@{
    schema_version = 1
    generated_at = [datetime]::UtcNow.ToString('o')
    source = $mobilelog
    output = $OutDir
    files = $files.Count
    text_files_scanned = $textFileCount
    gzip_files_scanned = $gzipFileCount
    binary_files_skipped = $binaryFileCount
    total_bytes = $totalBytes
    scanned_lines = $totalLines
    parsed_first_time = if ($globalFirst) { $globalFirst.ToString('o') } else { $null }
    parsed_last_time = if ($globalLast) { $globalLast.ToString('o') } else { $null }
    filter_start = if ($start) { $start.ToString('o') } else { $null }
    filter_end = if ($end) { $end.ToString('o') } else { $null }
    timeline_rows = $timelineRows.Count
    timeline_truncated = $timelineTruncated
    events = @($summaryRows)
}
$fingerprintSource = ($fileInventory | Sort-Object file | ForEach-Object { '{0}:{1}' -f $_.file, $_.sha256 }) -join "`n"
$manifest.input_fingerprint_sha256 = Get-StringSha256 -Value $fingerprintSource
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'manifest.json') -Encoding utf8

Write-Host ''
Write-Host 'AI log index complete.' -ForegroundColor Green
Write-Host "Read first: $OutDir\00-AI-READ-ME.md" -ForegroundColor Yellow
return $OutDir
