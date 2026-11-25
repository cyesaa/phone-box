// Turning red near a limit (design §8 "Sınıra yaklaşınca kızarma"): the limits, the level 0…1, the colour along
// path B (ocean → blue → violet → pink → red) and the alarm rule. Pure, so it is tested in JavaScriptCore.
(function (global) {
  "use strict";

  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const finite = (value) => typeof value === "number" && Number.isFinite(value);

  /// [starts turning red, fully red] for each metric; `power` is the pair the Mac sent in `ready.limits`. A limit
  /// below its start means lower is worse (free disk space in bytes, the battery when it is not on power).
  function limits(power) {
    const ok = Array.isArray(power) && power.length === 2 && power.every(finite) && power[0] < power[1];
    return {
      // RAM goes by macOS's memory pressure (0 normal, 1 warning, 2 critical), not by how full memory is: macOS keeps
      // memory full on purpose, and an 8 GB Mac sits at 85–95 % with no trouble.
      cpu: [40, 95], ram: [0, 2], gpu: [40, 95], temp: [60, 95], power: ok ? power.slice() : [15, 35],
      net: [10e6, 100e6], disk: [30e9, 5e9], battery: [30, 10], app: [60, 200],
    };
  }

  /// 0 below the start, 1 at or past the limit, straight in between; null for a missing value.
  function level(range, value) {
    if (!range || !finite(value)) return null;
    return clamp((value - range[0]) / (range[1] - range[0]), 0, 1);
  }

  // ---- Colour: OKLCH keeps the in-between colours vivid (an RGB blend of blue and red goes grey).
  const toLinear = (channel) => {
    const c = channel / 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  };
  const toByte = (linear) => {
    const c = linear <= 0.0031308 ? 12.92 * linear : 1.055 * Math.pow(linear, 1 / 2.4) - 0.055;
    return Math.round(clamp(c, 0, 1) * 255);
  };

  function rgb(hex) {
    const value = parseInt(hex.slice(1), 16);
    return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
  }

  /// [lightness 0…1, chroma, hue in degrees 0…360).
  function oklch(color) {
    const [r, g, b] = color.map(toLinear);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
    const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
    const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
    return [L, Math.hypot(A, B), ((Math.atan2(B, A) * 180) / Math.PI + 360) % 360];
  }

  function linearFromOklab(L, A, B) {
    const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
    const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
    const s = Math.pow(L - 0.0894841775 * A - 1.291485548 * B, 3);
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s];
  }

  /// An OKLCH colour as RGB; a colour the screen cannot show loses chroma until it can.
  function fromOklch(L, C, hue) {
    const angle = (hue * Math.PI) / 180;
    const at = (chroma) => linearFromOklab(L, chroma * Math.cos(angle), chroma * Math.sin(angle));
    const inside = (linear) => linear.every((value) => value >= -0.0005 && value <= 1.0005);
    let linear = at(C);
    if (!inside(linear)) {
      let low = 0;
      let high = C;
      for (let step = 0; step < 16; step += 1) {
        const middle = (low + high) / 2;
        if (inside(at(middle))) low = middle;
        else high = middle;
      }
      linear = at(low);
    }
    return linear.map(toByte);
  }

  const hot = "#ff2d2d";
  const hotLight = "#ff8a7a";
  const cache = new Map();

  /// `hex` at heat `level`, as [r, g, b]. The hue turns upwards (blue, violet, pink) until it reaches red; `light`
  /// is the bright end of a ring and ends at a light red. The level is eased at both ends and rounded to 1/100.
  function color(hex, heatLevel, light) {
    const level = clamp(finite(heatLevel) ? heatLevel : 0, 0, 1);
    const t = Math.round(level * level * (3 - 2 * level) * 100) / 100;
    const target = light ? hotLight : hot;
    if (t === 0) return rgb(hex);
    if (t === 1) return rgb(target);
    const key = `${hex}|${target}|${t}`;
    let result = cache.get(key);
    if (!result) {
      const [L0, C0, h0] = oklch(rgb(hex));
      const [L1, C1, h1] = oklch(rgb(target));
      let turn = h1 - h0;
      while (turn < 0) turn += 360;
      // A little more chroma half way keeps violet and pink from looking washed out.
      result = fromOklch(L0 + (L1 - L0) * t, C0 + (C1 - C0) * t + Math.sin(Math.PI * t) * 0.05, h0 + turn * t);
      cache.set(key, result);
    }
    return result;
  }

  const css = (color, alpha = 1) => `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${alpha})`;
  const mix = (a, b, t) => a.map((value, index) => Math.round(value + (b[index] - value) * t));

  /// The alarm (design §8): a metric rings after `rounds` snapshots in a row at or past its limit and stops after
  /// `rounds` in a row below 0.9. A missing value, or one that does not turn red (the battery on power), counts as
  /// calm. A one-second spike never rings; the colour shows it anyway. After `loudFor` ms a ringing alarm goes quiet
  /// (no beat, no edge light; the metric stays red), and so does the faint light of a metric that stays near its
  /// limit: a value that stays bad must not light the screen's edge for ever.
  class Alarm {
    constructor(rounds = 3, loudFor = 120000) {
      this.rounds = rounds;
      this.loudFor = loudFor;
      this.counts = {};
      this.ringing = new Set();
      /// When each ringing metric started ringing, and when each metric went past 0.7 (page time, ms).
      this.since = {};
      this.nearSince = {};
    }

    /// `levels` maps each metric to its level or null, arrived at page time `now`; returns the metrics that just
    /// started ringing.
    update(levels, now = 0) {
      const started = [];
      for (const metric of Object.keys(levels)) {
        const value = levels[metric];
        const count = this.counts[metric] || { over: 0, under: 0 };
        count.over = value !== null && value >= 1 ? count.over + 1 : 0;
        count.under = value === null || value < 0.9 ? count.under + 1 : 0;
        this.counts[metric] = count;
        if (value !== null && value > 0.7) {
          if (this.nearSince[metric] === undefined) this.nearSince[metric] = now;
        } else {
          delete this.nearSince[metric];
        }
        if (!this.ringing.has(metric) && count.over >= this.rounds) {
          this.ringing.add(metric);
          this.since[metric] = now;
          started.push(metric);
        } else if (this.ringing.has(metric) && count.under >= this.rounds) {
          this.ringing.delete(metric);
          delete this.since[metric];
        }
      }
      return started;
    }

    /// The ringing metrics, in the order they started.
    active() {
      return Array.from(this.ringing);
    }

    /// The ringing metrics that started less than `loudFor` ago: they still beat and light the edge.
    loud(now) {
      return this.active().filter((metric) => now - this.since[metric] < this.loudFor);
    }

    /// The metrics near their limit (level past 0.7) for less than `loudFor`: they may light the edge faintly.
    near(now) {
      return Object.keys(this.nearSince).filter((metric) => now - this.nearSince[metric] < this.loudFor);
    }

    /// The values went stale: nothing rings.
    clear() {
      this.counts = {};
      this.ringing.clear();
      this.since = {};
      this.nearSince = {};
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.heat = { limits, level, color, css, mix, rgb, oklch, Alarm, hot };
})(typeof window !== "undefined" ? window : globalThis);
