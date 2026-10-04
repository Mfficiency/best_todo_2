# Best Music Changelog

Best Music's own changelog, split off from BestToDo's `CHANGELOG.md` so each
app tells its own story and a Todo-only release no longer bumps Music's
version number. Entries from before the split are still recorded in the
shared history over in `CHANGELOG.md` (search it for "Music"/"Best Music");
nothing has been copied over here.

## [0.3.0] - 2026-10-04
- Subscriptions open faster: the last 2 days show right away, the rest of the week fills in by itself, and older videos load only when you scroll to the end — always newest first
- Tap a video to play it; the info button (where the play button was) shows its description and options
- Videos no longer play the next one automatically (turn it back on in Feed settings if you like)
- New "Back to music" / "Back to videos" button at the bottom left, just above the song bar: one tap stops what's playing and picks up the other where you left it, with its own volume and speed
- The video speed you pick is now remembered for your next videos

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
