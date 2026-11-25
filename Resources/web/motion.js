// How things move (design §8 "Görünüm ve hareket"): values glide to each new snapshot, and one
// requestAnimationFrame loop draws everything. `ease`, `between` and `Glide` are pure and tested in JavaScriptCore.
(function (global) {
  "use strict";

  /// Starts fast and slows to a stop.
  const ease = (x) => 1 - Math.pow(1 - Math.max(0, Math.min(1, x)), 3);

  /// A snapshot part way (`t` 0…1) from `from` to `to`: a number found at the same place in both is blended,
  /// anything else is `to`'s. Arrays (cores, load, apps) are taken as they are.
  function between(from, to, t) {
    if (typeof to === "number") {
      return typeof from === "number" && Number.isFinite(from) && Number.isFinite(to) ? from + (to - from) * t : to;
    }
    if (!to || typeof to !== "object" || Array.isArray(to)) return to;
    const source = from && typeof from === "object" && !Array.isArray(from) ? from : {};
    const result = {};
    for (const key of Object.keys(to)) result[key] = between(source[key], to[key], t);
    return result;
  }

  /// The values on screen: each new snapshot is reached in `duration` ms, starting from what is shown, so a snapshot
  /// that arrives mid-way does not make a value jump.
  class Glide {
    constructor(duration = 900) {
      this.duration = duration;
      this.from = null;
      this.to = null;
      this.start = 0;
    }

    push(snapshot, now) {
      this.from = this.to ? this.at(now) : snapshot;
      this.to = snapshot;
      this.start = now;
    }

    /// The snapshot to show at `now`; null before the first one.
    at(now) {
      if (!this.to) return null;
      const t = ease((now - this.start) / this.duration);
      return t >= 1 ? this.to : between(this.from, this.to, t);
    }
  }

  // One loop for every drawing. The browser stops it while the page is hidden (phone locked, other tab).
  const tasks = [];
  let running = false;

  let failed = false;

  // The next frame is asked for first, and each task runs on its own: one that throws must not stop every
  // animation for good (the page would freeze while its dot still says it is live).
  function frame(now) {
    global.requestAnimationFrame(frame);
    for (const task of tasks) {
      try {
        task(now);
      } catch (error) {
        // Once, not sixty times a second.
        if (!failed && global.console) global.console.error(error);
        failed = true;
      }
    }
  }

  /// Calls `task(now)` on every frame.
  function onFrame(task) {
    tasks.push(task);
    if (running || !global.requestAnimationFrame) return;
    running = true;
    global.requestAnimationFrame(frame);
  }

  /// "Reduce Motion" is on: no shine, pulse, rolling digits or sliding rows; colours and numbers still change.
  // Asked once; the browser keeps `matches` up to date when the setting changes.
  const reduceMotion = global.matchMedia ? global.matchMedia("(prefers-reduced-motion: reduce)") : null;

  function reduced() {
    return Boolean(reduceMotion && reduceMotion.matches);
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.motion = { ease, between, Glide, onFrame, reduced };
})(typeof window !== "undefined" ? window : globalThis);
