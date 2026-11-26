// The page's commands to the Mac (design §5, §7): each one numbered and signed with the pairing key, its answer
// (`ack`) matched back to it, and the volume slider held to 4 values a second. Pure: the connection, the clock and the
// timers come in from outside, so the Swift tests run it in JavaScriptCore with fakes.
(function (global) {
  "use strict";

  /// A command with no answer after this long counts as failed (the socket may have dropped on the way).
  const answerWithin = 5000;

  class Commands {
    /// `link`: `key` (the pairing key's bytes), `nonce()` (the authenticated socket's nonce, or null) and
    /// `send(message)` (true when it went out). `options.later(fn, ms)` replaces `setTimeout` in tests.
    constructor(link, options = {}) {
      this.link = link;
      this.later = options.later || ((fn, ms) => global.setTimeout(fn, ms));
      this.seq = 0;
      this.pending = new Map();
    }

    /// Sends `name` with `args` (an object). `done(result)` gets "ok", the ack's error ("not-allowed",
    /// "app-changed", "unsupported", "failed"), or "failed" when it could not go out or no answer came in 5 s.
    /// Returns the command's number, or 0 when it did not go out.
    run(name, args, done) {
      const nonce = this.link.nonce();
      const text = JSON.stringify(args || {});
      // Numbers only grow, also across reconnects: the Mac wants them strictly increasing on each socket.
      const seq = this.seq + 1;
      const message = {
        v: 1, type: "cmd", seq, name, args: text,
        mac: global.PBCrypto.hmacHex(this.link.key, `cmd:${nonce}:${seq}:${name}:${text}`),
      };
      if (nonce === null || !this.link.send(message)) {
        if (done) done("failed");
        return 0;
      }
      this.seq = seq;
      this.pending.set(seq, done || null);
      this.later(() => this.settle(seq, "failed"), answerWithin);
      return seq;
    }

    /// The Mac's `ack`; one for a command that already timed out is ignored.
    acked(ack) {
      this.settle(ack.seq, ack.ok ? "ok" : String(ack.error || "failed"));
    }

    settle(seq, result) {
      if (!this.pending.has(seq)) return;
      const done = this.pending.get(seq);
      this.pending.delete(seq);
      if (done) done(result);
    }
  }

  /// At most one value every `interval` ms while a control is dragged, and the last value always goes out: the volume
  /// slider sends at most 4 a second, then its final value when let go (design §7).
  class Throttle {
    constructor(interval, send, options = {}) {
      this.interval = interval;
      this.send = send;
      this.now = options.now || (() => Date.now());
      this.later = options.later || ((fn, ms) => global.setTimeout(fn, ms));
      this.sentAt = -Infinity;
      this.waiting = false;
      this.value = undefined;
      this.sent = undefined;
    }

    push(value) {
      this.value = value;
      const wait = this.sentAt + this.interval - this.now();
      if (wait <= 0) {
        this.fire();
      } else if (!this.waiting) {
        this.waiting = true;
        this.later(() => {
          this.waiting = false;
          this.fire();
        }, wait);
      }
    }

    /// Let go: the last value goes out now, unless it already has.
    flush() {
      this.fire();
    }

    fire() {
      if (this.value === this.sent) return;
      this.sentAt = this.now();
      this.sent = this.value;
      this.send(this.value);
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.Commands = Commands;
  global.PhoneBox.Throttle = Throttle;
})(typeof window !== "undefined" ? window : globalThis);
