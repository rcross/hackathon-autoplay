# ---------------------------------------------------------------------------
# Hackathon video autoplay - preparation script
#
# 1. Downloads the form responses (Google Sheet) as CSV
# 2. Splits submissions into 2 playlists, grouped by task
#    (all Machine Learning tasks go in the same playlist)
# 3. Checks every video link: is it public, is it really a video, and can a
#    browser pre-download it (or will it have to stream it live)?
# 4. Writes one self-contained page per playlist into output\<date-time>\
#      playlist-1.html, playlist-2.html, running-order.txt
#
# Each playlist page can be copied to any computer. When opened, it downloads
# only the videos for that playlist. No videos are downloaded by this script.
#
# Run it by double-clicking prepare.bat (no installation needed).
# ---------------------------------------------------------------------------

param(
    [string]$CsvPath = "",    # optional: use this CSV instead of downloading the sheet
    [switch]$SkipCheck        # optional: don't check the video links
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
$ProgressPreference    = "SilentlyContinue"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }
# Windows PowerShell 5.1 otherwise sometimes writes arrays as {"value":[...],"Count":n}
Remove-TypeData System.Array -ErrorAction SilentlyContinue

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Template  = Join-Path $Root "player-template.html"
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

function Write-Step($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   OK     $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "   WARN   $msg" -ForegroundColor Yellow }
function Write-Bad($msg)  { Write-Host "   FAIL   $msg" -ForegroundColor Red }

if (-not (Test-Path $Template)) { Write-Bad "player-template.html is missing - keep it next to this script."; exit 1 }

function Test-LooksLikeHtml([string]$path) {
    $bytes = New-Object byte[] 64
    $fs = [IO.File]::OpenRead($path)
    try { $n = $fs.Read($bytes, 0, 64) } finally { $fs.Close() }
    $text = [Text.Encoding]::ASCII.GetString($bytes, 0, $n).TrimStart()
    return ($text.StartsWith("<") -or $text.StartsWith("{"))
}

# Returns "mp4", "webm", "html" or $null for the first bytes of a file
function Get-ContentKind([byte[]]$bytes, [int]$n) {
    if ($n -ge 4 -and $bytes[0] -eq 0x1A -and $bytes[1] -eq 0x45 -and $bytes[2] -eq 0xDF -and $bytes[3] -eq 0xA3) { return "webm" }
    if ($n -ge 8) {
        $box = [Text.Encoding]::ASCII.GetString($bytes, 4, 4)
        if (@("ftyp", "moov", "mdat", "free", "wide", "skip") -contains $box) { return "mp4" }
    }
    $text = [Text.Encoding]::ASCII.GetString($bytes, 0, $n).TrimStart()
    if ($text.StartsWith("<") -or $text.StartsWith("{") -or $text.StartsWith("version https://git-lfs")) { return "html" }
    return $null
}

# Turn a "share" link into a direct-download link where we know how.
# Returns @{ Download = <url or $null>; YouTube = <id or $null> }
function Resolve-VideoUrl([string]$url) {
    $u = $url.Trim()
    $r = @{ Download = $u; YouTube = $null }

    # YouTube - cannot be downloaded; the player embeds it instead
    if ($u -match '(?:youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|embed/|live/)|youtu\.be/)([A-Za-z0-9_-]{6,})') {
        $r.Download = $null; $r.YouTube = $Matches[1]; return $r
    }
    # GitHub "blob" or "raw" page -> raw.githubusercontent.com (allows browser downloads)
    if ($u -match '^https?://(?:www\.)?github\.com/([^/]+)/([^/]+)/(?:blob|raw)/([^?#]+)') {
        $r.Download = "https://raw.githubusercontent.com/$($Matches[1])/$($Matches[2])/$($Matches[3])"; return $r
    }
    # Google Drive file
    if ($u -match 'drive\.google\.com/file/d/([A-Za-z0-9_-]+)' -or
        $u -match 'drive\.google\.com/(?:open|uc)\?(?:.*&)?id=([A-Za-z0-9_-]+)' -or
        $u -match 'drive\.usercontent\.google\.com/.*[?&]id=([A-Za-z0-9_-]+)') {
        $r.Download = "https://drive.usercontent.google.com/download?id=$($Matches[1])&export=download&confirm=t"; return $r
    }
    # Dropbox -> dl.dropboxusercontent.com (allows browser downloads)
    if ($u -match '^https?://(?:www\.)?dropbox\.com/(.+)$') {
        $rest = $Matches[1] -replace '([?&])dl=[01]&?', '$1' -replace '[?&]$', ''
        $r.Download = "https://dl.dropboxusercontent.com/$rest"; return $r
    }
    # OneDrive / SharePoint
    if ($u -match 'sharepoint\.com|1drv\.ms|onedrive\.live\.com') {
        if ($u -notmatch '[?&]download=1') { $r.Download = $u + $(if ($u.Contains("?")) { "&download=1" } else { "?download=1" }) }
        return $r
    }
    return $r
}

# Fetches only the first few bytes of a video link, the way a browser would.
# Returns @{ Status = ok|stream|fail; Message; SizeMB }
#   ok     - public video, and the host lets the player page pre-download it
#   stream - public video, but the host blocks pre-downloading: the page will
#            stream it live during judging (needs internet, may buffer)
#   fail   - not reachable / not public / not a video
function Test-VideoLink([string]$url) {
    $resp = $null
    try {
        $req = [Net.HttpWebRequest]::Create($url)
        $req.Method = "GET"
        $req.UserAgent = $UserAgent
        $req.AllowAutoRedirect = $true
        $req.MaximumAutomaticRedirections = 10
        $req.Timeout = 30000
        $req.ReadWriteTimeout = 30000
        $req.AddRange(0, 63)
        $req.Headers.Add("Origin", "null")   # what a page opened from disk sends
        $resp = $req.GetResponse()

        $buf = New-Object byte[] 64
        $stream = $resp.GetResponseStream()
        $n = 0
        while ($n -lt 64) { $got = $stream.Read($buf, $n, 64 - $n); if ($got -le 0) { break }; $n += $got }

        $size = $null
        $cr = $resp.Headers["Content-Range"]
        if ($cr -and $cr -match '/(\d+)$') { $size = [double]$Matches[1] }
        elseif ([int]$resp.StatusCode -eq 200 -and $resp.ContentLength -gt 0) { $size = [double]$resp.ContentLength }
        $sizeMB = $(if ($size) { [Math]::Round($size / 1MB, 1) } else { $null })

        $kind = Get-ContentKind $buf $n
        if ($kind -eq "html") { return @{ Status = "fail"; Message = "link opens a web page / sign-in page, not a video file (not public, or not a direct link)"; SizeMB = $null } }
        if (-not $kind) {
            $ct = "" + $resp.ContentType
            if ($ct -notmatch '^video/') { return @{ Status = "fail"; Message = "link does not return an mp4/webm video (got '$ct')"; SizeMB = $null } }
        }

        $acao = "" + $resp.Headers["Access-Control-Allow-Origin"]
        if ($acao -eq "*" -or $acao -eq "null") { return @{ Status = "ok"; Message = ""; SizeMB = $sizeMB } }
        return @{ Status = "stream"; Message = "host blocks pre-downloading - will stream live (needs internet)"; SizeMB = $sizeMB }
    } catch {
        $msg = $_.Exception.Message
        if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
        if ($msg -match '\((\d{3})\)\s*([^.]*)') { $msg = "HTTP $($Matches[1]) $($Matches[2])".Trim() }
        if ($msg -match '40[13]') { $msg += " - the video is not public" }
        return @{ Status = "fail"; Message = $msg; SizeMB = $null }
    } finally {
        if ($resp) { $resp.Close() }
    }
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
if ($SkipCheck) { Write-Step "Skipping video link checks (-SkipCheck)" }
else { Write-Step "Checking every video link (only the first few bytes are fetched)" }

$items = @{}
$counts = @{ ok = 0; stream = 0; fail = 0; youtube = 0; unchecked = 0 }
foreach ($s in ($subs | Sort-Object Order)) {
    $entry = [ordered]@{ team = $s.Team; task = $s.Task; url = $s.Url; src = $null; youtube = $null; check = "unchecked"; problem = $null; sizeMB = $null }
    if (-not $s.Url) {
        $entry.check = "fail"; $entry.problem = "no video link submitted"
    } else {
        $res = Resolve-VideoUrl $s.Url
        if ($res.YouTube) {
            $entry.youtube = $res.YouTube; $entry.check = "youtube"
            $entry.problem = "YouTube link - can't be pre-downloaded, will stream live (needs internet)"
        } else {
            $entry.src = $res.Download
            if (-not $SkipCheck) {
                $t = Test-VideoLink $res.Download
                $entry.check = $t.Status; $entry.sizeMB = $t.SizeMB
                if ($t.Message) { $entry.problem = $t.Message }
            }
        }
    }
    $counts[$entry.check]++
    $label = "{0}  [{1}]" -f $s.Team, $s.Task
    switch ($entry.check) {
        "ok"        { Write-Ok ("{0}{1}" -f $label, $(if ($entry.sizeMB) { "  $($entry.sizeMB) MB" } else { "" })) }
        "unchecked" { Write-Host "   -      $label" }
        "fail"      { Write-Bad ("$label`n            $($entry.problem)" + $(if ($s.Url) { "`n            $($s.Url)" } else { "" })) }
        default     { Write-Warn2 "$label`n            $($entry.problem)" }
    }
    $items[$s.Team.ToLowerInvariant()] = $entry
}

# ---------------------------------------------------------------------------
$stamp  = Get-Date -Format "yyyy-MM-dd_HHmm"
$OutDir = Join-Path $Root "output\$stamp"
$n = 1
while (Test-Path $OutDir) { $n++; $OutDir = Join-Path $Root "output\$stamp-$n" }
New-Item -ItemType Directory -Path $OutDir | Out-Null

Write-Step "Writing playlist pages"

$utf8 = New-Object Text.UTF8Encoding($false)
$templateHtml = [IO.File]::ReadAllText($Template, $utf8)
$orderLines = @("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "")
$generated = (Get-Date).ToString("yyyy-MM-dd HH:mm")

foreach ($p in 1, 2) {
    $list = @()
    foreach ($g in $groups) {
        if ($assign[$g.Name] -ne $p) { continue }
        foreach ($s in ($g.Group | Sort-Object Order)) { $list += $items[$s.Team.ToLowerInvariant()] }
    }
    $tasks = @($groups | Where-Object { $assign[$_.Name] -eq $p } | ForEach-Object { $_.Name })
    $data = [ordered]@{ name = "Playlist $p"; generated = $generated; tasks = $tasks; items = $list }
    $json = (ConvertTo-Json -InputObject $data -Depth 8) -replace '</', '<\/'

    $html = $templateHtml.Replace("/*__PLAYLIST_DATA__*/null", $json).Replace("__PLAYLIST_TITLE__", "Playlist $p")
    $file = Join-Path $OutDir "playlist-$p.html"
    [IO.File]::WriteAllText($file, $html, $utf8)
    Write-Ok "playlist-$p.html  ($($list.Count) videos)"

    $orderLines += "PLAYLIST $p  ($($list.Count) videos)"
    $orderLines += ("-" * 60)
    $i = 0; $lastTask = $null
    foreach ($e in $list) {
        $i++
        if ($e.task -ne $lastTask) { $orderLines += ""; $orderLines += "  $($e.task)"; $lastTask = $e.task }
        $flag = $(if ($e.check -eq "fail") { "   <-- PROBLEM: $($e.problem)" } elseif ($e.problem) { "   (note: $($e.problem))" } else { "" })
        $orderLines += ("  {0,3}. {1}{2}" -f $i, $e.team, $flag)
    }
    $orderLines += ""; $orderLines += ""
}
[IO.File]::WriteAllText((Join-Path $OutDir "running-order.txt"), ($orderLines -join "`r`n"), $utf8)
Write-Ok "running-order.txt"

Write-Step "Summary"
if (-not $SkipCheck) {
    Write-Host ("   {0} ready to pre-download, {1} will stream live, {2} YouTube (streams), {3} broken" -f $counts.ok, $counts.stream, $counts.youtube, $counts.fail)
    if ($counts.fail -gt 0) {
        Write-Host "   Ask the teams marked FAIL for a public, direct mp4 link (e.g. a GitHub repo file)," -ForegroundColor Yellow
        Write-Host "   then run prepare.bat again." -ForegroundColor Yellow
    }
    if ($counts.stream + $counts.youtube -gt 0) {
        Write-Host "   Videos that stream live need internet during judging and may buffer." -ForegroundColor Yellow
    }
}
Write-Host ""
Write-Host "   Playlist pages are in: $OutDir" -ForegroundColor Cyan
Write-Host "   Copy playlist-1.html / playlist-2.html to the judging computer(s) and open in Chrome or Edge." -ForegroundColor Cyan
Write-Host ""
try { Invoke-Item $OutDir } catch { }
