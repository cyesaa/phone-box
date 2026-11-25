// PhoneBox dashboard (Plan 2: CPU and RAM; Plan 3A: the other metrics and the app list as plain rows).
// Design §5 (protocol), §6 (metrics), §8 (keep-awake, states).
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
      noData: "Mac şu an veri göndermiyor.",
      start: "Başlat",
      startNote: "Dokunduğunda ekran açık kalır. Telefonda çalan müzik durmaz.",
      memory: (used, total) => `${used} / ${total} GB`,
      load: (value) => `Yük ${value}`,
      gpu: "GPU",
      temp: "Sıcaklık",
      power: "Güç",
      net: "Ağ",
      disk: "Disk",
      battery: "Pil",
      apps: "En çok kullananlar",
      hottest: (value) => `en yüksek ${value} °C`,
      gpuPower: "GPU",
      systemPower: "Mac'in tamamı",
      free: (free, total) => `${free} / ${total} GB boş`,
      diskSpeed: (read, write) => `okuma ${read} · yazma ${write}`,
      charging: "şarj oluyor",
      untilEmpty: (time) => `${time} kaldı`,
      untilFull: (time) => `dolmasına ${time}`,
      duration: (hours, minutes) => (hours ? `${hours} sa ` : "") + `${minutes} dk`,
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
      noData: "The Mac is not sending data right now.",
      start: "Start",
      startNote: "Once you tap, the screen stays on. Music playing on the phone keeps playing.",
      memory: (used, total) => `${used} / ${total} GB`,
      load: (value) => `Load ${value}`,
      gpu: "GPU",
      temp: "Temperature",
      power: "Power",
      net: "Network",
      disk: "Disk",
      battery: "Battery",
      apps: "Top apps",
      hottest: (value) => `hottest ${value} °C`,
      gpuPower: "GPU",
      systemPower: "whole Mac",
      free: (free, total) => `${free} of ${total} GB free`,
      diskSpeed: (read, write) => `read ${read} · write ${write}`,
      charging: "charging",
      untilEmpty: (time) => `${time} left`,
      untilFull: (time) => `${time} to full`,
      duration: (hours, minutes) => (hours ? `${hours} h ` : "") + `${minutes} min`,
    },
  };
  const language = (navigator.language || "en").toLowerCase().startsWith("tr") ? "tr" : "en";
  const t = TEXT[language];
  const number = new Intl.NumberFormat(language, { maximumFractionDigits: 1, minimumFractionDigits: 1 });
  const whole = new Intl.NumberFormat(language, { maximumFractionDigits: 0 });
  const $ = (id) => document.getElementById(id);
  document.documentElement.lang = language;
  for (const element of document.querySelectorAll("[data-text]")) element.textContent = t[element.dataset.text];

  // The key comes from the personal link's fragment (#k=…), or from localStorage on later visits (design §5).
  function readKey() {
    const fromLink = new URLSearchParams(location.hash.slice(1)).get("k");
    const decode = (text) => {
      try {
        const bytes = text ? PBCrypto.base64UrlToBytes(text) : null;
        return bytes && bytes.length === 32 ? bytes : null;
      } catch (error) {
        return null;
      }
    };
    const linkBytes = decode(fromLink);
    if (linkBytes) {
      try {
        localStorage.setItem("phonebox-key", fromLink);
      } catch (error) {}
      return linkBytes;
    }
    let stored = null;
    try {
      stored = localStorage.getItem("phonebox-key");
    } catch (error) {}
    return decode(stored);
  }

  const key = readKey();
  const state = {
    socket: null, retries: 0, started: false, stopped: false, nonce: null,
    receivedAt: 0, lastMessageAt: 0, socketOpenedAt: 0, access: null, accessSetAt: 0,
  };

  function setStatus(kind, text) {
    $("status").className = "status " + kind;
    $("status-text").textContent = text;
  }

  function showMessage(text) {
    $("message").textContent = text || "";
    $("message").hidden = !text;
  }

  function setStale(stale) {
    for (const id of ["metrics", "details", "apps"]) $(id).classList.toggle("stale", stale);
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
    return video.play();
  }

  // Chrome does not fire visibilitychange when the phone is unlocked, and WebKit pauses media while the
  // page is hidden, so check every few seconds (spike).
  setInterval(() => {
    if (state.started && document.visibilityState === "visible" && video.paused) keepAwake().catch(() => {});
    replaceStaleSocket();
    if (key) connect();
  }, 3000);

  $("start-button").textContent = t.start;
  $("start-note").textContent = t.startNote;
  $("start").addEventListener("click", () => {
    keepAwake().then(
      () => {
        state.started = true;
        $("start").hidden = true;
      },
      () => {
        $("start").hidden = false;
      }
    );
  });

  // ---- Connection.
  function send(message) {
    if (state.socket && state.socket.readyState === WebSocket.OPEN) state.socket.send(JSON.stringify(message));
  }

  function connect() {
    if (state.stopped || document.visibilityState !== "visible" || (state.socket && state.socket.readyState <= WebSocket.OPEN)) return;
    if (!state.receivedAt) setStatus("", t.connecting);
    const socket = new WebSocket(`ws://${location.host}/ws`);
    state.socket = socket;
    state.lastMessageAt = Date.now();
    state.socketOpenedAt = Date.now();
    socket.onmessage = (event) => {
      state.lastMessageAt = Date.now();
      try {
        handle(JSON.parse(event.data));
      } catch (error) {}
    };
    socket.onclose = (event) => {
      if (state.socket === socket) state.socket = null;
      setStale(true);
      if (event.code === 4001) {
        state.stopped = true;
        $("start").hidden = true;
        setStatus("offline", t.unpaired);
        showMessage(t.badKey);
        return;
      }
      if (event.code === 4003) {
        // Authentication did not arrive in time: retryable, not a bad key.
        setStatus("", t.connecting);
        setTimeout(connect, 1000);
        return;
      }
      if (event.code === 4002) {
        // Not a failure (the Mac asked for a fresh connection); a short pause keeps repeats from spinning.
        setTimeout(connect, 250);
        return;
      }
      // A close while the page is hidden (phone locked) is not a failure; the page reconnects on return.
      if (document.visibilityState === "visible") state.retries += 1;
      if (state.retries >= 3) {
        setStatus("offline", t.offline);
        showMessage(t.unreachable);
      } else {
        setStatus("", t.connecting);
      }
      setTimeout(connect, [1000, 2000, 5000][Math.min(Math.max(state.retries, 1) - 1, 2)]);
    };
  }

  // After lock/sleep iOS can leave a socket that reports OPEN but delivers nothing. While the Mac is streaming
  // (snapshots arrive every second or so), silence for 5 s means the socket is dead: replace it right away.
  function replaceStaleSocket() {
    if (document.visibilityState !== "visible") return;
    const socket = state.socket;
    if (!socket || socket.readyState !== WebSocket.OPEN) return;
    if (!(state.access && state.access.streaming)) {
      // Not streaming (e.g. first connected over Wi-Fi, or before the USB link came up): try again every ~10 s
      // so the phone moves to the cable without a reload.
      if (state.access && Date.now() - state.accessSetAt >= 10000) replaceSocket();
      return;
    }
    if (Date.now() - state.lastMessageAt <= 5000) return;
    replaceSocket();
  }

  function replaceSocket() {
    const socket = state.socket;
    if (!socket) return connect();
    state.accessSetAt = Date.now();
    socket.onmessage = null;
    socket.onclose = null;
    try {
      socket.close();
    } catch (error) {}
    state.socket = null;
    setStale(true);
    connect();
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
    state.access = access;
    state.accessSetAt = Date.now();
    if (access.streaming) {
      setStatus("connected", t.connected);
      showMessage("");
    } else if (access.reason === "not-on-cable") {
      setStatus("cable", t.cable);
      setStale(true);
      showMessage(t.notOnCable);
    } else {
      setStatus("offline", t.noData);
      setStale(true);
      showMessage(t.noData);
    }
  }

  function render(snapshot) {
    state.receivedAt = Date.now();
    setStale(false);
    if (snapshot.cpu) {
      setRing("cpu", snapshot.cpu.total);
      $("cpu-value").textContent = Math.round(snapshot.cpu.total) + "%";
      const load = snapshot.cpu.load;
      $("cpu-detail").textContent = load && load.length ? t.load(number.format(load[0])) : "";
    }
    if (snapshot.mem) {
      const valid = snapshot.mem.total > 0;
      const percent = valid ? (snapshot.mem.used / snapshot.mem.total) * 100 : 0;
      setRing("ram", percent);
      $("ram-value").textContent = valid ? Math.round(percent) + "%" : "—";
      const gb = (bytes) => number.format(bytes / 1073741824);
      $("ram-detail").textContent = t.memory(gb(snapshot.mem.used), gb(snapshot.mem.total));
    }
    renderDetails(snapshot);
    if (snapshot.apps) renderApps(snapshot.apps);
  }

  // ---- Plan 3A rows. A missing metric shows "—".
  function setRow(id, value, sub) {
    $(id + "-value").textContent = value == null ? "—" : value;
    $(id + "-sub").textContent = value == null || !sub ? "" : sub;
  }

  function speed(bytesPerSecond) {
    if (bytesPerSecond == null) return "—";
    if (bytesPerSecond >= 1e6) return number.format(bytesPerSecond / 1e6) + " MB/s";
    if (bytesPerSecond >= 1e3) return whole.format(bytesPerSecond / 1e3) + " KB/s";
    return whole.format(bytesPerSecond) + " B/s";
  }

  function duration(minutes) {
    return t.duration(Math.floor(minutes / 60), minutes % 60);
  }

  function renderDetails(snapshot) {
    const gpu = snapshot.gpu;
    setRow("gpu", gpu ? Math.round(gpu.util) + "%" : null);

    const temp = snapshot.temp;
    setRow("temp", temp ? number.format(temp.avg) + " °C" : null,
           temp && temp.max - temp.avg >= 1 ? t.hottest(number.format(temp.max)) : "");

    const power = snapshot.power;
    if (power && power.system != null) setRow("power", number.format(power.system) + " W", t.systemPower);
    else if (power && power.gpu != null) setRow("power", number.format(power.gpu) + " W", t.gpuPower);
    else setRow("power", null);

    const net = snapshot.net;
    setRow("net", net ? `↓ ${speed(net.rx)} · ↑ ${speed(net.tx)}` : null, net ? net.iface : "");

    const disk = snapshot.disk;
    const gb = (bytes) => number.format(bytes / 1e9);
    setRow("disk", disk ? t.free(gb(disk.free), gb(disk.total)) : null,
           disk && (disk.read != null || disk.write != null) ? t.diskSpeed(speed(disk.read), speed(disk.write)) : "");

    const battery = snapshot.battery;
    let batterySub = "";
    if (battery && battery.minutesLeft != null) {
      batterySub = battery.charging ? t.untilFull(duration(battery.minutesLeft)) : t.untilEmpty(duration(battery.minutesLeft));
    } else if (battery && battery.charging) {
      batterySub = t.charging;
    }
    setRow("battery", battery ? battery.percent + "%" + (battery.charging ? " ⚡" : "") : null, batterySub);
  }

  function renderApps(apps) {
    const list = $("app-list");
    const sorted = apps.slice().sort((a, b) => b.cpu - a.cpu || b.mem - a.mem);
    list.replaceChildren(...sorted.map((app) => {
      const item = document.createElement("li");
      const cells = [
        ["app-name", app.name],
        ["app-cpu", number.format(app.cpu) + "%"],
        ["app-mem", app.mem >= 1e9 ? number.format(app.mem / 1e9) + " GB" : whole.format(app.mem / 1e6) + " MB"],
      ];
      for (const [className, text] of cells) {
        const cell = document.createElement("span");
        cell.className = className;
        cell.textContent = text;
        item.append(cell);
      }
      return item;
    }));
  }

  function setRing(id, percent) {
    document.querySelector(`#${id} .ring`).style.setProperty("--p", Math.max(0, Math.min(100, percent)).toFixed(1));
  }

  // Reconnect right away when the page comes back (spike: iOS drops the socket 10–15 s after locking).
  for (const name of ["visibilitychange", "pageshow", "focus"]) {
    window.addEventListener(name, () => {
      if (document.visibilityState !== "visible") return;
      // The three events often fire together; a socket opened less than 1 s ago is kept.
      if (Date.now() - state.socketOpenedAt >= 1000) {
        if (state.access && !state.access.streaming && state.socket) replaceSocket();
        else replaceStaleSocket();
      }
      connect();
    });
  }
  window.addEventListener("hashchange", () => location.reload());

  if (!key) {
    $("start").hidden = true;
    setStatus("offline", t.unpaired);
    showMessage(t.noKey);
    return;
  }
  connect();
})();
