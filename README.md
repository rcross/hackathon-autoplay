# Hackathon video autoplay

Plays the 45-second submission videos for judging, in two playlists:

**team name** (5 s) → **video** → **"Judges, submit your scores" countdown** (12 s) → next team …

All videos are downloaded ahead of time, so nothing buffers during judging. It runs on Windows with nothing to install: it uses the PowerShell built into Windows and Chrome or Edge.

## Before judging

1. Download this folder (on GitHub: **Code → Download ZIP**) and unzip it.
2. Double-click **`prepare.bat`**. It:
   - downloads the latest form responses from the Google Sheet
   - splits teams into **Playlist 1** (all Machine Learning tasks) and **Playlist 2** (everything else), grouped by task. If the sizes are uneven, it moves whole non-ML tasks across to even them out.
   - downloads every video into `videos\`
   - writes `running-order.txt` (handy for the judges) and lists every submission with a problem (private link, web page instead of a video, 404, missing URL)
3. Fix any problem links with the teams, then run `prepare.bat` again. You can re-run it as often as you like: videos it already has are skipped.

**If the sheet can't be downloaded automatically** (it isn't shared publicly), open the sheet, choose **File → Download → Comma-separated values (.csv)**, save the file as `responses.csv` in this folder, then run `prepare.bat` again.

### Supported video links
Direct `.mp4`/`.webm` links, GitHub (`/blob/` links are converted to raw), Google Drive, Dropbox and OneDrive/SharePoint share links. **YouTube** links can't be pre-downloaded, so they are embedded and streamed at judging time, which needs internet. They're flagged in the output.

## During judging

Open **`player.html`** in Chrome or Edge, then click **Start Playlist 1** or **Start Playlist 2**. It goes fullscreen and runs on its own.

| Key | Action |
|---|---|
| Space | pause / resume (the countdowns pause too) |
| → | skip ahead (title → video → scores → next team) |
| ← | back to the start of this team (or the previous team from the title card) |
| R | replay this team's video |
| F | toggle fullscreen |
| Esc | stop and return to the menu (press twice if fullscreen) |

Each team also has a **start here** button in the menu, so you can resume partway through a playlist.

On the menu screen you can change how long the team name shows, the scoring pause (default 12 s) and the cut-off for overlong videos (default 60 s; 0 = never cut off). The player remembers your settings.

## Settings in `prepare.ps1`

At the top of the file:

- `$MlTaskPattern`: how Machine Learning tasks are recognised (default: task name contains "Machine Learning" or "ML")
- `$PlaylistOverride`: force a task into playlist 1 or 2
- `$IgnoreTeamPattern`: test submissions to skip (default: team names like `dummy1` or `test`)

If a team submits more than once, only its latest submission is used.
