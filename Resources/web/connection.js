// The WebSocket to the Mac (design §5): pairing key, authentication, reconnection and dead-socket detection.
// It reports what the page should show through `handlers`; it never touches the page itself.
(function (global) {
  "use strict";

  /// The key from the personal link's fragment (#k=…), else from localStorage on later visits.
  function readKey() {
    const decode = (text) => {
      try {
        const bytes = text ? global.PBCrypto.base64UrlToBytes(text) : null;
        return bytes && bytes.length === 32 ? bytes : null;
      } catch (error) {
        return null;
      }
    };
    const fromLink = new URLSearchParams(global.location.hash.slice(1)).get("k");
    const linkBytes = decode(fromLink);
    if (linkBytes) {
      try {
        global.localStorage.setItem("phonebox-key", fromLink);
      } catch (error) {}
      return linkBytes;
    }
    let stored = null;
    try {
      stored = global.localStorage.getItem("phonebox-key");
    } catch (error) {}
    return decode(stored);
  }

  const retryDelays = [1000, 2000, 5000];
  /// A snapshot is due every second; without one for this long the values are stale.
  const staleAfter = 3000;
  /// Silence for this long while streaming means the socket is dead (iOS keeps such sockets "open" after a lock).
  const deadAfter = 5000;
  /// Not streaming (e.g. on Wi-Fi in cable mode): reconnect this often so the phone moves to the cable by itself.
  const recheckAfter = 10000;
  /// iOS can leave an attempt to an unreachable Mac (asleep, Wi-Fi changed) "connecting" for tens of seconds.
  const connectTimeout = 5000;

  /// handlers: onState(kind) with kind "connecting" | "streaming" | "cable" | "offline" | "unpaired" | "nodata";
  /// onStale(stale); onReady({host, mode, access}); onAccess(access); onSnapshot(snapshot); onAck(ack).
  class Connection {
    constructor(key, handlers) {
      this.key = key;
      this.handlers = handlers;
      this.socket = null;
      this.nonce = null;
      this.retries = 0;
      this.stopped = false;
      this.access = null;
      this.accessSetAt = 0;
      this.lastMessageAt = 0;
      this.lastSnapshotAt = 0;
      this.openedAt = 0;
      this.nextAttemptAt = 0;
      this.stale = true;
      this.state = null;
    }

    /// Tells the page what to show and remembers it.
    emit(kind) {
      this.state = kind;
      this.handlers.onState(kind);
    }

    start() {
      global.setInterval(() => this.tick(), 1000);
      for (const name of ["visibilitychange", "pageshow", "focus"]) global.addEventListener(name, () => this.resume());
      this.connect();
    }

    /// True when the message went out on an open socket.
    send(message) {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return false;
      this.socket.send(JSON.stringify(message));
      return true;
    }

    visible() {
      return global.document.visibilityState === "visible";
    }

    // Every second: mark stale values, replace a dead socket, and reconnect once the back-off delay has passed.
    tick() {
      if (this.stopped) return;
      if (this.access && this.access.streaming && Date.now() - this.lastSnapshotAt > staleAfter) this.setStale(true);
      this.replaceIfDead();
      if (Date.now() >= this.nextAttemptAt) this.connect();
    }

    // The page came back (unlock, tab switch): check the socket at once instead of waiting for the back-off.
    resume() {
      if (this.stopped || !this.visible()) return;
      // The three events often fire together; a socket opened less than 1 s ago is kept.
      if (Date.now() - this.openedAt >= 1000) {
        if (this.access && !this.access.streaming && this.socket) this.replace();
        else this.replaceIfDead();
      }
      this.nextAttemptAt = 0;
      this.connect();
    }

    connect() {
      if (this.stopped || !this.visible()) return;
      if (this.socket && this.socket.readyState <= WebSocket.OPEN) return;
      // A reconnect while the page shows "plug in the cable" or "no data" keeps that card instead of flashing it.
      if (!this.lastSnapshotAt && this.state !== "cable" && this.state !== "nodata") this.emit("connecting");
      const socket = new WebSocket(`ws://${global.location.host}/ws`);
      this.socket = socket;
      this.lastMessageAt = Date.now();
      this.openedAt = Date.now();
      socket.onmessage = (event) => {
        this.lastMessageAt = Date.now();
        let message;
        try {
          message = JSON.parse(event.data);
        } catch (error) {
          return;
        }
        this.handle(message);
      };
      socket.onclose = (event) => this.closed(socket, event.code);
    }

    retryIn(delay) {
      this.nextAttemptAt = Date.now() + delay;
      global.setTimeout(() => {
        if (Date.now() >= this.nextAttemptAt) this.connect();
      }, delay);
    }

    closed(socket, code) {
      if (this.socket === socket) this.socket = null;
      this.setStale(true);
      if (code === 4001) {
        // Wrong key or a pairing reset: retrying cannot help.
        this.stopped = true;
        this.emit("unpaired");
        return;
      }
      if (code === 4003) {
        // Authentication came too late (e.g. the phone was locked): retry, it is not a bad key.
        this.emit("connecting");
        this.retryIn(1000);
        return;
      }
      if (code === 4002) {
        // The Mac asked for a fresh connection (an iPhone was plugged in); a short pause keeps repeats from spinning.
        this.retryIn(250);
        return;
      }
      // A close while the page is hidden (phone locked) is not a failure; the page reconnects when it returns.
      if (this.visible()) this.retries += 1;
      this.emit(this.retries >= 3 ? "offline" : "connecting");
      this.retryIn(retryDelays[Math.min(Math.max(this.retries, 1), retryDelays.length) - 1]);
    }

    replaceIfDead() {
      if (!this.visible()) return;
      const socket = this.socket;
      if (socket && socket.readyState === WebSocket.CONNECTING && Date.now() - this.openedAt > connectTimeout) {
        socket.onmessage = null;
        socket.onclose = null;
        try {
          socket.close();
        } catch (error) {}
        this.closed(socket, 1006);
        return;
      }
      if (!socket || socket.readyState !== WebSocket.OPEN) return;
      if (!(this.access && this.access.streaming)) {
        if (this.access && Date.now() - this.accessSetAt >= recheckAfter) this.replace();
        return;
      }
      if (Date.now() - this.lastMessageAt > deadAfter) this.replace();
    }

    replace() {
      const socket = this.socket;
      this.accessSetAt = Date.now();
      if (socket) {
        socket.onmessage = null;
        socket.onclose = null;
        try {
          socket.close();
        } catch (error) {}
      }
      this.socket = null;
      this.setStale(true);
      this.nextAttemptAt = 0;
      this.connect();
    }

    handle(message) {
      switch (message.type) {
        case "hello":
          this.nonce = message.nonce;
          this.send({ v: 1, type: "auth", mac: global.PBCrypto.hmacHex(this.key, "auth:" + message.nonce) });
          break;
        case "ready":
          this.retries = 0;
          if (this.handlers.onReady) this.handlers.onReady(message);
          this.applyAccess(message.access);
          break;
        case "access":
          this.applyAccess(message);
          break;
        case "snapshot":
          this.lastSnapshotAt = Date.now();
          this.setStale(false);
          this.handlers.onSnapshot(message);
          break;
        case "ack":
          if (this.handlers.onAck) this.handlers.onAck(message);
          break;
      }
    }

    applyAccess(access) {
      if (!access) return;
      this.access = access;
      this.accessSetAt = Date.now();
      this.handlers.onAccess(access);
      if (access.streaming) {
        this.emit("streaming");
      } else {
        this.setStale(true);
        this.emit(access.reason === "not-on-cable" ? "cable" : "nodata");
      }
    }

    setStale(stale) {
      if (stale === this.stale) return;
      this.stale = stale;
      this.handlers.onStale(stale);
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.readKey = readKey;
  global.PhoneBox.Connection = Connection;
})(typeof window !== "undefined" ? window : globalThis);
