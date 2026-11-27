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

  /// Every wait and silence here is timed with a clock that only moves forward: the phone's wall clock can be set back,
  /// which would stall retrying and hide a dead socket for as long as the step. JavaScriptCore, where the tests run,
  /// has no `performance` of its own. WebKit's clock stops while the phone sleeps, so the time the page was away is
  /// told by the wall clock (`resume`).
  const monotonic = () => (typeof global.performance !== "undefined" ? global.performance.now() : Date.now());

  const retryDelays = [1000, 2000, 5000];
  /// A snapshot is due every second; without one for this long the values are stale.
  const staleAfter = 3000;
  /// Silence for this long while streaming means the socket is dead (iOS keeps such sockets "open" after a lock).
  const deadAfter = 5000;
  /// Not streaming (e.g. on Wi-Fi in cable mode): reconnect this often so the phone moves to the cable by itself.
  const recheckAfter = 10000;
  /// A socket that has not finished authenticating by then is given up and counts as a failed attempt: iOS can leave
  /// an attempt to an unreachable Mac (asleep, Wi-Fi changed) "connecting" for tens of seconds, and a socket can open
  /// without the Mac ever answering. (The Mac itself closes an unauthenticated socket after 5 s with 4003.)
  const readyTimeout = 6000;

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
      /// `Date.now()` when the page was hidden; null while it shows.
      this.hiddenAt = null;
      /// This socket finished authentication (`ready` arrived); only then may the page send its own messages.
      this.ready = false;
    }

    /// Tells the page what to show and remembers it.
    emit(kind) {
      this.state = kind;
      this.handlers.onState(kind);
    }

    start() {
      global.setInterval(() => this.tick(), 1000);
      global.addEventListener("visibilitychange", () => this.hidden());
      for (const name of ["visibilitychange", "pageshow", "focus"]) global.addEventListener(name, () => this.resume());
      this.connect();
    }

    /// For the page's own messages (Plan 4B's commands): only on an authenticated socket. A command sent before
    /// `auth` would make the Mac close with 4001, which the page must treat as a wrong key.
    send(message) {
      return this.ready && this.transmit(message);
    }

    /// True when the message went out on an open socket.
    transmit(message) {
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
      if (this.access && this.access.streaming && monotonic() - this.lastSnapshotAt > staleAfter) this.setStale(true);
      this.replaceIfDead();
      if (monotonic() >= this.nextAttemptAt) this.connect();
    }

    hidden() {
      if (!this.visible() && this.hiddenAt === null) this.hiddenAt = Date.now();
    }

    // The page came back (unlock, tab switch): check the socket at once instead of waiting for the back-off.
    resume() {
      if (this.stopped || !this.visible()) return;
      // Away longer than a dead socket's silence (or the wall clock was set back meanwhile): the phone may have slept,
      // which the page's own clock does not count, so the socket's last message only looks recent.
      const away = this.hiddenAt === null ? 0 : Date.now() - this.hiddenAt;
      this.hiddenAt = null;
      if (this.socket && (away > deadAfter || away < 0)) {
        this.replace();
      } else if (monotonic() - this.openedAt >= 1000) {
        // The three events often fire together; a socket opened less than 1 s ago is kept.
        if (this.access && !this.access.streaming && this.socket) this.replace();
        else this.replaceIfDead();
      }
      this.nextAttemptAt = 0;
      this.connect();
    }

    connect() {
      if (this.stopped || !this.visible()) return;
      if (this.socket && this.socket.readyState <= WebSocket.OPEN) return;
      // Only the very first attempt says "connecting" here; after that `closed()` decides, so the cable, no-data and
      // offline cards stay up while the page retries instead of flashing.
      if (this.state === null) this.emit("connecting");
      const socket = new WebSocket(`ws://${global.location.host}/ws`);
      this.socket = socket;
      this.ready = false;
      this.access = null;
      this.lastMessageAt = monotonic();
      this.openedAt = monotonic();
      socket.onmessage = (event) => {
        this.lastMessageAt = monotonic();
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
      this.nextAttemptAt = monotonic() + delay;
      global.setTimeout(() => {
        if (monotonic() >= this.nextAttemptAt) this.connect();
      }, delay);
    }

    closed(socket, code) {
      // A socket that is no longer the current one (the page opened the next while this one was closing) has nothing
      // to say about the live one: its late close changes nothing.
      if (this.socket !== socket) return;
      this.socket = null;
      this.ready = false;
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
      if (!socket) return;
      if (!this.ready) {
        if (socket.readyState <= WebSocket.OPEN && monotonic() - this.openedAt > readyTimeout) {
          socket.onmessage = null;
          socket.onclose = null;
          try {
            socket.close();
          } catch (error) {}
          this.closed(socket, 1006);
        }
        return;
      }
      if (socket.readyState !== WebSocket.OPEN) return;
      if (!(this.access && this.access.streaming)) {
        if (this.access && monotonic() - this.accessSetAt >= recheckAfter) this.replace();
        return;
      }
      if (monotonic() - this.lastMessageAt > deadAfter) this.replace();
    }

    replace() {
      const socket = this.socket;
      this.accessSetAt = monotonic();
      if (socket) {
        socket.onmessage = null;
        socket.onclose = null;
        try {
          socket.close();
        } catch (error) {}
      }
      this.socket = null;
      this.ready = false;
      this.setStale(true);
      this.nextAttemptAt = 0;
      this.connect();
    }

    handle(message) {
      switch (message.type) {
        case "hello":
          this.nonce = message.nonce;
          this.transmit({ v: 1, type: "auth", mac: global.PBCrypto.hmacHex(this.key, "auth:" + message.nonce) });
          break;
        case "ready":
          this.ready = true;
          this.retries = 0;
          if (this.handlers.onReady) this.handlers.onReady(message);
          this.applyAccess(message.access);
          break;
        case "access":
          this.applyAccess(message);
          break;
        case "snapshot":
          this.lastSnapshotAt = monotonic();
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
      this.accessSetAt = monotonic();
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

  /// Remembers which PhoneBox files the page runs: the build the Mac stamped into index.html, else the `build` of the
  /// first `ready`. A `ready` that names other files means PhoneBox was updated while the page stayed open, or between
  /// serving the page and its first `ready`: the page has to load the new ones.
  class BuildWatch {
    /// `own`: the build from index.html; empty or missing when the Mac did not stamp one.
    constructor(own) {
      // The same rule as WebBuild.stamp: twelve lowercase hex digits; anything else counts as no own build.
      this.build = typeof own === "string" && /^[0-9a-f]{12}$/.test(own) ? own : null;
    }

    /// True when the page should reload. A `ready` without a build (an older Mac side) changes nothing.
    changed(build) {
      if (typeof build !== "string" || build === "") return false;
      if (this.build === null) {
        this.build = build;
        return false;
      }
      return build !== this.build;
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.readKey = readKey;
  global.PhoneBox.Connection = Connection;
  global.PhoneBox.BuildWatch = BuildWatch;
})(typeof window !== "undefined" ? window : globalThis);
