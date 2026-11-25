// Puts the Mac's data on the page (design §8): rings, tiles, the graph and its header, the app list, the now-playing
// card, the status line and the state card. Text always goes in with textContent: names come from other apps.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  const metrics = () => global.PhoneBox.metrics;

  class View {
    constructor(t, format) {
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

    render(snapshot) {
      this.snapshot = snapshot;
      const { cpu, mem } = snapshot;
      const f = this.format;
      const t = this.t;
      this.ring("cpu", cpu ? cpu.total : null, cpu && cpu.load && cpu.load.length ? t.load(f.decimal(cpu.load[0])) : "");
      const memoryOK = mem && mem.total > 0;
      this.ring("ram", memoryOK ? (mem.used / mem.total) * 100 : null,
                memoryOK ? t.memory(f.gibibytes(mem.used), f.gibibytes(mem.total)) : "");
      for (const metric of ["gpu", "temp", "power", "net", "disk", "battery"]) {
        $(metric + "-tile").textContent = metrics().tile(metric, snapshot, f);
      }
      this.renderHeader();
      const playingBefore = !$("now-playing").hidden;
      this.renderNowPlaying(snapshot.media);
      if (snapshot.apps) this.apps = snapshot.apps;
      // A new app list arrives every 3 s; the card appearing or going changes how many rows fit.
      if (snapshot.apps || playingBefore !== !$("now-playing").hidden) this.renderApps();
    }

    ring(metric, percent, sub) {
      const ok = typeof percent === "number" && Number.isFinite(percent);
      const ring = global.document.querySelector(`.ring-button[data-metric="${metric}"] .ring`);
      ring.style.setProperty("--p", ok ? Math.max(0, Math.min(100, percent)).toFixed(1) : "0");
      $(metric + "-ring").textContent = this.format.percent(ok ? percent : null);
      $(metric + "-sub").textContent = sub;
    }

    select(metric) {
      this.selected = metric;
      for (const element of global.document.querySelectorAll(".ring-button, .tile")) {
        element.classList.toggle("selected", element.dataset.metric === metric);
      }
      global.document.querySelector(".graph").dataset.metric = metric;
      this.renderHeader();
    }

    renderHeader() {
      const { value, detail } = metrics().header(this.selected, this.snapshot, this.format, this.t);
      $("graph-title").textContent = `${this.t.metric[this.selected]} · ${this.t.lastMinute}`;
      $("graph-value").textContent = value;
      $("graph-detail").textContent = detail;
    }

    renderGraph(history) {
      const m = metrics();
      const lines = m.lines(this.selected).map((line) => Object.assign({}, line, { values: history.series(line.key) }));
      const range = global.PhoneBox.chart.range(m.scale(this.selected), lines.map((line) => line.values));
      global.PhoneBox.chart.draw($("graph"), lines, range, m.axisLabel(this.selected, range, this.format));
    }

    renderNowPlaying(media) {
      $("now-playing").hidden = !media;
      if (!media) return;
      $("np-title").textContent = media.title;
      $("np-sub").textContent = media.artist ? `${media.artist} · ${media.app}` : media.app;
    }

    toggleSort() {
      this.sortBy = this.sortBy === "cpu" ? "mem" : "cpu";
      this.renderApps();
    }

    // Only as many rows as fit without cutting one off; grey rows are apps the phone cannot quit.
    renderApps() {
      $("app-sort").textContent = (this.sortBy === "cpu" ? "CPU" : "RAM") + " ▾";
      const list = $("app-list");
      if (!this.apps) {
        list.replaceChildren();
        return;
      }
      const key = this.sortBy;
      const other = key === "cpu" ? "mem" : "cpu";
      const sorted = this.apps.slice().sort((a, b) => b[key] - a[key] || b[other] - a[other] || String(a.name).localeCompare(String(b.name)));
      const rowHeight = parseFloat(global.getComputedStyle(list).getPropertyValue("--row")) || 34;
      const fits = Math.max(1, Math.floor((list.clientHeight + 1) / rowHeight));
      list.replaceChildren(...sorted.slice(0, fits).map((app) => {
        const item = global.document.createElement("li");
        if (!app.quittable) item.className = "dim";
        const name = global.document.createElement("span");
        name.className = "app-name";
        name.textContent = app.name;
        const figures = global.document.createElement("span");
        figures.className = "app-figures";
        figures.textContent = `${this.format.percent(app.cpu)} · ${this.format.memory(app.mem)}`;
        item.append(name, figures);
        return item;
      }));
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.View = View;
})(typeof window !== "undefined" ? window : globalThis);
