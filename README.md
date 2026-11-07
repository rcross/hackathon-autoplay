# Hackathon video autoplay

Plays the 45-second submission videos for judging, in two playlists:

**team name** (5 s) → **video** → **"Judges, submit your scores" countdown** (12 s) → next team …

There are two separate steps:

1. **Prepare** (once, on any Windows PC): `prepare.bat` builds two standalone pages, `playlist-1.html` and `playlist-2.html`, and checks every video link.
2. **Play** (on the judging computer(s)): open one playlist page. It downloads **only that playlist's videos**, then plays them.

Nothing needs installing: the prep step uses the PowerShell built into Windows, and the pages run in Chrome or Edge.

## 1. Prepare the playlists

1. Download this folder (on GitHub: **Code → Download ZIP**) and unzip it.
2. Double-click **`prepare.bat`**. It:
   - downloads the latest form responses from the Google Sheet
   - splits teams into **Playlist 1** (all Machine Learning tasks) and **Playlist 2** (everything else), grouped by task. If the sizes are uneven, it moves whole non-ML tasks across to even them out.
   - **checks every video link.** It fetches only the first few bytes of each and reports one of:
     - `OK`: public video that the playlist page can pre-download
     - `WARN`: public video, but the host (e.g. Google Drive) blocks pre-downloading, or it's a YouTube link. It will stream live during judging, which needs internet and may buffer.
     - `FAIL`: not public, a web page instead of a video, not found, or no link submitted
   - writes `playlist-1.html`, `playlist-2.html` and `running-order.txt` into a new folder, `output\<date-time>\`. Earlier runs are kept, never overwritten.
3. Chase the teams marked FAIL (or WARN, if you want everything pre-downloaded), then run `prepare.bat` again.

**If the sheet can't be downloaded automatically** (it isn't shared publicly), open the sheet, choose **File → Download → Comma-separated values (.csv)**, save the file as `responses.csv` in this folder, then run `prepare.bat` again.

**Most reliable host:** a file in a public GitHub repo, or Dropbox. Both allow pre-downloading. Share links from GitHub, Google Drive, Dropbox and OneDrive/SharePoint are converted to direct links automatically.

## 2. Play a playlist

Copy `playlist-1.html` or `playlist-2.html` to the judging computer and open it in Chrome or Edge. Each file is self-contained.

- Videos start downloading straight away. The list shows each one as **waiting / % / ready / streams live / problem**, with a **retry** button for failures.
- Click **Start** once everything shows *ready*. You can start earlier: anything not yet downloaded streams instead.
- Keep the tab open. Videos are held by the tab, so reloading it downloads them again.

| Key | Action |
|---|---|
| Space | pause / resume (the countdowns pause too) |
| → | skip ahead (title → video → scores → next team) |
| ← | back to the start of this team (or the previous team from the title card) |
| R | replay this team's video |
| F | toggle fullscreen |
| Esc | stop and return to the list (press twice if fullscreen) |

Each team has a **start here** button, so you can resume partway through. The menu also has settings for the team-name time, the scoring pause (default 12 s) and the cut-off for overlong videos (default 60 s; 0 = never).

## Settings in `prepare.ps1`

At the top of the file:

- `$MlTaskPattern`: how Machine Learning tasks are recognised (default: task name contains "Machine Learning" or "ML")
- `$PlaylistOverride`: force a task into playlist 1 or 2
- `$IgnoreTeamPattern`: test submissions to skip (default: team names like `dummy1` or `test`)

If a team submits more than once, only its latest submission is used. `player-template.html` is the template the playlist pages are built from. Keep it next to `prepare.ps1`.
