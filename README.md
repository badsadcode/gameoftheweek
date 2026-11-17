# Game of the Week · Bad Ideas Works

A new small game every week, premiered live every Friday on YouTube.
*Where bad ideas receive suspiciously serious engineering.*

**Site:** https://badsadcode.github.io/gameoftheweek/ (devlog, downloads, browser versions, stream replays)

| Week | Game | Theme | Stream |
| ---- | ---- | ----- | ------ |
| 1 | [Frostline: Last Train to Haven](games/01-frostline/) | Survival on a train | Fri 20 Nov 2026 |

## Repo layout

```
games/
  01-frostline/
    game.json      the game's info card: title, theme, stream date, YouTube video id, progress...
    devlog.json    devlog entries for the site, newest first
    screenshot.png shown on the site
    README.md      how to play (shipped inside the zip)
    src/           the game itself
site/              the website (index.html, game.html, app.js, style.css, config.json)
tools/
  build-love.sh    builds a LÖVE game: Windows exe zip + .love + web version
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

Games use LÖVE by default (`"engine": "love"`). A week that needs something else sets another
engine and provides its own `build.sh <out-dir>` in its folder.
