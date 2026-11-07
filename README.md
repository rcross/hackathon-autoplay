# Hackathon video autoplay

Plays the 45-second submission videos for judging, in two playlists:

**team name** (5 s) → **video** → **"Judges, submit your scores" countdown** (12 s) → next team …

It's all one file, `hackathon-videos.html`, with nothing to install. It works on Mac or Windows in Chrome or Edge.

1. **Prepare** (e.g. on your Mac): open `hackathon-videos.html`. Load the responses, check the split and the video links, then save `playlist-1_….html` and `playlist-2_….html`.
2. **Play** (e.g. on the Windows judging computers): open a saved playlist file. It downloads **only that playlist's videos**, then plays them.

## 1. Prepare

Open **`hackathon-videos.html`** in Chrome (double-click it, or drag it onto Chrome).

1. **Load the form responses.** Click **Load from Google Sheet**. This only works if the sheet is shared as "anyone with the link". Otherwise, in the sheet choose **File → Download → Comma-separated values (.csv)** and drop that file onto the page.
   - Test submissions (team names like `dummy1` or `test`) are ignored.
   - If a team submitted more than once, its latest submission is used.
2. **Playlists.** All Machine Learning tasks (task name contains "Machine Learning" or "ML") go in Playlist 1. Other tasks are placed to balance the two sizes. Click **move** on any task to change it. Your changes are remembered.
3. **Video link check.** Runs automatically. Each link is tested the same way the playlist page will use it:
   - **ready**: plays, and can be pre-downloaded
   - **streams only**: plays, but the host (e.g. Google Drive) blocks pre-downloading, or it's a YouTube link. It needs internet during judging and may buffer.
   - **problem**: not public, opens a web page instead of a video, not found, a format the browser can't play, or no link
   - Videos longer than 60 s are flagged too (wrong video submitted?)
4. **Save** Playlist 1, Playlist 2 and the running order. They go to your Downloads folder with the date and time in the name, so earlier versions are never overwritten.

When teams fix their links, reload the responses and save again.

**Most reliable host:** a file in a public GitHub repo, or Dropbox. Both can be pre-downloaded. Share links from GitHub, Google Drive, Dropbox and OneDrive/SharePoint are converted to direct links automatically.

## 2. Play

Copy a saved playlist file to the judging computer and open it in Chrome or Edge.

- Videos start downloading straight away. Each one shows **waiting / % / ready / streams live / problem**, with a **retry** button for failures.
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

**Tip:** check on the judging computer itself before the event. A video that plays on a Mac (e.g. an iPhone HEVC `.mov`) may not play in Chrome on Windows. Each team's status in the playlist list shows this.
