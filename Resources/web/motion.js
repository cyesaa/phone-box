// How things move (design §8 "Görünüm ve hareket"): values glide to each new snapshot, and one
// requestAnimationFrame loop draws everything. `ease`, `between`, `Glide`, `Timeline` and `Pace` are pure and tested in
// JavaScriptCore.
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

  /// The Mac's clock as the graph sees it. Snapshots carry the Mac's time `t`, come once a second and arrive after a
  /// delay that varies (an iPhone on Wi-Fi gets them in bursts). The graph is drawn one snapshot period plus the
  /// spread of the last `size` delays (+100 ms, 150 ms–1.5 s) behind the quickest arrival, so the newest value is
  /// always still coming in from the right and a late one is already there when its turn comes. A change in that lag
  /// is eased in at no more than 10 % of real time: the clock never stops, steps or runs backwards. Only when it is
  /// more than 3 s off (the page was asleep) does it jump.
  class Timeline {
    constructor(size = 20) {
      this.size = size;
      this.offsets = [];
      /// [page time, Mac time] of the last answer.
      this.shown = null;
    }

    /// A snapshot with the Mac's time `t` arrived at page time `now` (both in ms).
    arrived(t, now) {
      const offset = t - now;
      // The Mac's clock jumped (set by hand, a long sleep) or the page was asleep: start over.
      if (this.offsets.length && Math.abs(offset - this.offsets[this.offsets.length - 1]) > 5000) {
        this.offsets = [];
        this.shown = null;
      }
      this.offsets.push(offset);
      if (this.offsets.length > this.size) this.offsets.shift();
    }

    /// The Mac time (ms) to draw at page time `now`; null before the first snapshot. Called once a frame.
    at(now) {
      if (!this.offsets.length) return null;
      const quickest = Math.max(...this.offsets);
      const spread = quickest - Math.min(...this.offsets);
      const target = now + quickest - 1000 - Math.min(1500, Math.max(150, spread + 100));
      let mac = target;
      if (this.shown) {
        const elapsed = Math.max(0, now - this.shown[0]);
        const natural = this.shown[1] + elapsed;
        const room = 0.1 * elapsed;
        if (Math.abs(target - natural) <= 3000) mac = natural + Math.max(-room, Math.min(room, target - natural));
      }
      this.shown = [now, mac];
      return mac;
    }
  }

  /// Which animation frames draw everything: each one, or once every `every` ms while nothing should move or nothing
  /// is seen (`slow`: stale values, or the dashboard behind the Claude page or the Start screen). The first frame after
  /// `slow` changes, or after `soon()`, is drawn at once.
  class Pace {
    constructor(every = 1000) {
      this.every = every;
      this.slow = false;
      this.last = -Infinity;
    }

    soon() {
      this.last = -Infinity;
    }

    /// True when the frame at `now` (ms) draws everything.
    due(now, slow) {
      if (slow !== this.slow) {
        this.slow = slow;
        this.last = -Infinity;
      }
      if (slow && now - this.last < this.every) return false;
      this.last = now;
      return true;
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
  global.PhoneBox.motion = { ease, between, Glide, Timeline, Pace, onFrame, reduced };
})(typeof window !== "undefined" ? window : globalThis);
