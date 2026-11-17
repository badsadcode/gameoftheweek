// Bad Ideas Works · site renderer
// Reads config.json + games.json (built from every games/*/game.json) and each game's devlog.json.
// index.html -> show homepage, game.html?g=<slug> -> one game's page with its full devlog.
// A week can have several games (they share "week" in game.json); all premiere that Friday.
// To add a week you never touch this file: add a games/<NN-name>/ folder with game.json + devlog.json.

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

async function getJSON(url, fallback) {
  try {
    const r = await fetch(url, { cache: "no-cache" });
    if (!r.ok) throw new Error(r.status);
    return await r.json();
  } catch (e) {
    return fallback;
  }
}

function parseDate(iso) {
  if (!iso) return null;
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}
function fmtDate(iso) {
  const d = parseDate(iso);
  return d ? d.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" }) : "TBA";
}
function daysUntil(iso) {
  const d = parseDate(iso);
  if (!d) return null;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  return Math.round((d - today) / 86400000);
}

// ---------------------------------------------------------------- pieces
// genre + engine chips: every week can be a different genre in a different engine
function tags(game) {
  const t = [];
  for (const g of String(game.genre || "").split("·").map((x) => x.trim()).filter(Boolean)) t.push(`<span class="tag genre">🎭 ${esc(g)}</span>`);
  if (game.engine_label || game.engine) t.push(`<span class="tag engine">🔧 Made with ${esc(game.engine_label || game.engine)}</span>`);
  return t.length ? `<div class="tags">${t.join("")}</div>` : "";
}

function bulbs(n) {
  n = Math.max(0, Math.min(5, n || 0));
  return "💡".repeat(n) + "🔌".repeat(5 - n);
}

function progressTrack(game) {
  const steps = game.progress || [];
  const firstOpen = steps.findIndex((s) => !s.done);
  return `<ul class="track" aria-label="Progress">${steps.map((s, i) =>
    `<li class="${s.done ? "done" : i === firstOpen ? "now" : ""}">${s.done ? "✔" : i === firstOpen ? "⏳" : "☐"} ${esc(s.label)}</li>`).join("")}</ul>`;
}

function buttons(game, withDevlog) {
  const b = [];
  if (game.download) b.push(`<a class="btn" href="${esc(game.download)}">⬇ Download for Windows</a>`);
  if (game.has_web) b.push(`<a class="btn ghost" href="games/${esc(game.slug)}/play/">▶ Play in browser</a>`);
  if (game.youtube_video_id) b.push(`<a class="btn ghost" href="https://www.youtube.com/watch?v=${esc(game.youtube_video_id)}">📺 Watch the stream</a>`);
  if (withDevlog) b.push(`<a class="btn ghost" href="game.html?g=${esc(game.slug)}">📓 Read the devlog</a>`);
  if (!b.length) b.push(`<span class="small-note">Downloads appear here once the build robot is done.</span>`);
  return `<div class="btns">${b.join("")}</div>`;
}

function gameCard(game, { withDevlog = true, ribbon } = {}) {
  return `
  <article class="game-card" style="--game-accent:${esc(game.accent || "#8fd3ff")}">
    <div class="shot">
      ${game.screenshot !== false ? `<img src="games/${esc(game.slug)}/screenshot.png" alt="${esc(game.title)} screenshot" onerror="this.parentNode.classList.add('noshot');this.remove()">` : ""}
      <span class="ribbon">${esc(ribbon || "WEEK " + game.week)}</span>
    </div>
    <div class="game-body">
      <h3 class="marker">${esc(game.title)}</h3>
      <p class="theme">Theme: <b>${esc(game.theme)}</b>${game.tagline ? " · " + esc(game.tagline) : ""}</p>
      ${tags(game)}
      <p>${esc(game.pitch)}</p>
      ${progressTrack(game)}
      <div class="meter"><span>Bad Idea Rating:</span><span class="bulbs" aria-label="${game.bad_idea_rating} out of 5">${bulbs(game.bad_idea_rating)}</span><span>(${esc(game.bad_idea_note)})</span></div>
      ${buttons(game, withDevlog)}
      ${game.controls ? `<p class="small-note">${esc(game.controls)}</p>` : ""}
    </div>
  </article>`;
}

function entryHTML(e) {
  const kind = ["win", "oops", "wait", "idea"].includes(e.kind) ? e.kind : "idea";
  return `
  <div class="entry ${kind}">
    <span class="pin"></span>
    <div class="meta"><span class="chip day">${esc(e.day)}</span><span class="chip ${kind}">${esc(e.tag)}</span></div>
    <h4>${esc(e.title)}</h4>
    ${e.body || ""}
    ${e.scribble ? `<span class="scribble marker">${esc(e.scribble)}</span>` : ""}
  </div>`;
}

function onAir(game, config) {
  const ch = config.youtube_channel_url;
  const chBtn = ch
    ? `<a class="btn yt" href="${esc(ch)}">▶ Subscribe on YouTube</a>`
    : `<span class="btn yt disabled" title="Channel link coming soon">▶ YouTube channel: link coming soon</span>`;
  const time = config.stream_time ? `${esc(config.stream_time)} ${esc(config.stream_timezone)}` : "time TBA";
  let big, small;
  if (game.youtube_video_id) {
    big = "Replay is up!";
    small = `Week ${game.week} was streamed on ${fmtDate(game.stream_date)}.`;
  } else {
    const d = daysUntil(game.stream_date);
    if (d === null) { big = "Stream date TBA"; small = "Tom is checking his calendar."; }
    else if (d > 1) { big = `Premieres in ${d} days`; small = `${fmtDate(game.stream_date)} · ${time}`; }
    else if (d === 1) { big = "Premieres TOMORROW"; small = `${fmtDate(game.stream_date)} · ${time}`; }
    else if (d === 0) { big = "STREAMING TODAY"; small = `${time} · grab snacks`; }
    else { big = "Replay coming soon"; small = `Streamed on ${fmtDate(game.stream_date)}. The tape is being rewound.`; }
  }
  return `
  <div class="onair">
    <div class="onair-light"><span class="dot"></span> ON AIR · FRIDAYS</div>
    <div class="onair-main">
      <div class="onair-game">Week ${game.week}: <b>${esc(game.title)}</b></div>
      <div class="onair-big marker">${big}</div>
      <div class="onair-small">${small}</div>
    </div>
    <div class="onair-cta">${chBtn}</div>
  </div>`;
}

// ---------------------------------------------------------------- pages
// Which games are "this week"? The ones with the nearest upcoming (or today's) Friday stream that
// hasn't happened yet. Several games can share a week. If nothing is upcoming, the newest week.
function splitWeeks(games) {
  const upcoming = games.filter((g) => !g.youtube_video_id && (daysUntil(g.stream_date) ?? 0) >= 0);
  let spotlightWeek
  if (upcoming.length) {
    upcoming.sort((a, b) => (daysUntil(a.stream_date) ?? 999) - (daysUntil(b.stream_date) ?? 999) || a.week - b.week);
    spotlightWeek = upcoming[0].week;
  } else {
    spotlightWeek = Math.max(...games.map((g) => g.week));
  }
  const spotlight = games.filter((g) => g.week === spotlightWeek);
  const others = games.filter((g) => g.week !== spotlightWeek).sort((a, b) => b.week - a.week || a.slug.localeCompare(b.slug));
  return { spotlight, others, spotlightWeek };
}

function onAirWeek(week, games, config) {
  if (games.length === 1) return onAir(games[0], config);
  // several games premiering together: reuse the single-game banner, then list the titles
  const html = onAir(games[0], config);
  const titles = games.map((g) => "<b>" + esc(g.title.split(":")[0]) + "</b>").join(" + ");
  return html.replace(/<div class="onair-game">[\s\S]*?<\/div>/, `<div class="onair-game">Week ${week}: ${titles}</div>`);
}

async function renderHome() {
  const [config, games] = await Promise.all([getJSON("config.json", {}), getJSON("games.json", [])]);
  if (!games.length) { $("#spotlight").innerHTML = "<p>No games yet. The first bad idea is loading…</p>"; return; }
  const { spotlight, others, spotlightWeek } = splitWeeks(games);
  const logs = await Promise.all(games.map((g) => getJSON(`games/${g.slug}/devlog.json`, [])));
  const logOf = Object.fromEntries(games.map((g, i) => [g.slug, logs[i]]));

  const streamed = games.filter((g) => g.youtube_video_id).length;
  const engines = new Set(games.map((g) => g.engine_label || g.engine).filter(Boolean)).size;
  const weeks = new Set(games.map((g) => g.week)).size;
  const entries = logs.reduce((n, l) => n + l.length, 0);
  $("#stats").innerHTML = `
    <div class="stat"><b>${games.length}</b><span>game${games.length === 1 ? "" : "s"} made</span></div>
    <div class="stat"><b>${weeks}</b><span>week${weeks === 1 ? "" : "s"} of bad ideas</span></div>
    <div class="stat"><b>${streamed}</b><span>Friday premiere${streamed === 1 ? "" : "s"} so far</span></div>
    <div class="stat"><b>${engines}</b><span>engine${engines === 1 ? "" : "s"} used (no favourites)</span></div>
    <div class="stat"><b>${entries}</b><span>devlog confessions</span></div>`;

  $("#onair").innerHTML = onAirWeek(spotlightWeek, spotlight, config);
  $("#this-week-title").textContent = spotlight.length > 1 ? `This Week's Bad Ideas (${spotlight.length})` : "This Week's Bad Idea";
  $("#spotlight").innerHTML = spotlight.map((g, i) =>
    gameCard(g, { ribbon: spotlight.length > 1 ? `WEEK ${g.week} · GAME ${i + 1} OF ${spotlight.length}` : `THIS WEEK · WEEK ${g.week}` })
  ).join('<div style="height:26px"></div>');

  // latest devlog: the freshest entries across this week's games
  $("#latest").innerHTML = spotlight.map((g) => {
    const log = logOf[g.slug];
    const head = spotlight.length > 1 ? `<h3 class="marker log-week" style="color:${esc(g.accent || "#8fd3ff")}">${esc(g.emoji || "📓")} ${esc(g.title.split(":")[0])}</h3>` : "";
    return head + log.slice(0, spotlight.length > 1 ? 2 : 3).map(entryHTML).join("") +
      (log.length > 2 ? `<p class="more"><a class="btn ghost" href="game.html?g=${esc(g.slug)}">Read all ${log.length} entries →</a></p>` : "");
  }).join("");
  $("#latest-title").textContent = spotlight.length > 1 ? `Week ${spotlightWeek}` : `${spotlight[0].emoji || "📓"} Week ${spotlightWeek} · ${spotlight[0].title.split(":")[0]}`;

  // archive + whatever comes next, grouped by week
  const card = (g) => `
    <a class="mini" href="game.html?g=${esc(g.slug)}" style="--game-accent:${esc(g.accent || "#8fd3ff")}">
      <img src="games/${esc(g.slug)}/screenshot.png" alt="" onerror="this.remove()">
      <div class="mini-body">
        <span class="chip day">Week ${g.week}</span>
        <h4 class="marker">${esc(g.title)}</h4>
        <p>${esc(g.theme)}${g.genre ? " · " + esc(g.genre.split("·")[0].trim()) : ""}${g.engine_label ? " · " + esc(g.engine_label) : ""}</p>
        <span class="mini-status">${g.youtube_video_id ? "📺 Streamed" : (g.week > spotlightWeek ? "🔨 In the workshop" : "🎮 Playable")}</span>
      </div>
    </a>`;
  const maxWeek = Math.max(...games.map((g) => g.week));
  $("#archive").innerHTML = others.map(card).join("") + `
    <div class="mini next">
      <div class="mini-body">
        <span class="chip day">Week ${maxWeek + 1}</span>
        <h4 class="marker">???</h4>
        <p>The next bad ideas are still forming in Tom's head. Sage is nervous. Noor is already excited.</p>
      </div>
    </div>`;
}

async function renderGame() {
  const slug = new URLSearchParams(location.search).get("g");
  const games = await getJSON("games.json", []);
  const game = games.find((g) => g.slug === slug) || games[0];
  if (!game) { $("#game").innerHTML = "<p>That game wandered off.</p>"; return; }
  document.title = `${game.title} · Bad Ideas Works`;
  const devlog = await getJSON(`games/${game.slug}/devlog.json`, []);
  $("#game").innerHTML = gameCard(game, { withDevlog: false });
  $("#video").innerHTML = game.youtube_video_id
    ? `<div class="video"><iframe src="https://www.youtube-nocookie.com/embed/${esc(game.youtube_video_id)}" title="Friday stream of ${esc(game.title)}" allowfullscreen loading="lazy"></iframe></div>`
    : `<div class="video-wait marker">📺 The Friday stream (${fmtDate(game.stream_date)}) will appear here</div>`;
  $("#log-title").textContent = `${game.emoji || "📓"} The devlog of week ${game.week}`;
  $("#log").innerHTML = devlog.map(entryHTML).join("") || "<p>No entries yet. Suspiciously quiet.</p>";
}

if (document.body.dataset.page === "game") renderGame(); else renderHome();
