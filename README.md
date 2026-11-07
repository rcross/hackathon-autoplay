# Hackathon video autoplay

Plays the 45-second submission videos for judging, in two playlists:

**team name** (5 s) → **video** → **"Judges, submit your scores" countdown** (12 s) → next team …

It's all one file, `hackathon-videos.html`, with nothing to install. It works on Mac or Windows in Chrome or Edge.

1. **Prepare** (e.g. on your Mac): open `hackathon-videos.html`. Load the responses, check the split and the video links, then save `playlist-1_….html` and `playlist-2_….html`.
2. **Play** (e.g. on the Windows judging computers): open a saved playlist file. It downloads **only that playlist's videos**, then plays them.

## 1. Prepare

Open **`hackathon-videos.html`** in Chrome (double-click it, or drag it onto Chrome).

1. **Load the form responses.** Click **Load from Google Sheet**. This only works if the sheet is shared as "anyone with the link". Otherwise, in the sheet choose **File → Download → Comma-separated values (.csv)** and drop that file onto the page.
   - **Columns:** once the responses load, dropdowns choose which column is the **team name**, the **video link** and the **task** to group by ("don't group" is an option). There's also a **cut-off** length for videos (default 60 s). They default to this hackathon's form and are remembered, so the tool works with other forms too.
   - Test submissions (team names like `dummy1` or `test`) are ignored.
   - If a team submitted more than once, its latest submission is used.
2. **Playlists.** All Machine Learning tasks (task name contains "Machine Learning" or "ML") go in Playlist 1. Other tasks are placed to balance the two sizes. Click **move** on any task to change it. Your changes are remembered.
3. **Video link check.** Runs automatically. Each link is tested the same way the playlist page will use it:
   - **ready**: plays, and can be pre-downloaded
   - **streams only**: plays, but the host blocks pre-downloading (Google Drive without an API key), or it's a YouTube link. It needs internet during judging.
   - **problem**: not public, opens a web page instead of a video, not found, a Drive folder or other non-video file, a deleted YouTube video, a format the browser can't play, or no link. These teams get a "not working" card during judging (see below).
   - Videos longer than the cut-off are flagged too (wrong video submitted?)
4. **Save** Playlist 1, Playlist 2, **All teams** (every team in one playlist: Playlist 1's tasks, then Playlist 2's) and the running order. The cut-off chosen in step 1 is built into each playlist file. They go to your Downloads folder with the date and time in the name, so earlier versions are never overwritten.

When teams fix their links, reload the responses and save again.

**Supported links:** direct `.mp4`/`.webm` links, GitHub, Dropbox, OneDrive/SharePoint, Google Drive and YouTube. Share links are converted to direct links automatically.

**Google Drive.** Drive videos stream during judging, as long as the file is shared as "Anyone with the link". Streaming is usually fine with decent internet. To pre-download Drive videos too, paste a free **Google Drive API key** into step 1 (the page has 5-minute instructions). The key also makes the check more precise: it reports "not shared publicly", "not a video (PDF)" and so on. The key is saved inside the playlist files but can only read files that are already public. Delete it after the event.

**YouTube.** YouTube videos play through YouTube's own player. The page sees when each one ends and moves on, and shows the "not working" card if the video is private, deleted or doesn't allow embedding. **Try one YouTube team on the judging computer before the event.** YouTube sometimes refuses to play embeds on a page opened from a file. If it does, those teams get the "not working" card and the playlist continues.

## 2. Play

Copy a saved playlist file to the judging computer and open it in Chrome or Edge.

- Videos start downloading straight away. Each one shows **waiting / % / ready / streams live / problem**, with a **retry** button for failures.
- Click **Start** once everything shows *ready*. You can start earlier: anything not yet downloaded streams instead.
- **Downloaded videos are saved on that computer**, so opening a playlist again later (even after a restart) doesn't download them again. The page shows how many are saved and where. They are in the browser's storage for pages opened from files, usually `%LOCALAPPDATA%\Google\Chrome\User Data\Default\IndexedDB\file__0.indexeddb.blob` (Edge: `…\Microsoft\Edge\User Data\Default\…`). When a playlist finishes, the end screen offers **Play all again**, **Exit** and **Delete saved videos and exit**, the last of which removes them. You can also use **Delete saved videos** on the playlist page at any time. The files are numbered, not named by team, so don't delete them by hand.
- **After the one click on Start, it runs by itself to the end.** Browsers only allow sound after a click on the page, which is why one click is needed.
- **A video that doesn't work** (broken link, or a stream that doesn't start within 20 s or stalls for 15 s) shows the team name and *"Sorry, this team's video isn't working"* for 6 s, then moves on to the next team with no scoring pause. If it breaks after at least 30 s of playing, the judges get the normal scoring pause instead.
- Fully hands-free option: open the file with `#autostart` at the end of its address (e.g. `file:///C:/Users/me/Desktop/playlist-1.html#autostart`). It then starts by itself once downloads finish. Without a click, the browser may play videos muted.

| Key | Action |
|---|---|
| Space | pause / resume (the countdowns pause too) |
| → | skip ahead (title → video → scores → next team) |
| ← | back to the start of this team (or the previous team from the title card) |
| R | replay this team's video |
| F | toggle fullscreen |
| Esc | stop and return to the list (press twice if fullscreen) |

Each team has a **start here** button, so you can resume partway through. The menu also has settings for the team-name time, the scoring pause (default 12 s), the "not working" message time (default 6 s) and the cut-off for overlong videos (default 60 s; 0 = never).

**Tip:** check on the judging computer itself before the event. A video that plays on a Mac (e.g. an iPhone HEVC `.mov`) may not play in Chrome on Windows. Each team's status in the playlist list shows this.
