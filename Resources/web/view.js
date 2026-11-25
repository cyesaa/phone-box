// Puts the Mac's data on the page (design §8): rings, tiles, the graph and its header, the app list, the now-playing
// card, the status line and the state card. Values glide to each new snapshot and turn red near their limits;
// `frame` draws them on every animation frame. Text always goes in with textContent: names come from other apps.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  const PB = () => global.PhoneBox;
  const tileMetrics = ["gpu", "temp", "power", "net", "disk", "battery"];
  const smooth = (x) => x * x * (3 - 2 * x);

  // Most frames change nothing on the page: write a text or a style only when it differs from the last write.
  const written = new WeakMap();
  function put(element, property, value) {
    let cache = written.get(element);
    if (!cache) {
      cache = {};
      written.set(element, cache);
    }
    if (cache[property] === value) return;
    cache[property] = value;
    if (property === "text") element.textContent = value;
    else if (property.startsWith("--")) element.style.setProperty(property, value);
    else element.style[property] = value;
  }

  class View {
    constructor(t, format) {
      const { motion, heat } = PB();
      this.t = t;
      this.format = format;
      this.host = t.mac;
      this.access = null;
      this.kind = "connecting";
      this.stale = true;
      this.selected = "cpu";
      this.sortBy = "cpu";
      this.snapshot = { t: 0 };
      this.apps = null;
      this.glide = new motion.Glide(900);
      this.limits = heat.limits();
      this.arrivedAt = 0;
      this.graph = null;
      this.rows = new Map();
      this.white = heat.rgb("#eaf6ff");
      this.card = heat.rgb("#0b1622");
      this.ringButtons = {};
      for (const button of global.document.querySelectorAll(".ring-button")) this.ringButtons[button.dataset.metric] = button;
    }

    fillTexts() {
      for (const element of global.document.querySelectorAll("[data-text]")) element.textContent = this.t[element.dataset.text];
      for (const element of global.document.querySelectorAll("[data-metric-label]")) {
        element.textContent = this.t.metric[element.dataset.metricLabel];
      }
      $("more").setAttribute("aria-label", this.t.more);
    }

    setHost(host) {
      this.host = host || this.t.mac;
      this.renderStatus();
    }

    /// The power limits from `ready.limits.power`; the other limits are fixed (design §8).
    setLimits(power) {
      this.limits = PB().heat.limits(power);
    }

    setAccess(access) {
      this.access = access;
      this.renderStatus();
    }

    setState(kind) {
      this.kind = kind;
      this.renderStatus();
      this.renderStateCard();
    }

    setStale(stale) {
      this.stale = stale;
      $("dashboard").classList.toggle("stale", stale);
      this.renderStatus();
    }

    // "● MacBook Pro · kablo": green on the cable, orange on Wi-Fi (no commands), grey while (re)connecting.
    renderStatus() {
      const t = this.t;
      const problems = { cable: t.stateCable, offline: t.stateOffline, unpaired: t.stateUnpaired, nokey: t.stateUnpaired,
                         nodata: t.stateNoData };
      let className = "status";
      let text = t.connecting;
      if (this.kind === "streaming" && !this.stale) {
        const cable = Boolean(this.access && this.access.cable);
        className += cable ? " streaming" : " wifi";
        text = `${this.host} · ${cable ? t.cable : t.wifi}`;
      } else if (problems[this.kind]) {
        className += " problem";
        text = problems[this.kind];
      }
      $("status").className = className;
      $("status-text").textContent = text;
    }

    renderStateCard() {
      const t = this.t;
      const cards = {
        cable: [t.stateCable, t.stateCableText],
        offline: [t.stateOffline, t.stateOfflineText],
        unpaired: [t.stateUnpaired, t.stateUnpairedText],
        nokey: [t.stateUnpaired, t.stateNoKeyText],
        nodata: [t.stateNoData, t.stateNoDataText],
      };
      const card = cards[this.kind];
      $("state").hidden = !card;
      if (!card) return;
      $("state-title").textContent = card[0];
      $("state-text").textContent = card[1];
    }

    /// A new snapshot: the values start gliding to it; the app list and the now-playing card change at once.
    render(snapshot, now) {
      const previous = this.glide.at(now);
      this.snapshot = snapshot;
      this.glide.push(snapshot, now);
      this.arrivedAt = now;
      this.fitTiles(previous);
      const playingBefore = !$("now-playing").hidden;
      this.renderNowPlaying(snapshot.media);
      if (snapshot.apps) this.apps = snapshot.apps;
      // A new app list arrives every 3 s; the card appearing or going changes how many rows fit.
      if (snapshot.apps || playingBefore !== !$("now-playing").hidden) this.renderApps();
    }

    // A long value (busy network, a disk over 1 TB) gets a smaller font instead of being cut off. Measured once
    // per snapshot, not on every frame: with the longer of the text the value glides from and the one it glides to
    // (a speed can change unit on the way), and all writes before the first read.
    fitTiles(previous) {
      const { metrics } = PB();
      const elements = tileMetrics.map((metric) => $(metric + "-tile"));
      elements.forEach((element, index) => {
        const next = metrics.tile(tileMetrics[index], this.snapshot, this.format);
        const before = previous ? metrics.tile(tileMetrics[index], previous, this.format) : "";
        put(element, "text", before.length > next.length ? before : next);
        element.style.fontSize = "";
      });
      for (const element of elements) {
        let size = parseFloat(global.getComputedStyle(element).fontSize);
        while (element.scrollWidth > element.clientWidth + 1 && size > 9) {
          size -= 1;
          element.style.fontSize = size + "px";
        }
      }
    }

    /// Each metric's heat level (0…1, or null) for a snapshot.
    levelsOf(snapshot) {
      const { heat, metrics } = PB();
      const values = metrics.heatValues(snapshot);
      const levels = {};
      for (const metric of Object.keys(values)) levels[metric] = heat.level(this.limits[metric], values[metric]);
      return levels;
    }

    /// Draws everything that moves. Sizes are read first, before any write, so the page is laid out once a frame.
    frame(now) {
      const shown = this.glide.at(now) || this.snapshot;
      const still = PB().motion.reduced();
      const ringSizes = {};
      for (const metric of ["cpu", "ram"]) ringSizes[metric] = this.ringButtons[metric].querySelector("canvas").clientWidth;
      const graph = $("graph");
      const graphSize = [graph.clientWidth, graph.clientHeight];

      const levels = this.levelsOf(shown);
      const { cpu, mem } = shown;
      const f = this.format;
      const memoryOK = mem && mem.total > 0;
      this.drawRing("cpu", ringSizes.cpu, cpu ? cpu.total : null, levels.cpu, now, still,
                    cpu && cpu.load && cpu.load.length ? this.t.load(f.decimal(cpu.load[0])) : "");
      this.drawRing("ram", ringSizes.ram, memoryOK ? (mem.used / mem.total) * 100 : null, levels.ram, now, still,
                    memoryOK ? this.t.memory(f.gibibytes(mem.used), f.gibibytes(mem.total)) : "");
      for (const metric of tileMetrics) this.paintTile(metric, shown, levels[metric]);
      this.renderHeader(shown, levels);
      this.drawGraph(graph, graphSize, now, still);
    }

    drawRing(metric, size, percent, level, now, still, sub) {
      const { heat, metrics, rings } = PB();
      const ok = typeof percent === "number" && Number.isFinite(percent);
      const heated = level ?? 0;
      const from = heat.color(metrics.colors[metric], heated);
      const to = heat.color(metrics.light[metric], heated, true);
      const button = this.ringButtons[metric];
      rings.draw(button.querySelector("canvas"), size, { fraction: ok ? percent / 100 : 0, from, to, now, still, glow: 0 });
      const value = $(metric + "-ring");
      put(value, "text", this.format.percent(ok ? percent : null));
      put(value, "color", heat.css(heat.mix(this.white, to, smooth(heated))));
      put($(metric + "-sub"), "text", sub);
      put(button, "--color", heat.css(from));
    }

    /// A tile's value and colours: the dot and the value turn red with the level, the tile's background warms a
    /// little, and past 0.4 a thin frame appears.
    paintTile(metric, shown, level) {
      const { heat, metrics } = PB();
      const heated = level ?? 0;
      const color = heat.color(metrics.colors[metric], heated);
      const value = $(metric + "-tile");
      const tile = value.closest(".tile");
      put(value, "text", metrics.tile(metric, shown, this.format));
      put(value, "color", heat.css(heat.mix(color, this.white, 0.3 - 0.2 * smooth(heated))));
      put(tile, "--color", heat.css(color));
      put(tile, "backgroundColor", heat.css(heat.mix(this.card, color, 0.2 * smooth(heated))));
      const frames = [];
      if (metric === this.selected) frames.push(`inset 0 0 0 2px ${heat.css(color)}`);
      else if (heated > 0.4) frames.push(`inset 0 0 0 1px ${heat.css(color, ((heated - 0.4) * 0.9).toFixed(2))}`);
      put(tile, "boxShadow", frames.join(", "));
    }

    select(metric) {
      this.selected = metric;
      for (const element of global.document.querySelectorAll(".ring-button, .tile")) {
        element.classList.toggle("selected", element.dataset.metric === metric);
      }
      global.document.querySelector(".graph").dataset.metric = metric;
      this.renderHeader(this.snapshot, this.levelsOf(this.snapshot));
    }

    /// A tap on a ring or a tile: the old graph fades out, the new one fades in.
    switchTo(metric, history) {
      if (metric === this.selected) return;
      const canvas = $("graph");
      if (PB().motion.reduced()) {
        this.select(metric);
        this.renderGraph(history);
        return;
      }
      canvas.classList.add("switching");
      global.setTimeout(() => {
        this.select(metric);
        this.renderGraph(history);
        canvas.classList.remove("switching");
      }, 300);
    }

    renderHeader(shown, levels) {
      const { heat, metrics } = PB();
      const { value, detail } = metrics.header(this.selected, shown, this.format, this.t);
      const key = metrics.graphHeat(this.selected);
      const color = heat.color(metrics.colors[this.selected], key ? levels[key] ?? 0 : 0);
      put($("graph-title"), "text", `${this.t.metric[this.selected]} · ${this.t.lastMinute}`);
      put($("graph-value"), "text", value);
      put($("graph-value"), "color", heat.css(color));
      put($("graph-detail"), "text", detail);
    }

    /// The graph's lines, range and axis label, from the history; `frame` draws them.
    renderGraph(history) {
      const m = PB().metrics;
      const lines = m.lines(this.selected).map((line) => Object.assign({}, line, { values: history.series(line.key) }));
      const bounds = PB().chart.range(m.scale(this.selected), lines.map((line) => line.values));
      this.graph = { lines, bounds, label: m.axisLabel(this.selected, bounds, this.format) };
    }

    drawGraph(canvas, size, now, still) {
      if (!this.graph) return;
      const { heat, metrics, chart, motion } = PB();
      const key = metrics.graphHeat(this.selected);
      const battery = this.snapshot.battery;
      // The battery's graph turns red only when the Mac is not on power.
      const range = key && !(key === "battery" && !(battery && battery.plugged === false)) ? this.limits[key] : null;
      const since = now - this.arrivedAt;
      chart.draw(canvas, size[0], size[1], this.graph.lines, this.graph.bounds, {
        label: this.graph.label,
        shift: still ? 0 : Math.max(0, Math.min(1, since / 1000)),
        settle: still ? 1 : motion.ease(since / 700),
        heat: range ? (color, value) => heat.color(color, heat.level(range, value)) : null,
        limit: range ? { value: range[1], label: this.t.limit } : null,
        now,
        still,
        glow: 0,
      });
    }

    renderNowPlaying(media) {
      $("now-playing").hidden = !media;
      $("now-playing").classList.toggle("playing", Boolean(media && media.playing));
      if (!media) return;
      $("np-title").textContent = media.title;
      $("np-sub").textContent = media.artist ? `${media.artist} · ${media.app}` : media.app;
    }

    toggleSort() {
      this.sortBy = this.sortBy === "cpu" ? "mem" : "cpu";
      this.renderApps();
    }

    // Only as many rows as fit without cutting one off; grey rows are apps the phone cannot quit. Rows are kept
    // between lists, so a row that moves slides from its old place to the new one.
    renderApps() {
      $("app-sort").textContent = (this.sortBy === "cpu" ? "CPU" : "RAM") + " ▾";
      const list = $("app-list");
      if (!this.apps) {
        list.replaceChildren();
        this.rows.clear();
        return;
      }
      const { heat, metrics, motion } = PB();
      const still = motion.reduced();
      const key = this.sortBy;
      const other = key === "cpu" ? "mem" : "cpu";
      const sorted = this.apps.slice().sort((a, b) => b[key] - a[key] || b[other] - a[other] || String(a.name).localeCompare(String(b.name)));
      const rowHeight = parseFloat(global.getComputedStyle(list).getPropertyValue("--row")) || 34;
      const fits = Math.max(1, Math.floor((list.clientHeight + 1) / rowHeight));
      const apps = sorted.slice(0, fits);
      const top = Math.max(1e-9, ...apps.map((app) => app[key] || 0));
      const before = new Map();
      for (const [id, item] of this.rows) before.set(id, item.getBoundingClientRect().top);

      const rows = new Map();
      const items = apps.map((app) => {
        const id = app.bundleId || `${app.name}#${app.pid}`;
        let item = this.rows.get(id);
        if (!item) {
          item = global.document.createElement("li");
          const name = global.document.createElement("span");
          name.className = "app-name";
          const figures = global.document.createElement("span");
          figures.className = "app-figures";
          const bar = global.document.createElement("i");
          bar.className = "app-bar";
          item.append(name, figures, bar);
          // Fades in once; the class goes, or every new list (which re-inserts the rows) would fade it in again.
          if (!still) {
            item.classList.add("enter");
            item.addEventListener("animationend", () => item.classList.remove("enter"), { once: true });
          }
        }
        item.classList.toggle("dim", !app.quittable);
        item.children[0].textContent = app.name;
        item.children[1].textContent = `${this.format.percent(app.cpu)} · ${this.format.memory(app.mem)}`;
        // On the CPU list the bar and the figures turn red as an app fills two cores.
        const level = key === "cpu" ? heat.level(this.limits.app, app.cpu) ?? 0 : 0;
        const color = heat.color(key === "cpu" ? metrics.colors.cpu : metrics.colors.ram, level);
        item.children[1].style.color = level > 0.02 ? heat.css(heat.mix(color, this.white, 0.15)) : "";
        item.children[2].style.backgroundColor = heat.css(color);
        item.children[2].style.width = `${Math.max(2, ((app[key] || 0) / top) * 100).toFixed(1)}%`;
        rows.set(id, item);
        return item;
      });
      list.replaceChildren(...items);
      this.rows = rows;
      if (still) return;
      for (const [id, item] of rows) {
        const old = before.get(id);
        if (old === undefined) continue;
        const delta = old - item.getBoundingClientRect().top;
        if (Math.abs(delta) < 1) continue;
        item.style.transition = "none";
        item.style.transform = `translateY(${delta}px)`;
        item.getBoundingClientRect();
        item.style.transition = "";
        item.style.transform = "";
      }
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.View = View;
})(typeof window !== "undefined" ? window : globalThis);
