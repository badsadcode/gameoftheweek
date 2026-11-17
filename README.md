# Game of the Week · Bad Ideas Works

A new small game every week, premiered live every Friday on YouTube.
**No fixed engine, no fixed genre:** every week uses whatever fits that week's bad idea.
*Where bad ideas receive suspiciously serious engineering.*

**Site:** https://badsadcode.github.io/gameoftheweek/ (devlog, downloads, browser versions, stream replays)

| Week | Game | Theme | Genre | Engine | Stream |
| ---- | ---- | ----- | ----- | ------ | ------ |
| 1 | [Frostline: Last Train to Haven](games/01-frostline/) | Survival on a train | Survival / action | LÖVE (Lua) | Fri 20 Nov 2026 |

## Repo layout

```
games/
  01-frostline/
    game.json      the game's info card: title, theme, stream date, YouTube video id, progress...
    devlog.json    devlog entries for the site, newest first
    screenshot.png shown on the site
    README.md      how to play (shipped inside the zip)
    src/           the game itself (any language / engine)
    build.sh       optional: custom build for non-LÖVE games
    prebuilt/      optional: ready-made downloads for engines that can't build in CI
site/              the website (index.html, game.html, app.js, style.css, config.json)
tools/
  build-all.sh     builds every game folder, whatever its engine
  build-love.sh    helper for LÖVE games: Windows exe zip + .love + web version
  assemble-site.sh puts site/ + every game together for GitHub Pages
.github/workflows/pages.yml   builds every game and deploys the site on each push to main
```

## The weekly routine

1. **Theme drops:** create `games/NN-name/` with `game.json` (copy week 1's), `devlog.json` and `src/`.
   The newest week automatically becomes "This week" on the site, and the previous one moves to the archive.
2. **Build week:** write devlog entries as things happen (or go wrong).
3. **Friday stream:** after streaming, put the YouTube video id in `game.json` (`youtube_video_id`)
   and tick the progress steps. The replay is embedded on the game's page.
4. Push to `main`. The site rebuilds itself in about a minute.

Stream channel and time live in `site/config.json` (`youtube_channel_url`, `stream_time`, `stream_timezone`).

## Any engine, any genre

Each week picks the right tool for its idea. `tools/build-all.sh` supports three ways to build a game folder:

1. **LÖVE:** set `"engine": "love"` in `game.json` and the helper does everything.
2. **Anything scriptable** (Godot, Python/pygame, C/raylib, HTML5, ...): add `build.sh` to the game folder.
   It is called as `build.sh <out-dir>` on Ubuntu in CI and may download whatever tools it needs.
3. **Engines that can't build in CI** (e.g. Unity): put the finished files in `prebuilt/`.

However it's built, the output should contain `<exe_name>-win64.zip` and optionally `play/index.html`
(a browser version). Fill in `genre` and `engine_label` in `game.json` so the site can show them.
One broken week never takes the site down: the build warns and deploys the rest.
