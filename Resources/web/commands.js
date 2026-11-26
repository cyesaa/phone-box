// The page's commands to the Mac (design §5, §7): each one numbered and signed with the pairing key, its answer
// (`ack`) matched back to it, at most 9 sent in any second, and the volume slider held to 4 values a second. Pure: the
// connection, the clock and the timers come in from outside, so the Swift tests run it in JavaScriptCore with fakes.
(function (global) {
  "use strict";

  /// A command with no answer after this long counts as failed (the socket may have dropped on the way).
  const answerWithin = 5000;
  /// The Mac closes a socket on the 11th command within one second; the page sends at most this many, one short of
  /// the Mac's 10, so a little network jitter cannot bunch them over it.
  const perSecond = 9;

  /// A clock that only moves forward (the wall clock can jump). JavaScriptCore, where the tests run, has no
  /// `performance`.
  const monotonic = () => (typeof global.performance !== "undefined" ? global.performance.now() : Date.now());

  class Commands {
    /// `link`: `key` (the pairing key's bytes), `nonce()` (the authenticated socket's nonce, or null) and
    /// `send(message)` (true when it went out). `options.later(fn, ms)` replaces `setTimeout` and `options.now()`
    /// the clock in tests.
    constructor(link, options = {}) {
      this.link = link;
      this.later = options.later || ((fn, ms) => global.setTimeout(fn, ms));
      this.now = options.now || monotonic;
      this.seq = 0;
      this.pending = new Map();
      /// When each command of the last second went out.
      this.sentAt = [];
    }

    /// Commands can go out: the socket is authenticated.
    canSend() {
      return this.link.nonce() !== null;
    }

    /// Sends `name` with `args` (an object). `done(result)` gets "ok", the ack's error ("not-allowed",
    /// "app-changed", "unsupported", "failed"), or "failed" when it could not go out, 9 already went out in the last
    /// second, or no answer came in 5 s. Returns the command's number, or 0 when it did not go out.
    run(name, args, done) {
      const nonce = this.link.nonce();
      const now = this.now();
      this.sentAt = this.sentAt.filter((at) => now - at < 1000);
      if (nonce === null || this.sentAt.length >= perSecond) {
        if (done) done("failed");
        return 0;
      }
      const text = JSON.stringify(args || {});
      // Numbers only grow, also across reconnects: the Mac wants them strictly increasing on each socket.
      const seq = this.seq + 1;
      const message = {
        v: 1, type: "cmd", seq, name, args: text,
        mac: global.PBCrypto.hmacHex(this.link.key, `cmd:${nonce}:${seq}:${name}:${text}`),
      };
      if (!this.link.send(message)) {
        if (done) done("failed");
        return 0;
      }
      this.seq = seq;
      this.sentAt.push(now);
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
  /// slider sends at most 4 a second, then its final value when let go (design §7). Letting go sends at once, but never
  /// sooner than half an interval after the previous value: the Mac closes a socket that sends more than 10 commands a
  /// second.
  class Throttle {
    constructor(interval, send, options = {}) {
      this.interval = interval;
      this.send = send;
      this.now = options.now || monotonic;
      this.later = options.later || ((fn, ms) => global.setTimeout(fn, ms));
      this.sentAt = -Infinity;
      /// The timer set last, by number, and when it goes off; a send voids every timer set before it.
      this.timer = 0;
      this.dueAt = null;
      this.value = undefined;
      this.sent = undefined;
    }

    /// A new drag: the value sent last is forgotten, since the Mac's volume may have changed since.
    reset() {
      this.sent = undefined;
    }

    push(value) {
      this.value = value;
      this.after(this.interval);
    }

    /// Let go: the last value goes out now, or half an interval after the previous one, unless it already has.
    flush() {
      this.after(this.interval / 2);
    }

    /// Sends the value once `gap` ms have passed since the previous send: at once if they have, otherwise from a timer
    /// (an earlier one already set stays).
    after(gap) {
      const now = this.now();
      const wait = this.sentAt + gap - now;
      if (wait <= 0) {
        this.fire();
        return;
      }
      if (this.dueAt !== null && this.dueAt <= now + wait) return;
      const timer = ++this.timer;
      this.dueAt = now + wait;
      this.later(() => {
        if (timer === this.timer) this.fire();
      }, wait);
    }

    fire() {
      this.timer += 1;
      this.dueAt = null;
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
