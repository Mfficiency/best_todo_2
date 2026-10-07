# Best Music Changelog

Best Music's own changelog, split off from BestToDo's `CHANGELOG.md` so each
app tells its own story and a Todo-only release no longer bumps Music's
version number. Entries from before the split are still recorded in the
shared history over in `CHANGELOG.md` (search it for "Music"/"Best Music");
nothing has been copied over here.

## [0.3.17] - 2026-10-07
- Subscriptions: swipe a video right to add it to the queue, left to mark it watched (with Undo), and long-press for all its options — Transcript, Quick summary, Download, Open in YouTube and more. Each gesture can be changed in Settings → Subscriptions
- Videos you add to the queue are downloaded so they play without internet, and kept for 2 days (the playing video and the next two in the queue too) — change the number of days, or turn it off, in Settings → Subscriptions
- Searching Subscriptions: when nothing in your feed matches, it searches YouTube itself and shows those videos instead
- The Subscriptions screen no longer has a settings button at the top — its settings are in Settings
- CI build: 2026-10-07 09:19 UTC
- Build duration (apk, CI): 6m 28s
- APK size: 63.4 MB

## [0.3.16] - 2026-10-07
- Fixed: Subscriptions videos not loading — channels needed YouTube's RSS feed for their video titles, and that feed fails a lot; the titles now come from the channel's video list itself, both are asked at the same time, and the slow backup is only used when both fail
- The feed keeps its videos: opening it shows the saved list straight away and only adds the newest videos (nothing disappears because one refresh listed fewer); saved videos stay for 30 days. Opening it again within 10 minutes doesn't reload at all — pull down to refresh anytime
- CI build: 2026-10-07 05:39 UTC
- Build duration (apk, CI): 8m 11s
- APK size: 63.0 MB

## [0.3.15] - 2026-10-07
- The "Back to music" / "Back to videos" button is now a small see-through circle with just an icon, so messages that pop up at the bottom (errors, Undo) are no longer hidden behind it
- CI build: 2026-10-07 04:28 UTC
- Build duration (apk, CI): 6m 40s
- APK size: 63.0 MB
- Local build: 2026-10-07 06:28
- Build duration (apk): 4m 13s
- APK size: 63.7 MB

## [0.3.14] - 2026-10-06
- Subscriptions: a channel's new videos didn't show up? Each channel on the Channels page now has a "Check for new videos" button that fetches just that channel again (trying up to three times), and the feed's "Couldn't refresh …" line has a Retry button
- Fixed: a channel was sometimes left out of a refresh entirely when YouTube's feed for it had a hiccup, even though its videos could still be read another way
- CI build: 2026-10-06 05:40 UTC
- Build duration (apk, CI): 8m 00s
- APK size: 63.0 MB

## [0.3.13] - 2026-10-06
- New app icon: a music note with a motion blur — on the home screen (it follows your phone's icon shape, and themed icons on Android 13+), the startup screen, the notifications, the menu and the About page
- CI build: 2026-10-06 04:39 UTC
- Build duration (apk, CI): 8m 30s
- APK size: 63.0 MB
- Local build: 2026-10-06 06:38
- Build duration (apk): 4m 07s

## [0.3.12] - 2026-10-05
- Fixed: the background song info search stopped after a few songs with "paused (offline?)" even though you were online — it went faster than Deezer allows and one "slow down" answer paused everything. It now paces each service to its own limit, waits and retries when asked to slow down, rests a service that keeps refusing while the others carry on, and only pauses when there really is no internet
- Shows how long the search has left ("Looking up song info online… 120/1954 · about 1 h 40 min left"), also for on-device BPM detection
- New "Restart" button next to that line on Metadata Scan: searches again right away, including songs where nothing was found before
- Keeps working while you use other apps: a quiet "Best Music · filling in song info" notification shows the progress and goes away when it's done
- CI build: 2026-10-06 04:28 UTC
- Build duration (apk, CI): 5m 45s
- APK size: 63.0 MB

## [0.3.11] - 2026-10-05
- Song info fills itself in, in the background: songs missing an artist, album, genre, year or BPM are looked up online (Deezer, iTunes and MusicBrainz, trying several spellings of the title until one matches) and only the blanks are filled — your own tags and edits are never overwritten
- If the internet can't find a BPM for at least 90% of your songs, Best Music works it out on your phone by listening to each remaining song — no button to press
- What's found is also saved into your MP3 files' own tags, so other music apps see it too — only blank tags are filled, nothing already in the file is changed
- Fixed: the library scan never read your MP3s' tags (artist, album, genre, year, BPM) at all — the library is rescanned once automatically after updating to pick them up
- Metadata Scan and Songs by BPM show what it's doing ("Looking up song info online… 12/240", "Detecting BPM on device… 3/40")
- CI build: 2026-10-05 13:06 UTC
- Build duration (apk, CI): 7m 45s
- APK size: 62.9 MB

## [0.3.10] - 2026-10-05
- If an update can't be downloaded, the "Downloading…" message is replaced right away by the reason instead of showing a few seconds later
- CI build: 2026-10-05 12:02 UTC
- Build duration (apk, CI): 6m 41s
- APK size: 62.7 MB

## [0.3.9] - 2026-10-05
- Videos now have a Transcript button: read the full transcript of a Subscriptions video, with timestamps — taken from YouTube's captions, or from backup sites (Invidious) when YouTube won't give them
- New "Quick summary" button on videos: a short summary of the video, its key points and the conclusion it reaches. Add a Claude API key in Settings → Transcripts & summaries for a summary written by Claude; without one, the phone picks the key sentences itself
- Save a summary to Obsidian with one tap — it lands as a note in your Research folder (folder and vault are set in Settings → Transcripts & summaries) — or use Share/Copy to send it anywhere
- CI build: 2026-10-05 11:25 UTC
- Build duration (apk, CI): 5m 58s
- APK size: 62.7 MB

## [0.3.8] - 2026-10-05
- New "Songs by BPM" page (menu, and at the top of Playlists): drag either end of the BPM slider to pick a tempo range, see the songs in it, then play them as your queue, save them as a playlist, or save the range as a preset to come back to
- Songs now have a BPM: read from your MP3s' BPM tag (rescan the library to pick it up), from a Subsonic/Navidrome server, typed in on Track info, or filled in through the metadata CSV's new "bpm" column
- CI build: 2026-10-05 10:51 UTC
- Build duration (apk, CI): 6m 26s
- APK size: 62.4 MB

## [0.3.7] - 2026-10-05
- The Now Playing screen (songs and videos) has just the menu button at the top — every other button (speed, volume, sleep timer, shuffle, queue, info and "Back to music/videos") now sits at the bottom, within reach of your thumb
- CI build: 2026-10-05 08:43 UTC
- Build duration (apk, CI): 6m 53s
- APK size: 62.2 MB

## [0.3.6] - 2026-10-04
- Updates now install automatically: a new version is downloaded as soon as it appears and Android's install screen opens, with no "Do you want to download?" question first
- Changelog now shows when the version you're running was installed (e.g. "Installed v0.3.6+403 · 2026-10-04 18:40 (2 hours ago)"), so you can see when an update came through
- CI build: 2026-10-04 20:06 UTC
- Build duration (apk, CI): 8m 11s
- APK size: 62.2 MB

## [0.3.5] - 2026-10-04
- Subscriptions videos have back 10 seconds and forward 10 seconds buttons: in the notification (also on the lock screen), on the Now Playing screen and on the song bar at the bottom
- CI build: 2026-10-04 20:03 UTC
- Build duration (apk, CI): 8m 35s
- APK size: 62.2 MB

## [0.3.4] - 2026-10-04
- Volume now works with your phone's own volume instead of a separate app volume: Best Music remembers the phone volume you use for music and the one you use for videos, and switches the phone to the right one whenever you go between them (the phone's volume bar shows when it does). Changes you make with the volume buttons are remembered too
- The boost for quiet videos stays inside the app, on top of the phone's volume
- CI build: 2026-10-04 17:31 UTC
- Build duration (apk, CI): 8m 20s
- APK size: 62.2 MB

## [0.3.3] - 2026-10-04
- Settings is now organised like BestToDo's: buttons at the top jump to a section, and every section (Library, Playback, Appearance, Subscriptions feed, SponsorBlock, Updates) folds open and closed
- The Subscriptions feed's settings now live in Settings (the feed's settings button opens them there) instead of on their own page
- Search your Subscriptions feed: tap the search button and type part of a video title, a channel or a date ("yesterday", "oct 3", "friday", "2026-10-03") — typos are fine, and the Title/Channel/Date buttons narrow it down. It finds older videos too, not just this week's
- CI build: 2026-10-04 07:32 UTC
- Build duration (apk, CI): 8m 10s
- APK size: 62.2 MB

## [0.3.2] - 2026-10-04
- "Back to videos" now also takes you to the Subscriptions feed, and "Back to music" opens the song that's playing — the screen follows the sound
- Every video in Subscriptions now shows its length, views and upload time (e.g. "12:34 · 1.2K views" and "Today 14:05 (3h ago)"), each on its own line so nothing gets cut off
- Length and views show up reliably again: YouTube changed its channel pages so they came back empty (and wiped the correct view count) — the app now reads them the new way, never lets a missing value erase a known one, and looks up anything still missing on the video's own page
- CI build: 2026-10-04 07:29 UTC
- Build duration (apk, CI): 6m 41s
- APK size: 62.1 MB

## [0.3.1] - 2026-10-04
- Update downloads now show which app and version are downloading in the notification (e.g. "Best Music update 0.3.1+397")
- CI build: 2026-10-04 06:38 UTC
- Build duration (apk, CI): 7m 51s
- APK size: 61.8 MB

## [0.3.0] - 2026-10-04
- Subscriptions open faster: the last 2 days show right away, the rest of the week fills in by itself, and older videos load only when you scroll to the end — always newest first
- Tap a video to play it; the info button (where the play button was) shows its description and options
- Videos no longer play the next one automatically (turn it back on in Feed settings if you like)
- New "Back to music" / "Back to videos" button at the bottom left, just above the song bar: one tap stops what's playing and picks up the other where you left it, with its own volume and speed
- The video speed you pick is now remembered for your next videos
- CI build: 2026-10-04 06:15 UTC
- Build duration (apk, CI): 5m 43s
- APK size: 61.8 MB

## [0.2.99] - 2026-10-03
- Jump between your last song and your last video in one tap: stop either halfway, and the button on the song bar (or at the top of Now Playing) resumes the other right where you left it — even after restarting the app
- Every Subscriptions video you start now downloads completely in the background and stays on your phone for a week after you last played it, so jumping back in is instant and works offline
- Progress bars while things load: songs and videos starting, the feed refreshing (per channel), searches and video descriptions
- APK size: 61.8 MB
- CI build: 2026-10-03 21:46 UTC
- Build duration (apk, CI): 8m 20s

## [0.2.98] - 2026-10-03
- Music and Subscriptions videos now keep separate settings: music always plays at 1× (including songs from YouTube search), and each has its own volume — set it with the new volume button on Now Playing, or in Settings / Feed settings
- Volume boost for quiet Subscriptions videos: a "Boost for quiet videos" slider (up to +12 dB) in the video volume sheet. Never applied to music
- Searching for a song that isn't in your library now searches YouTube by itself — the results sit under a clear "Not in your library" banner and are marked YouTube, so you can tell them apart from your own songs
- Local build: 2026-10-03 21:11
- Build duration (apk): 7m 26s
- APK size: 61.8 MB

## [0.2.97] - 2026-10-03
- Settings now shows the folder where update downloads are saved, with a button to copy its path

## [0.2.96] - 2026-10-03
- Playback speed for Subscriptions videos: set a default speed in Feed settings (0.5× to 3×), and change it any time while a video plays with the new speed button (e.g. 1.5×) at the top of Now Playing — pick a preset or fine-tune in 0.05 steps, and tap "Make … the default" to keep it. A speed you pick while playing lasts for the rest of that queue. Your own music always plays at normal speed
- Local build: 2026-10-03 19:28
- Build duration (apk): 5m 34s

## [0.2.95] - 2026-10-03
- Fixed "YouTube search failed" on a working connection — searching YouTube from the library and the MP3 Downloader works again, and a real failure now says what went wrong

## [0.2.94] - 2026-10-03
- Fixed Subscriptions → Channels search failing with "Search failed: NoSuchMethodError ... getT" for every search. You can now also type or paste a channel link or @handle to find that exact channel

## [0.2.93] - 2026-10-03
- Search finds nothing in your library? Tap "Search on YouTube", pick a song and it starts playing right away while it quietly downloads into your library in the background
- Local build: 2026-10-03 19:04
- Build duration (apk): 5m 08s

## [0.2.92] - 2026-10-03
- New Subscriptions feed (menu → Subscriptions): follow YouTube channels — find them by name or import your subscriptions from Tubular/NewPipe — and see their newest videos in one list. Tap a video for its full description, Open in YouTube, or Download (straight into the MP3 Downloader). The play button streams the audio through the normal player (song bar, lock screen, sleep timer) with the thumbnail as cover art and keeps going through the unplayed videos below it. Played videos are dimmed with a check mark, long ones resume where you stopped, and the feed refreshes when you open it or pull down. Feed settings: hide Shorts and livestreams, and SponsorBlock auto-skip of sponsor reads and other marked segments (pick which kinds)

## [0.2.91] - 2026-10-03
- Share a song from Shazam, Spotify or YouTube to Best Music and it starts downloading right away: the best match downloads immediately (a YouTube link downloads that exact video), and if it picked the wrong version, tap the right one in the list to swap
- Works for links from other music apps too (Apple Music, Deezer, SoundCloud, ...) and for plain text like "Song - Artist"
- Finished downloads show up in your library automatically, no Rescan needed
- Best Music only appears in the share menu for links and text, not for photos or PDFs
- No more accidental music blasting: when nothing is playing and no Bluetooth speaker or headphones are connected, pressing Play asks "Play out loud?" first (turn it off in Settings → Ask before playing out loud)
- The Changelog page now starts straight with the latest release — no title or intro text on top
- The playback notification shows just Previous, Play/Pause and Next — the Stop button is gone
- Local build: 2026-10-03 17:29
- Build duration (apk): 34m 14s

## [0.2.90] - 2026-10-02
- Only one copy of the app can be open at a time: opening it again from the home screen, a notification, a widget or a shared link brings back the copy that's already running instead of starting a second one (on Windows too)
- Local build: 2026-10-02 19:15
- Build duration (apk): 3m 30s

## [0.2.89] - 2026-10-02
- Best Music is now blue like BestToDo, and Settings has a Dark mode switch that applies right away. New sleep timer: pause after 5 minutes to 1.5 hours, a custom time, or at the end of the current song — set it from Now Playing (moon icon), the menu, Settings, or by long-pressing the song bar at the bottom; while it runs the song bar shows the time left

## [0.2.88] - 2026-10-02
- The song bar now sits at the bottom of every screen in Best Music, showing what's playing with a play/pause button (tap it to open Now Playing). When nothing is playing it shows the last song you played — press play to carry on right where you left off, even after closing the app, restarting your phone or updating

## [0.2.87] - 2026-10-02
- Date added now means when the song arrived on your phone/computer: the default sort is "Added to device" (read from the file itself), with "Added to app" (when Best Music first found it) kept as a separate sort option. Track info shows both dates. Your library rescans itself once after updating to pick up the device dates

## [0.2.86] - 2026-10-02
- Fixed screens hiding behind the phone's navigation bar on every page (track lists, Track info, ...) — Best Music now keeps clear of it the same way BestToDo does. Also fixed the now-playing bar taking over the whole screen in 0.2.85

## [0.2.85] - 2026-10-02
- Music Player: every sort option (Date added, Title, Artist, Duration) now goes both ways — tap the new Newest/Oldest first, A–Z/Z–A or Longest/Shortest first button next to the sort menu (or pick the same option again) to flip it, and your choice is remembered. Long track lists get a fast-scroll handle on the right edge: drag it to fly through hundreds of songs, with a bubble showing the letter, month or length you're at. Fixed the mini player and the bottom of the list hiding behind the phone's navigation bar

## [0.2.84] - 2026-09-19
- Fixed the Wishlist checking an item off here also marking it done in BestToDo: since 0.2.78 both apps' Wishlists were quietly synced through one shared external-storage file, so a checkbox tapped in either app took effect in both. Best Music's Wishlist is local-only again, stored purely in its own app-private storage like every other Best Music list — BestToDo's own Wishlist and its "Connect"/sync option are unchanged

## [0.2.83] - 2026-09-18
- Wishlist now genuinely starts empty on a fresh install: it was silently inheriting BestToDo's own historical feature-request backlog (a one-time import the two apps' generic storage layer shared). Each item also gets a checkbox now, so you can mark it done right from the list instead of opening it first
- Local build: 2026-09-18 23:11
- Build duration (apk): 2m 37s

## [0.2.82] - 2026-09-18
- Music Player: the Artists tab now groups a "feat." credit (e.g. "49th & Main feat. SKYLAR") under its main artist instead of treating it as a separate artist, showing who's featured alongside the track count; tracks can now be tagged with free-form labels (e.g. "Wedding songs", "Belgian Top Charts") from the Track info page, with a new Tags tab to browse the library grouped by tag (a track with several tags appears under each), also round-tripped through the metadata CSV export/import

## [0.2.81] - 2026-09-18
- Music Player: redesigned around Samsung Music's layout — Favourites/Playlists/Tracks/Artists/Folders tabs (Tracks was "Library"), a search icon to find any track by title/artist, a quick sort menu (Date added/Title/Artist/Duration) plus shuffle/play-all on every track list, each track's separate action icons folded into one more-options (⋮) menu (Favorite, Add to playlist, Track info, and Remove from playlist inside a hand-built playlist), and a "+" button on a hand-built playlist to pick and add several songs at once instead of one at a time from the library

## [0.2.80] - 2026-09-18
- Best Music now keeps its own version number and changelog (`MUSIC_VERSION`, this file), independent of BestToDo's — see CHANGELOG.md for BestToDo's own history from here on
