# Best Music Changelog

Best Music's own changelog, split off from BestToDo's `CHANGELOG.md` so each
app tells its own story and a Todo-only release no longer bumps Music's
version number. Entries from before the split are still recorded in the
shared history over in `CHANGELOG.md` (search it for "Music"/"Best Music");
nothing has been copied over here.

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
