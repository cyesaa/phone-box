// PhoneBox dashboard: wires the connection, the history and the view together (design §8 "Sayfa kodu").
(function (global) {
  "use strict";

  const PB = global.PhoneBox;
  const $ = (id) => global.document.getElementById(id);
  const { t, language } = PB.i18n;
  const format = PB.format(language);
  const view = new PB.View(t, format);
  // 60 s on screen, plus 3 s that scroll out past the left edge (the graph runs a second or two behind the Mac).
  const history = new PB.History(63);
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
  PB.motion.onFrame((now) => view.frame(now));

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
      if (kind === "unpaired") PB.ui.hideStart();
      view.setState(kind);
    },
    onStale: (stale) => view.setStale(stale),
    onReady: (ready) => {
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
    },
    onAck: (ack) => commands.acked(ack),
  });
  connection.start();
  PB.connection = connection;
  PB.controls = controls;
})(window);
