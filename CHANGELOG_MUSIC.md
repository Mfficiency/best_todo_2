# Best Music Changelog

Best Music's own changelog, split off from BestToDo's `CHANGELOG.md` so each
app tells its own story and a Todo-only release no longer bumps Music's
version number. Entries from before the split are still recorded in the
shared history over in `CHANGELOG.md` (search it for "Music"/"Best Music");
nothing has been copied over here.

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
