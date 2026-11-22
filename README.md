# Zap for Android

The Android version of [Zap](https://github.com/Kira35s/Zap), for phones and
tablets: the same app, with a touch interface. Build it with `bin/apk` (see
[Android](#android) below); the desktop build still works from this tree.

![Zap showing live channels with their TV guide](docs/screenshot.png)

Zap is an IPTV player for Omarchy: live channels with their TV guide, movies
and series, from Xtream Codes accounts and M3U playlists. It follows the
Omarchy theme and language, and everything works from the keyboard.

- **Live TV** with what's on now and next, previewed beside the list; Enter
  again fills the screen, and ↑ ↓ change channel.
- **TV guide**: a grid of channels and programmes from the provider's XMLTV
  guide (plain or gzipped), matched by guide id or by channel name.
- **Movies** open on a sheet with the synopsis, director, cast, genre and
  running time from the provider, and play or resume from there.
- **Series** show their synopsis and cast, a tab per season, and the
  episodes of the season picked; the next episode starts when one ends.
- **Audio and subtitles**: A changes the audio language and S turns
  subtitles on or picks the next language, or use the buttons under the
  picture. The languages picked last are chosen first on whatever plays next.
- **Favourites**, **continue watching** (resume points for movies and
  episodes), and a search across everything.
- **Settings** (8): Zap follows the Omarchy language, or one picked for Zap
  alone (Français, English) without changing the rest of the desktop.
- Several sources at once. Lists are cached and refreshed daily, the guide
  twice a day, or on demand with R.

## Sources

Press 7 and add a source:

- **Xtream Codes**: the server address, username and password your provider
  gave you. The live, movie and series lists and the guide come from the
  server; a different XMLTV guide address can be given instead.
- **M3U playlist**: a web address or a file path. Channels, movies
  (`/movie/` or video-file addresses) and series episodes (`/series/`, or
  names with `S01E02`) are sorted apart. The guide comes from the playlist's
  `url-tvg`, or from the address you give.

Sources, with their passwords, are kept in `~/.config/zap/sources.json`,
readable only by you. Favourites and resume points are in
`~/.local/share/zap/state.json`, and downloaded lists, guides and images in
`~/.cache/zap`.

## Keyboard

| Key | Action |
| --- | --- |
| `1` – `8` | Live TV, TV guide, movies, series, favourites, continue watching, sources, settings |
| `/` or `Ctrl+F` | Search |
| `↑` `↓` `←` `→` | Move; Left goes back to the categories |
| `Enter` | Play, or open a movie's sheet or a series; on the playing channel, full screen |
| `Esc` | Back: leave full screen, close the sheet or the series, clear the search |
| `Space` | Pause and resume |
| `↑` `↓`, `PgUp` `PgDn` | Previous and next channel while watching |
| `←` `→`, `Shift+←` `→` | Skip 10 seconds or 1 minute in a movie or an episode |
| `←` `→` in a series | Change season |
| `A` | Change the audio language while watching |
| `S` | Subtitles: off, or the next language |
| `F` | Add to or remove from favourites |
| `M` | Mute |
| `+` `-` | Volume |
| `X` | Stop playing |
| `O` | Open in mpv |
| `R` | Refresh the lists and the TV guide |
| `Del` | Remove from continue watching |
| `F11` | Full-screen window |
| `?` | Show every shortcut |
| `Q` | Quit |

## Building

Zap is C++ and Qt Quick, built with qmake6 and make. Playback goes through
Qt Multimedia's FFmpeg backend; a stream it can't play opens in mpv with O.

```sh
bin/build      # build/zap
bin/test       # the Qt Test suite, offscreen
bin/install    # makepkg -fsi: installs zap, its icon and its launcher entry
bin/apk        # build-android/zap.apk, for Android phones and tablets (arm64)
```

### Android

`bin/apk` expects its toolchain in `~/Android`: Qt 6.12.0 for Android
(`android_arm64_v8a`, with Qt Multimedia, plus the matching `gcc_64` host
build, both through aqtinstall), the SDK with platform 36 and NDK
27.2.12479018, KDAB's [android_openssl](https://github.com/KDAB/android_openssl)
and a Temurin 17 JDK from mise. The first run creates the signing key,
`~/Android/zap.keystore`; keep it, since Android only installs an update
signed with the same key.

On Android, or with `--touch` on the desktop, a tap plays, a long press adds
to the favourites, and the player has on-screen buttons. On a phone the
sections and categories move into drawers and everything plays full screen.
"Open in another app" hands a stream to VLC or any other installed player.

## License

MIT. Theme and language handling follow Omacut and Monologue by David
Heinemeier Hansson, under the MIT License.
