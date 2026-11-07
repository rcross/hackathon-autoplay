# ---------------------------------------------------------------------------
# Hackathon video autoplay - preparation script
#
# 1. Downloads the form responses (Google Sheet) as CSV
# 2. Splits submissions into 2 playlists, grouped by task
#    (all Machine Learning tasks go in the same playlist)
# 3. Downloads every 45-second video into .\videos so playback has no delays
# 4. Writes playlists.js (read by player.html) and running-order.txt
#
# Safe to re-run at any time: videos already downloaded are skipped, so a
# re-run only fetches new / changed submissions.
#
# Run it by double-clicking prepare.bat (no installation needed).
# ---------------------------------------------------------------------------

param(
    [string]$CsvPath = ""   # optional: use this CSV instead of downloading the sheet
)

# ============================ SETTINGS =====================================

$SheetId  = "1TuKzcx9GDQsScX8izS0m_QAssY0nIFnrsKUOXsBLABI"
$SheetGid = "1733447410"

# A task whose name matches this pattern is a "Machine Learning" task.
# All ML tasks are kept together in Playlist 1.
$MlTaskPattern = 'machine\s*learning|\bML\b'

# Force a task into a particular playlist (1 or 2). Overrides the automatic
# split. Use the task text exactly as it appears in the sheet, e.g.
#   $PlaylistOverride = @{ "Social post (make a video)" = 2 }
$PlaylistOverride = @{ }

# Team names matching this pattern are ignored (test submissions).
$IgnoreTeamPattern = '^\s*(dummy|test)\d*\s*$'

# ===========================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # makes Invoke-WebRequest much faster
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }
# Windows PowerShell 5.1 otherwise sometimes writes arrays as {"value":[...],"Count":n}
Remove-TypeData System.Array -ErrorAction SilentlyContinue

$Root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$VideoDir  = Join-Path $Root "videos"
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
if (-not (Test-Path $VideoDir)) { New-Item -ItemType Directory -Path $VideoDir | Out-Null }

function Write-Step($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   OK   $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "   WARN $msg" -ForegroundColor Yellow }
function Write-Bad($msg)  { Write-Host "   FAIL $msg" -ForegroundColor Red }

function Test-LooksLikeHtml([string]$path) {
    $bytes = New-Object byte[] 64
    $fs = [IO.File]::OpenRead($path)
    try { $n = $fs.Read($bytes, 0, 64) } finally { $fs.Close() }
    $text = [Text.Encoding]::ASCII.GetString($bytes, 0, $n).TrimStart()
    return ($text.StartsWith("<") -or $text.StartsWith("{"))
}

# Returns "mp4", "webm" or $null (not a recognisable video)
function Get-VideoKind([string]$path) {
    $bytes = New-Object byte[] 16
    $fs = [IO.File]::OpenRead($path)
    try { $n = $fs.Read($bytes, 0, 16) } finally { $fs.Close() }
    if ($n -lt 12) { return $null }
    if ($bytes[0] -eq 0x1A -and $bytes[1] -eq 0x45 -and $bytes[2] -eq 0xDF -and $bytes[3] -eq 0xA3) { return "webm" }
    $box = [Text.Encoding]::ASCII.GetString($bytes, 4, 4)
    if (@("ftyp", "moov", "mdat", "free", "wide", "skip") -contains $box) { return "mp4" }
    return $null
}

function Get-ShortHash([string]$text) {
    $sha = [Security.Cryptography.SHA1]::Create()
    $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
    return (($hash[0..3] | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-Slug([string]$text) {
    $s = ($text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).Trim('-') }
    if (-not $s) { $s = "team" }
    return $s
}

# Turn a "share" link into a direct-download link where we know how.
# Returns @{ Download = <url or $null>; YouTube = <id or $null> }
function Resolve-VideoUrl([string]$url) {
    $u = $url.Trim()
    $r = @{ Download = $u; YouTube = $null }

    # YouTube - cannot be downloaded without extra tools; the player embeds it instead
    if ($u -match '(?:youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|embed/|live/)|youtu\.be/)([A-Za-z0-9_-]{6,})') {
        $r.Download = $null; $r.YouTube = $Matches[1]; return $r
    }
    # GitHub "blob" page -> raw file
    if ($u -match '^https?://(www\.)?github\.com/([^/]+)/([^/]+)/blob/(.+)$') {
        $path = $Matches[4] -replace '\?.*$', ''
        $r.Download = "https://github.com/$($Matches[2])/$($Matches[3])/raw/$path"; return $r
    }
    # Google Drive file
    if ($u -match 'drive\.google\.com/file/d/([A-Za-z0-9_-]+)' -or
        $u -match 'drive\.google\.com/(?:open|uc)\?(?:.*&)?id=([A-Za-z0-9_-]+)' -or
        $u -match 'drive\.usercontent\.google\.com/.*[?&]id=([A-Za-z0-9_-]+)') {
        $r.Download = "https://drive.usercontent.google.com/download?id=$($Matches[1])&export=download&confirm=t"; return $r
    }
    # Dropbox
    if ($u -match 'dropbox\.com') {
        if ($u -match '[?&]dl=0') { $r.Download = $u -replace 'dl=0', 'dl=1' }
        elseif ($u -notmatch '[?&]dl=1') { $r.Download = $u + $(if ($u.Contains("?")) { "&dl=1" } else { "?dl=1" }) }
        return $r
    }
    # OneDrive / SharePoint
    if ($u -match 'sharepoint\.com|1drv\.ms|onedrive\.live\.com') {
        if ($u -notmatch '[?&]download=1') { $r.Download = $u + $(if ($u.Contains("?")) { "&download=1" } else { "?download=1" }) }
        return $r
    }
    return $r
}

function Find-Column($row, [string]$pattern) {
    foreach ($p in $row.PSObject.Properties) { if ($p.Name -match $pattern) { return $p.Name } }
    return $null
}

# ---------------------------------------------------------------------------
Write-Step "Getting form responses"

$LocalCsv = Join-Path $Root "responses.csv"
if ($CsvPath) {
    $LocalCsv = (Resolve-Path $CsvPath).Path
    Write-Ok "Using $LocalCsv"
} else {
    $csvUrl = "https://docs.google.com/spreadsheets/d/$SheetId/export?format=csv&gid=$SheetGid"
    $tmp = Join-Path $Root "responses.download.tmp"
    $downloaded = $false
    try {
        Invoke-WebRequest -Uri $csvUrl -OutFile $tmp -UseBasicParsing -UserAgent $UserAgent -TimeoutSec 60
        if (Test-LooksLikeHtml $tmp) { throw "Google returned a sign-in page instead of the CSV" }
        Move-Item -Force $tmp $LocalCsv
        $downloaded = $true
        Write-Ok "Downloaded latest responses from Google Sheets"
    } catch {
        if (Test-Path $tmp) { Remove-Item -Force $tmp }
        Write-Warn2 "Could not download the sheet automatically ($($_.Exception.Message))."
    }
    if (-not $downloaded) {
        if (Test-Path $LocalCsv) {
            Write-Warn2 "Using the existing responses.csv (last changed $((Get-Item $LocalCsv).LastWriteTime))."
        } else {
            Write-Bad "No responses.csv found."
            Write-Host ""
            Write-Host "   Either: open the sheet, File > Download > Comma-separated values (.csv)," -ForegroundColor Yellow
            Write-Host "           and save it as responses.csv in this folder, then run again." -ForegroundColor Yellow
            Write-Host "   Or:     share the sheet as 'Anyone with the link - Viewer'." -ForegroundColor Yellow
            exit 1
        }
    }
}

$rows = @(Import-Csv -Path $LocalCsv -Encoding UTF8)
if ($rows.Count -eq 0) { Write-Bad "The CSV has no submissions."; exit 1 }

$colTime = Find-Column $rows[0] '^Timestamp'
$colTeam = Find-Column $rows[0] '^Team name'
$colTask = Find-Column $rows[0] 'task'
$colVid  = Find-Column $rows[0] '45 second'
if (-not ($colTeam -and $colTask -and $colVid)) {
    Write-Bad "Could not find the Team name / task / 45 second video columns in the CSV."; exit 1
}

# Keep only the latest submission per team (people often resubmit to fix a link)
$byTeam = [ordered]@{}
$index = 0
foreach ($row in $rows) {
    $index++
    $team = ("" + $row.$colTeam).Trim()
    if (-not $team) { continue }
    if ($team -match $IgnoreTeamPattern) { Write-Warn2 "Ignoring test submission '$team'"; continue }
    $key = $team.ToLowerInvariant()
    if ($byTeam.Contains($key)) { Write-Warn2 "'$team' submitted more than once - using the latest submission"; $byTeam.Remove($key) }
    $byTeam[$key] = [pscustomobject]@{
        Order = $index
        Team  = $team
        Task  = ("" + $row.$colTask).Trim()
        Url   = ("" + $row.$colVid).Trim()
    }
}
$subs = @($byTeam.Values)
Write-Ok "$($subs.Count) team submission(s)"
if ($subs.Count -eq 0) { Write-Bad "Nothing to play."; exit 1 }

# ---------------------------------------------------------------------------
Write-Step "Splitting into 2 playlists"

$groups = @($subs | Group-Object Task | Sort-Object Name)
$assign = @{}
foreach ($g in $groups) {
    if ($PlaylistOverride.ContainsKey($g.Name)) { $assign[$g.Name] = [int]$PlaylistOverride[$g.Name] }
    elseif ($g.Name -match $MlTaskPattern)    { $assign[$g.Name] = 1 }
    else                                      { $assign[$g.Name] = 2 }
}
function Get-Count($n) { $c = 0; foreach ($g in $groups) { if ($assign[$g.Name] -eq $n) { $c += $g.Count } }; return $c }

# Balance: move whole non-ML task groups between playlists while it makes the
# two playlists closer in size. ML tasks and overridden tasks never move.
while ($true) {
    $c1 = Get-Count 1; $c2 = Get-Count 2
    $diff = [Math]::Abs($c1 - $c2)
    $from = $(if ($c1 -gt $c2) { 1 } else { 2 })
    $best = $null; $bestDiff = $diff
    foreach ($g in $groups) {
        if ($assign[$g.Name] -ne $from) { continue }
        if ($g.Name -match $MlTaskPattern -or $PlaylistOverride.ContainsKey($g.Name)) { continue }
        $newDiff = [Math]::Abs($diff - 2 * $g.Count)
        if ($newDiff -lt $bestDiff) { $best = $g; $bestDiff = $newDiff }
    }
    if (-not $best) { break }
    $assign[$best.Name] = 3 - $from
}

foreach ($g in $groups) {
    $ml = $(if ($g.Name -match $MlTaskPattern) { " [ML]" } else { "" })
    Write-Host ("   Playlist {0}: {1,3} x {2}{3}" -f $assign[$g.Name], $g.Count, $g.Name, $ml)
}
Write-Ok ("Playlist 1: {0} videos   Playlist 2: {1} videos" -f (Get-Count 1), (Get-Count 2))
if (-not ($groups | Where-Object { $_.Name -match $MlTaskPattern })) {
    Write-Warn2 "No task name matched the Machine Learning pattern - check `$MlTaskPattern at the top of prepare.ps1"
}

# ---------------------------------------------------------------------------
Write-Step "Downloading videos (already-downloaded videos are skipped)"

$problems = @()
$items = @{}
foreach ($s in ($subs | Sort-Object Order)) {
    $entry = [ordered]@{ team = $s.Team; task = $s.Task; url = $s.Url; file = $null; youtube = $null; error = $null }
    if (-not $s.Url) {
        $entry.error = "No video URL submitted"
    } else {
        $res = Resolve-VideoUrl $s.Url
        if ($res.YouTube) {
            $entry.youtube = $res.YouTube
            Write-Warn2 "$($s.Team): YouTube link - will stream it (needs internet during judging)"
            $problems += "$($s.Team): YouTube link, streamed live (not pre-downloaded) - $($s.Url)"
        } else {
            $base = "$(Get-Slug $s.Team)-$(Get-ShortHash $s.Url)"
            $existing = @(Get-ChildItem -Path $VideoDir -Filter "$base.*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne ".part" -and $_.Length -gt 0 })
            if ($existing.Count -gt 0) {
                $entry.file = "videos/" + $existing[0].Name
                Write-Host "   skip $($s.Team) (already downloaded)"
            } else {
                $part = Join-Path $VideoDir "$base.part"
                try {
                    Write-Host "   get  $($s.Team) ..." -NoNewline
                    Invoke-WebRequest -Uri $res.Download -OutFile $part -UseBasicParsing -UserAgent $UserAgent -TimeoutSec 900 -MaximumRedirection 10
                    $kind = Get-VideoKind $part
                    if (-not $kind) {
                        if (Test-LooksLikeHtml $part) { throw "the link returned a web page, not a video file (is it public? is it a direct link?)" }
                        throw "the downloaded file is not an mp4/webm video"
                    }
                    $final = Join-Path $VideoDir "$base.$kind"
                    Move-Item -Force $part $final
                    $entry.file = "videos/$base.$kind"
                    $mb = [Math]::Round((Get-Item $final).Length / 1MB, 1)
                    Write-Host " $mb MB" -ForegroundColor Green
                } catch {
                    Write-Host ""
                    if (Test-Path $part) { Remove-Item -Force $part }
                    $entry.error = $_.Exception.Message
                }
            }
        }
    }
    if ($entry.error) {
        Write-Bad "$($s.Team): $($entry.error)"
        $problems += "$($s.Team): $($entry.error) - $($s.Url)"
    }
    $items[$s.Team.ToLowerInvariant()] = $entry
}

# ---------------------------------------------------------------------------
Write-Step "Writing playlists.js and running-order.txt"

$playlists = @()
$orderLines = @()
foreach ($n in 1, 2) {
    $list = @()
    foreach ($g in $groups) {
        if ($assign[$g.Name] -ne $n) { continue }
        foreach ($s in ($g.Group | Sort-Object Order)) { $list += $items[$s.Team.ToLowerInvariant()] }
    }
    $tasks = @($groups | Where-Object { $assign[$_.Name] -eq $n } | ForEach-Object { $_.Name })
    $playlists += [ordered]@{ name = "Playlist $n"; tasks = $tasks; items = $list }

    $orderLines += "PLAYLIST $n  ($($list.Count) videos)"
    $orderLines += ("-" * 60)
    $i = 0; $lastTask = $null
    foreach ($e in $list) {
        $i++
        if ($e.task -ne $lastTask) { $orderLines += ""; $orderLines += "  $($e.task)"; $lastTask = $e.task }
        $flag = $(if ($e.error) { "   <-- PROBLEM: $($e.error)" } elseif ($e.youtube) { "   (YouTube, streamed)" } else { "" })
        $orderLines += ("  {0,3}. {1}{2}" -f $i, $e.team, $flag)
    }
    $orderLines += ""; $orderLines += ""
}

$data = [ordered]@{ generated = (Get-Date).ToString("yyyy-MM-dd HH:mm"); playlists = $playlists }
$json = ConvertTo-Json -InputObject $data -Depth 8
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Root "playlists.js"), "window.PLAYLIST_DATA = $json;`r`n", $utf8)
[IO.File]::WriteAllText((Join-Path $Root "running-order.txt"), ($orderLines -join "`r`n"), $utf8)
Write-Ok "playlists.js"
Write-Ok "running-order.txt"

Write-Step "Summary"
if ($problems.Count -gt 0) {
    Write-Host "   $($problems.Count) submission(s) need attention (also listed in running-order.txt):" -ForegroundColor Yellow
    foreach ($p in $problems) { Write-Host "    - $p" -ForegroundColor Yellow }
} else {
    Write-Ok "All videos downloaded."
}
Write-Host ""
Write-Host "   Now open player.html in Chrome or Edge." -ForegroundColor Cyan
Write-Host ""
