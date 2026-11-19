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

// ---------------------------------------------------------------- weeks
// The show runs in weeks: Saturday to Friday we build, Friday Tom streams what we made.
// A week is every game sharing a "week" number; its stream date is their stream_date (a Friday).
const DAY = 86400000;
function today0() { const t = new Date(); t.setHours(0, 0, 0, 0); return t; }
function shortDate(d) { return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }); }

function buildWeeks(games) {
  const by = {};
  for (const g of games) (by[g.week] = by[g.week] || []).push(g);
  return Object.keys(by).map(Number).sort((a, b) => a - b).map((n) => {
    const gs = by[n].sort((a, b) => a.slug.localeCompare(b.slug));
    const stream = parseDate(gs.find((g) => g.stream_date)?.stream_date);
    const start = stream ? new Date(stream - 6 * DAY) : null;
    const video = gs.find((g) => g.youtube_video_id)?.youtube_video_id || "";
    return { n, games: gs, stream, start, video };
  });
}

// this week = the one whose Sat..Fri contains today; else the next one coming; else the newest
function pickWeeks(weeks) {
  const t = today0();
  let cur = weeks.find((w) => w.start && w.start <= t && t <= w.stream);
  if (!cur) cur = weeks.find((w) => w.stream && w.stream > t);
  if (!cur) cur = weeks[weeks.length - 1];
  const next = weeks.filter((w) => w.n > cur.n);
  const past = weeks.filter((w) => w.n < cur.n).reverse();
  return { cur, next, past };
}

function weekRange(w) {
  return w.start ? `${w.start.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })} – ${w.stream.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })}` : "dates TBA";
}

// the 7-day strip: built days ticked off, today glowing, Friday is the show
function calendar(w) {
  if (!w.start) return "";
  const t = today0();
  let html = "";
  for (let i = 0; i < 7; i++) {
    const d = new Date(w.start.getTime() + i * DAY);
    const isToday = d.getTime() === t.getTime();
    const past = d < t;
    const fri = i === 6;
    const cls = ["cal-day", fri ? "fri" : "", isToday ? "today" : "", past ? "past" : ""].join(" ");
    const label = fri ? (w.video ? "📼 Replay" : isToday ? "🔴 LIVE TODAY" : "📺 Stream") : isToday ? "🔨 Today" : past ? "✔ Built" : "🔨 Build";
    html += `<div class="${cls}"><span class="cal-name">${d.toLocaleDateString("en-GB", { weekday: "short" })}</span><span class="cal-date">${d.getDate()}</span><span class="cal-label">${label}</span></div>`;
  }
  return `<div class="calendar">${html}</div>`;
}

function countdown(w, config) {
  const time = config.stream_time ? ` · ${esc(config.stream_time)} ${esc(config.stream_timezone || "")}` : "";
  if (w.video) return { big: "The replay is up!", small: `Streamed on ${shortDate(w.stream)}.` };
  const d = w.stream ? Math.round((w.stream - today0()) / DAY) : null;
  if (d === null) return { big: "Stream date TBA", small: "Tom is checking his calendar." };
  if (d > 1) return { big: `Stream in ${d} days`, small: `Friday ${shortDate(w.stream)}${time}` };
  if (d === 1) return { big: "Stream TOMORROW", small: `Friday ${shortDate(w.stream)}${time}` };
  if (d === 0) return { big: "LIVE TODAY", small: `Grab snacks${time}` };
  return { big: "Replay coming soon", small: `Streamed on ${shortDate(w.stream)}. The tape is being rewound.` };
}

// one game in this week's line-up: screenshot, what it is, where it's at, the latest devlog note
function lineupCard(g, log) {
  const latest = log[0];
  return `
  <article class="lineup" style="--game-accent:${esc(g.accent || "#8fd3ff")}">
    <a class="lineup-shot" href="game.html?g=${esc(g.slug)}"><img src="games/${esc(g.slug)}/screenshot.png" alt="${esc(g.title)} screenshot" onerror="this.remove()"></a>
    <div class="lineup-body">
      <h3 class="marker">${esc(g.emoji || "🎮")} ${esc(g.title)}</h3>
      <p class="theme">${esc(g.tagline || g.theme)}</p>
      ${tags(g)}
      ${progressTrack(g)}
      ${latest ? `<div class="latest"><span class="chip day">Latest from the devlog · ${esc(latest.day)}</span><b>${esc(latest.title)}</b> <a href="game.html?g=${esc(g.slug)}">Read all ${log.length} entries →</a></div>` : ""}
      ${buttons(g, false)}
    </div>
  </article>`;
}

function miniCard(g, status) {
  return `
    <a class="mini" href="game.html?g=${esc(g.slug)}" style="--game-accent:${esc(g.accent || "#8fd3ff")}">
      <img src="games/${esc(g.slug)}/screenshot.png" alt="" onerror="this.remove()">
      <div class="mini-body">
        <h4 class="marker">${esc(g.title)}</h4>
        <p>${esc(g.genre ? g.genre.split("·")[0].trim() : g.theme)}${g.engine_label ? " · " + esc(g.engine_label) : ""}</p>
        <span class="mini-status">${status}</span>
      </div>
    </a>`;
}

async function renderHome() {
  const [config, games] = await Promise.all([getJSON("config.json", {}), getJSON("games.json", [])]);
  if (!games.length) { $("#week-board").innerHTML = "<p>No games yet. The first bad idea is loading…</p>"; return; }
  const logs = await Promise.all(games.map((g) => getJSON(`games/${g.slug}/devlog.json`, [])));
  const logOf = Object.fromEntries(games.map((g, i) => [g.slug, logs[i]]));
  const weeks = buildWeeks(games);
  const { cur, next, past } = pickWeeks(weeks);

  // ---- this week: the event
  const cd = countdown(cur, config);
  const ch = config.youtube_channel_url;
  const n = cur.games.length;
  $("#week-board").innerHTML = `
    <div class="wb-head">
      <div>
        <span class="tape-label">This week</span>
        <h2 class="marker wb-title">Week ${cur.n}</h2>
        <p class="wb-dates">${weekRange(cur)} · ${n} game${n === 1 ? "" : "s"} on the workbench</p>
      </div>
      <div class="wb-stream">
        <div class="onair-light"><span class="dot"></span> FRIDAY STREAM</div>
        <div class="onair-big marker">${cd.big}</div>
        <div class="onair-small">${cd.small}</div>
        ${cur.video ? `<a class="btn yt" href="https://www.youtube.com/watch?v=${esc(cur.video)}">▶ Watch the replay</a>`
          : ch ? `<a class="btn yt" href="${esc(ch)}">▶ Watch on YouTube</a>` : ""}
      </div>
    </div>
    ${calendar(cur)}
    <h3 class="marker wb-sub">What we're making this week</h3>
    ${cur.games.map((g) => lineupCard(g, logOf[g.slug] || [])).join("")}`;

  // ---- next week (games can start early)
  if (next.length) {
    $("#next-week").classList.remove("hidden");
    const nw = next[0];
    $("#next-title").textContent = `Next Week · Week ${nw.n}`;
    $("#next-sub").textContent = `${weekRange(nw)}. Already in the workshop, because we couldn't wait.`;
    $("#next").innerHTML = next.flatMap((w) => w.games.map((g) => miniCard(g, `🔨 Streams Friday ${w.stream ? shortDate(w.stream) : "TBA"}`))).join("");
  } else {
    $("#jump-next").remove();
  }

  // ---- past weeks: one row per Friday stream
  $("#episodes").innerHTML = past.length ? past.map((w) => `
    <div class="episode">
      <div class="ep-head">
        <span class="ep-n marker">Week ${w.n}</span>
        <span class="ep-date">${weekRange(w)}</span>
        ${w.video ? `<a class="btn yt small" href="https://www.youtube.com/watch?v=${esc(w.video)}">📼 Watch the stream</a>` : `<span class="small-note">Replay coming soon</span>`}
      </div>
      <div class="archive">${w.games.map((g) => miniCard(g, "🎮 Playable")).join("")}</div>
    </div>`).join("")
    : `<div class="episode empty"><p class="marker">Nothing here yet.</p><p>Week ${cur.n} is the first one. After Friday's stream it moves here, with the replay.</p></div>`;

  const streamed = weeks.filter((w) => w.video || (w.stream && w.stream < today0())).length;
  const engines = new Set(games.map((g) => g.engine_label || g.engine).filter(Boolean)).size;
  const entries = logs.reduce((s, l) => s + l.length, 0);
  $("#stats").innerHTML = `
    <div class="stat"><b>${games.length}</b><span>game${games.length === 1 ? "" : "s"} made</span></div>
    <div class="stat"><b>${streamed}</b><span>Friday stream${streamed === 1 ? "" : "s"} so far</span></div>
    <div class="stat"><b>${engines}</b><span>engine${engines === 1 ? "" : "s"} used (no favourites)</span></div>
    <div class="stat"><b>${entries}</b><span>devlog confessions</span></div>`;
}

async function renderGame() {
  const slug = new URLSearchParams(location.search).get("g");
  const games = await getJSON("games.json", []);
  const game = games.find((g) => g.slug === slug) || games[0];
  if (!game) { $("#game").innerHTML = "<p>That game wandered off.</p>"; return; }
  document.title = `${game.title} · Bad Ideas Works`;
  const devlog = await getJSON(`games/${game.slug}/devlog.json`, []);
  const w = buildWeeks(games).find((x) => x.n === game.week);
  const streamed = w && w.stream && (w.video || w.stream < today0());
  $("#game").innerHTML = `<p class="week-line">📅 <b>Week ${game.week}</b> · ${w ? weekRange(w) : ""} · ${streamed ? "📺 streamed" : "📺 streams"} Friday ${w && w.stream ? shortDate(w.stream) : "TBA"}</p>` + gameCard(game, { withDevlog: false });
  $("#video").innerHTML = game.youtube_video_id
    ? `<div class="video"><iframe src="https://www.youtube-nocookie.com/embed/${esc(game.youtube_video_id)}" title="Friday stream of ${esc(game.title)}" allowfullscreen loading="lazy"></iframe></div>`
    : `<div class="video-wait marker">📺 The Friday stream (${fmtDate(game.stream_date)}) will appear here</div>`;
  $("#log-title").textContent = `${game.emoji || "📓"} The devlog of week ${game.week}`;
  $("#log").innerHTML = devlog.map(entryHTML).join("") || "<p>No entries yet. Suspiciously quiet.</p>";
}

if (document.body.dataset.page === "game") renderGame(); else renderHome();
