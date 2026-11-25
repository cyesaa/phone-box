// PhoneBox dashboard (Plan 2: CPU and RAM). Design §5 (protocol), §8 (keep-awake, states).
(function () {
  "use strict";

  const TEXT = {
    tr: {
      connecting: "Bağlanıyor…",
      connected: "Bağlı",
      cable: "Kabloyu tak",
      offline: "Mac'e ulaşılamıyor",
      unpaired: "Eşleşmedi",
      noKey: "Bu sayfanın anahtarı yok. iPhone'u Mac'e kabloyla tak ve Mac'te çıkan QR kodunu okut.",
      badKey: "Eşleştirme geçersiz. iPhone'u Mac'e kabloyla tak ve QR kodunu yeniden okut.",
      notOnCable: "Bu telefon Wi-Fi üzerinden bağlı. Veri için iPhone'u Mac'e kabloyla tak.",
      unreachable: "Mac'e ulaşılamıyor. PhoneBox açık mı, telefon kabloyla takılı ya da aynı Wi-Fi'de mi?",
      start: "Başlat",
      startNote: "Dokunduğunda ekran açık kalır. Telefonda çalan müzik durmaz.",
      memory: (used, total) => `${used} / ${total} GB`,
      load: (value) => `Yük ${value}`,
    },
    en: {
      connecting: "Connecting…",
      connected: "Connected",
      cable: "Plug in the cable",
      offline: "Cannot reach the Mac",
      unpaired: "Not paired",
      noKey: "This page has no key. Plug the iPhone into the Mac and scan the QR code the Mac shows.",
      badKey: "Pairing is no longer valid. Plug the iPhone into the Mac and scan the QR code again.",
      notOnCable: "This phone is connected over Wi-Fi. Plug the iPhone into the Mac to see data.",
      unreachable: "Cannot reach the Mac. Is PhoneBox running, and is the phone plugged in or on the same Wi-Fi?",
      start: "Start",
      startNote: "Once you tap, the screen stays on. Music playing on the phone keeps playing.",
      memory: (used, total) => `${used} / ${total} GB`,
      load: (value) => `Load ${value}`,
    },
  };
  const language = (navigator.language || "en").toLowerCase().startsWith("tr") ? "tr" : "en";
  const t = TEXT[language];
  const number = new Intl.NumberFormat(language, { maximumFractionDigits: 1, minimumFractionDigits: 1 });
  const $ = (id) => document.getElementById(id);
  document.documentElement.lang = language;

  // The key comes from the personal link's fragment (#k=…), or from localStorage on later visits (design §5).
  function readKey() {
    const fromLink = new URLSearchParams(location.hash.slice(1)).get("k");
    let stored = null;
    try {
      if (fromLink) localStorage.setItem("phonebox-key", fromLink);
      stored = localStorage.getItem("phonebox-key");
    } catch (error) {}
    const text = fromLink || stored;
    const bytes = text ? PBCrypto.base64UrlToBytes(text) : null;
    return bytes && bytes.length === 32 ? bytes : null;
  }

  const key = readKey();
  const state = { socket: null, retries: 0, started: false, stopped: false, nonce: null, receivedAt: 0 };

  function setStatus(kind, text) {
    $("status").className = "status " + kind;
    $("status-text").textContent = text;
  }

  function showMessage(text) {
    $("message").textContent = text || "";
    $("message").hidden = !text;
  }

  function setStale(stale) {
    $("metrics").classList.toggle("stale", stale);
  }

  // ---- Keep the screen on (spike V4): an unmuted, silent video that never loops, in an "ambient" audio
  // session so music on the phone keeps playing. WebKit lets the screen sleep for anything else.
  const video = $("keepawake");
  video.addEventListener("timeupdate", () => {
    if (video.currentTime > 0.5) video.currentTime = Math.random() * 0.4;
  });

  function keepAwake() {
    try {
      if (navigator.audioSession) navigator.audioSession.type = "ambient";
    } catch (error) {}
    video.muted = false;
    video.loop = false;
    return video.play().catch(() => {});
  }

  // Chrome does not fire visibilitychange when the phone is unlocked, and WebKit pauses media while the
  // page is hidden, so check every few seconds (spike).
  setInterval(() => {
    if (state.started && document.visibilityState === "visible" && video.paused) keepAwake();
  }, 3000);

  $("start-button").textContent = t.start;
  $("start-note").textContent = t.startNote;
  $("start").addEventListener("click", () => {
    state.started = true;
    $("start").hidden = true;
    keepAwake();
  });

  // ---- Connection.
  function send(message) {
    if (state.socket && state.socket.readyState === WebSocket.OPEN) state.socket.send(JSON.stringify(message));
  }

  function connect() {
    if (state.stopped || (state.socket && state.socket.readyState <= WebSocket.OPEN)) return;
    if (!state.receivedAt) setStatus("", t.connecting);
    const socket = new WebSocket(`ws://${location.host}/ws`);
    state.socket = socket;
    socket.onmessage = (event) => handle(JSON.parse(event.data));
    socket.onclose = (event) => {
      if (state.socket === socket) state.socket = null;
      setStale(true);
      if (event.code === 4001) {
        state.stopped = true;
        setStatus("offline", t.unpaired);
        showMessage(t.badKey);
        return;
      }
      state.retries += 1;
      if (state.retries >= 3) {
        setStatus("offline", t.offline);
        showMessage(t.unreachable);
      } else {
        setStatus("", t.connecting);
      }
      const delay = event.code === 4002 ? 0 : [1000, 2000, 5000][Math.min(state.retries - 1, 2)];
      setTimeout(connect, delay);
    };
  }

  function handle(message) {
    switch (message.type) {
      case "hello":
        state.nonce = message.nonce;
        send({ v: 1, type: "auth", mac: PBCrypto.hmacHex(key, "auth:" + message.nonce) });
        break;
      case "ready":
        state.retries = 0;
        applyAccess(message.access);
        break;
      case "access":
        applyAccess(message);
        break;
      case "snapshot":
        render(message);
        break;
    }
  }

  function applyAccess(access) {
    if (access.streaming) {
      setStatus("connected", t.connected);
      showMessage("");
    } else if (access.reason === "not-on-cable") {
      setStatus("cable", t.cable);
      setStale(true);
      showMessage(t.notOnCable);
    }
  }

  function render(snapshot) {
    state.receivedAt = Date.now();
    setStale(false);
    if (snapshot.cpu) {
      setRing("cpu", snapshot.cpu.total);
      $("cpu-value").textContent = Math.round(snapshot.cpu.total) + "%";
      $("cpu-detail").textContent = snapshot.cpu.load.length ? t.load(number.format(snapshot.cpu.load[0])) : "";
    }
    if (snapshot.mem) {
      const percent = (snapshot.mem.used / snapshot.mem.total) * 100;
      setRing("ram", percent);
      $("ram-value").textContent = Math.round(percent) + "%";
      const gb = (bytes) => number.format(bytes / 1073741824);
      $("ram-detail").textContent = t.memory(gb(snapshot.mem.used), gb(snapshot.mem.total));
    }
  }

  function setRing(id, percent) {
    document.querySelector(`#${id} .ring`).style.setProperty("--p", Math.max(0, Math.min(100, percent)).toFixed(1));
  }

  // Reconnect right away when the page comes back (spike: iOS drops the socket 10–15 s after locking).
  for (const name of ["visibilitychange", "pageshow", "focus"]) {
    window.addEventListener(name, () => {
      if (document.visibilityState === "visible") connect();
    });
  }

  if (!key) {
    $("start").hidden = true;
    setStatus("offline", t.unpaired);
    showMessage(t.noKey);
    return;
  }
  connect();
})();
