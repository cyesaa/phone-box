// PhoneBox dashboard: wires the connection, the history and the view together (design §8 "Sayfa kodu"). A page that
// cannot start (a script did not load, or the start failed) says the Mac cannot be reached and loads itself again.
(function (global) {
  "use strict";

  const PB = global.PhoneBox;
  const $ = (id) => global.document.getElementById(id);
  /// One part from each script in index.html but this one (sha256.js puts its own on `PBCrypto`).
  const parts = ["fullScreenHeight", "i18n", "format", "claude", "History", "metrics", "heat", "motion", "rings",
                 "clock", "chart", "Connection", "Commands", "View", "ClaudeView", "ui", "Controls"];
  /// How many times this tab has reloaded a page that could not start (sessionStorage outlives a reload).
  const reloadsKey = "phonebox-reloads";
  /// The wait before each of those reloads: a few seconds at first, then longer, so that a page that keeps failing
  /// reloads at most once a minute.
  const reloadDelays = [5000, 15000, 30000, 60000];
  /// While the Mac does not answer it is asked again this often: a reload then would end on the browser's error page,
  /// which never tries again (a Home Screen web app has no reload button).
  const askEvery = 5000;

  function start() {
    const { t, language } = PB.i18n;
    const format = PB.format(language);
    const view = new PB.View(t, format);
    // The Claude Code page below the dashboard (design §14); its header shows the dashboard clock's time.
    const pager = new PB.claude.Pager();
    const claudeView = new PB.ClaudeView(t, pager, view.clock);
    // 60 s on screen, plus 3 s that scroll out past the left edge (the graph runs a second or two behind the Mac).
    const history = new PB.History(63);
    const buildTag = global.document.querySelector('meta[name="phonebox-build"]');
    const builds = new PB.BuildWatch(buildTag && buildTag.getAttribute("content"));
    const selectedKey = "phonebox-metric";

    global.document.documentElement.lang = language;
    view.fillTexts();

    // The metric in the graph: CPU at first, then the last one chosen.
    let selected = "cpu";
    try {
      const saved = global.localStorage.getItem(selectedKey);
      if (PB.metrics.order.includes(saved)) selected = saved;
    } catch (error) {}
    view.select(selected);

    for (const element of global.document.querySelectorAll(".ring-button, .tile")) {
      element.addEventListener("click", () => {
        view.switchTo(element.dataset.metric, history);
        try {
          global.localStorage.setItem(selectedKey, element.dataset.metric);
        } catch (error) {}
      });
    }
    $("app-sort").addEventListener("click", () => view.toggleSort());
    global.addEventListener("resize", () => {
      view.renderGraph(history);
      view.renderApps();
      view.fitTiles();
    });
    global.addEventListener("hashchange", () => global.location.reload());
    view.renderApps();
    view.renderGraph(history);
    // Behind the Claude page or the Start screen the dashboard is drawn once a second (view.js).
    PB.motion.onFrame((now) => view.frame(now, claudeView.covers(now) || PB.ui.covers()));
    PB.motion.onFrame(() => claudeView.frame());

    const key = PB.readKey();
    PB.ui.setup(t, Boolean(key));
    if (!key) {
      view.setState("nokey");
      return;
    }

    // Commands go through the authenticated socket; `connection` is set below, before anything can be tapped.
    const commands = new PB.Commands({
      key,
      nonce: () => (connection.ready ? connection.nonce : null),
      send: (message) => connection.send(message),
    });
    const controls = new PB.Controls(t, format, commands);

    const connection = new PB.Connection(key, {
      onState: (kind) => {
        if (kind === "unpaired") PB.ui.stopKeepAwake();
        view.setState(kind);
      },
      onStale: (stale) => {
        view.setStale(stale);
        claudeView.setStale(stale);
      },
      onReady: (ready) => {
        // PhoneBox was updated while this page stayed open: load its new files (the page then asks for "Start" again).
        if (builds.changed(ready.build)) {
          global.location.reload();
          return;
        }
        view.setHost(ready.host);
        view.setLimits(ready.limits && ready.limits.power);
      },
      onAccess: (access) => {
        view.setAccess(access);
        controls.setAccess(access);
      },
      onSnapshot: (snapshot) => {
        history.push(snapshot.t, PB.metrics.values(snapshot));
        view.render(snapshot, global.performance.now());
        view.renderGraph(history);
        controls.setSnapshot(snapshot);
        // `claude` comes only while the feature is on; the page moves by itself when a session starts waiting and
        // when, having come by itself, nothing has waited for 3 s.
        claudeView.render(snapshot.claude, snapshot.t);
        const move = pager.update(snapshot.claude, snapshot.t);
        if (move) claudeView.show(move === "open" ? "claude" : "dashboard");
      },
      onAck: (ack) => commands.acked(ack),
    });
    $("app-list").addEventListener("click", (event) => {
      const row = event.target.closest("li");
      if (row) controls.openApp(view.appAt(row.dataset.id));
    });
    connection.start();
    PB.connection = connection;
    PB.controls = controls;
  }

  /// The page cannot work: a script did not load (a Wi-Fi blip, the Mac going to sleep while the page loaded) or the
  /// start threw. It shows the offline card and, after a wait, loads itself again once the Mac answers.
  function recover() {
    // i18n.js may be the script that is missing: then the same texts as its stateOffline and stateOfflineText.
    const turkish = String((global.navigator && global.navigator.language) || "").toLowerCase().startsWith("tr");
    const texts = PB && PB.i18n ? PB.i18n.t : turkish
      ? { stateOffline: "Mac'e ulaşılamıyor",
          stateOfflineText: "PhoneBox açık mı, telefon kabloyla takılı ya da aynı Wi-Fi'de mi? "
            + "Arka planda yeniden deneniyor." }
      : { stateOffline: "Cannot reach the Mac",
          stateOfflineText: "Is PhoneBox running, and is the phone plugged in or on the same Wi-Fi? "
            + "Retrying in the background." };
    $("state-title").textContent = texts.stateOffline;
    $("state-text").textContent = texts.stateOfflineText;
    $("state").hidden = false;
    $("status").className = "status problem";
    $("status-text").textContent = texts.stateOffline;
    // Nothing covers the card, and nothing asks for a tap that would keep the screen on.
    $("start").hidden = true;
    $("guide").hidden = true;
    let reloads;
    try {
      reloads = Number(global.sessionStorage.getItem(reloadsKey)) || 0;
    } catch (error) {
      // Without the count every reload would come soon: wait the longest.
      reloads = reloadDelays.length - 1;
    }
    const ask = () => {
      global.fetch("/", { cache: "no-store" }).then((response) => response.ok, () => false).then((answered) => {
        if (!answered) {
          global.setTimeout(ask, askEvery);
          return;
        }
        try {
          global.sessionStorage.setItem(reloadsKey, String(reloads + 1));
        } catch (error) {}
        global.location.reload();
      });
    };
    global.setTimeout(ask, reloadDelays[Math.min(reloads, reloadDelays.length - 1)]);
  }

  if (!PB || !global.PBCrypto || parts.some((part) => !PB[part])) {
    recover();
    return;
  }
  try {
    start();
  } catch (error) {
    if (global.console) global.console.error(error);
    recover();
    return;
  }
  // It started: a later failure waits the shortest time again.
  try {
    global.sessionStorage.removeItem(reloadsKey);
  } catch (error) {}
})(window);
