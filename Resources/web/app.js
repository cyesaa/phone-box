// PhoneBox dashboard: wires the connection, the history and the view together (design §8 "Sayfa kodu").
(function (global) {
  "use strict";

  const PB = global.PhoneBox;
  const $ = (id) => global.document.getElementById(id);
  const { t, language } = PB.i18n;
  const format = PB.format(language);
  const view = new PB.View(t, format);
  const history = new PB.History(60);
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
      view.select(element.dataset.metric);
      view.renderGraph(history);
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

  const key = PB.readKey();
  PB.ui.setup(t, Boolean(key));
  if (!key) {
    view.setState("nokey");
    return;
  }

  const connection = new PB.Connection(key, {
    onState: (kind) => {
      if (kind === "unpaired") PB.ui.hideStart();
      view.setState(kind);
    },
    onStale: (stale) => view.setStale(stale),
    onReady: (ready) => view.setHost(ready.host),
    onAccess: (access) => view.setAccess(access),
    onSnapshot: (snapshot) => {
      history.push(snapshot.t, PB.metrics.values(snapshot));
      view.render(snapshot);
      view.renderGraph(history);
    },
  });
  connection.start();
  PB.connection = connection;
})(window);
