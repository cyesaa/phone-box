// The graph's last 60 seconds, kept only in the phone's memory (design §8 "Grafik"). One slot per second of the Mac's
// clock; a second without a snapshot stays empty, so the line shows a gap instead of a made-up value.
(function (global) {
  "use strict";

  class History {
    constructor(seconds = 60) {
      this.seconds = seconds;
      this.samples = new Map();
      this.latest = null;
    }

    /// `time` is the snapshot's `t` (milliseconds); `values` maps a series key to a number or null.
    push(time, values) {
      const second = Math.floor(time / 1000);
      // The Mac's clock jumped (set by hand, or a long sleep): start over rather than draw nonsense.
      if (this.latest !== null && (second <= this.latest - this.seconds || second > this.latest + 3600)) this.clear();
      if (this.latest === null || second > this.latest) this.latest = second;
      this.samples.set(second, values);
      for (const key of this.samples.keys()) {
        if (key <= this.latest - this.seconds) this.samples.delete(key);
      }
    }

    /// `seconds` values, oldest first, ending at the newest second; null where nothing (or nothing finite) arrived.
    series(key) {
      const values = [];
      for (let index = this.seconds - 1; index >= 0; index -= 1) {
        const sample = this.latest === null ? undefined : this.samples.get(this.latest - index);
        const value = sample ? sample[key] : null;
        values.push(typeof value === "number" && Number.isFinite(value) ? value : null);
      }
      return values;
    }

    clear() {
      this.samples.clear();
      this.latest = null;
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.History = History;
})(typeof window !== "undefined" ? window : globalThis);
