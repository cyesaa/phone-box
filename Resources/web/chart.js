// The 60-second graph on a <canvas> (design §8 "Grafik", "Görünüm ve hareket"). `range` is pure and tested; `draw`
// runs on every animation frame and is checked by eye.
(function (global) {
  "use strict";

  /// The smallest 1, 2 or 5 × 10ⁿ that is at least `value` (1 for nothing positive).
  function niceCeil(value) {
    if (!(value > 0) || !Number.isFinite(value)) return 1;
    const power = 10 ** Math.floor(Math.log10(value));
    for (const step of [1, 2, 5, 10]) {
      if (value <= step * power * (1 + 1e-9)) return step * power;
    }
    return 10 * power;
  }

  /// The vertical range: "percent" is 0…100; "temperature" spans at least 20 °C around the values in steps of 5;
  /// "fromZero" starts at 0 and ends at a round number above the largest value.
  function range(kind, seriesList) {
    if (kind === "percent") return { min: 0, max: 100 };
    const values = [].concat(...seriesList).filter((value) => value !== null);
    if (kind === "temperature") {
      if (!values.length) return { min: 30, max: 60 };
      const min = Math.max(0, Math.floor(Math.min(...values) / 5) * 5 - 5);
      const max = Math.max(Math.ceil(Math.max(...values) / 5) * 5 + 5, min + 20);
      return { min, max };
    }
    return { min: 0, max: niceCeil(Math.max(0, ...values) * 1.1) };
  }

  /// A smooth line through `points` (midpoint curves), as the current path.
  function trace(g, points) {
    g.moveTo(points[0][0], points[0][1]);
    for (let index = 1; index < points.length - 1; index += 1) {
      const [x, y] = points[index];
      g.quadraticCurveTo(x, y, (x + points[index + 1][0]) / 2, (y + points[index + 1][1]) / 2);
    }
    const last = points[points.length - 1];
    g.lineTo(last[0], last[1]);
  }

  /// Draws `lines` ([{values, color, width, fill, alpha}]) scaled to `bounds` on a canvas `width`×`height` CSS
  /// pixels. `options`:
  /// - `label`: the top of the axis, at the top left;
  /// - `shift`: how many seconds the graph's clock is past the newest value. Negative while that value is still
  ///   coming in from the right; the line is cut where it crosses the right edge, so it scrolls in evenly;
  /// - `span`: how many seconds fill the width (default: all the values); older values are drawn past the left edge;
  /// - `heat(color, value)`: the colour at the height of `value`, as [r, g, b], or null for plain colours;
  /// - `limit` {value, label}: the dashed red line where the metric is fully red;
  /// - `now`, `still`: the pulse on the newest point (none with "Reduce Motion"); `glow` 0…1 makes it an alarm.
  function draw(canvas, width, height, lines, bounds, options) {
    if (!width || !height) return;
    const heat = global.PhoneBox.heat;
    const ratio = Math.min(global.devicePixelRatio || 1, 3);
    if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
    }
    const g = canvas.getContext("2d");
    g.setTransform(ratio, 0, 0, ratio, 0, 0);
    g.clearRect(0, 0, width, height);

    g.strokeStyle = "rgba(109, 138, 163, 0.25)";
    g.lineWidth = 1;
    g.setLineDash([3, 4]);
    g.beginPath();
    g.moveTo(0, Math.round(height / 2) + 0.5);
    g.lineTo(width, Math.round(height / 2) + 0.5);
    g.stroke();
    g.setLineDash([]);

    if (options.label) {
      g.fillStyle = "#6d8aa3";
      g.font = "10px -apple-system, system-ui, sans-serif";
      g.textBaseline = "top";
      g.fillText(options.label, 0, 0);
    }

    const pad = 4;
    const span = bounds.max - bounds.min || 1;
    const y = (value) => pad + (1 - (Math.min(Math.max(value, bounds.min), bounds.max) - bounds.min) / span) * (height - 2 * pad);

    const limit = options.limit;
    if (limit && limit.value >= bounds.min && limit.value <= bounds.max) {
      const red = heat.rgb(heat.hot);
      const ly = Math.round(y(limit.value)) + 0.5;
      g.strokeStyle = heat.css(red, 0.5);
      g.setLineDash([4, 4]);
      g.beginPath();
      g.moveTo(0, ly);
      g.lineTo(width, ly);
      g.stroke();
      g.setLineDash([]);
      g.fillStyle = heat.css(red, 0.8);
      g.font = "600 9px -apple-system, system-ui, sans-serif";
      g.textBaseline = ly > 14 ? "bottom" : "top";
      g.fillText(limit.label, width - g.measureText(limit.label).width - 2, ly > 14 ? ly - 3 : ly + 3);
    }

    const shift = options.shift || 0;
    let head = null;
    lines.forEach((line, lineIndex) => {
      const values = line.values;
      const count = values.length;
      const span = options.span || count - 1;
      const x = (index) => (count <= 1 ? width : ((index - (count - 1 - span) - shift) / span) * width);
      const runs = [];
      let run = [];
      // The value at the line's last drawn point, for the head's colour.
      let end = null;
      for (let index = 0; index < count; index += 1) {
        const value = values[index];
        if (value === null) {
          if (run.length) runs.push(run);
          run = [];
          end = null;
          continue;
        }
        const point = [x(index), y(value)];
        // A value still on its way in from the right: the line ends where it crosses the edge.
        if (point[0] > width) {
          if (run.length) {
            const [px, py] = run[run.length - 1];
            const part = (width - px) / (point[0] - px);
            run.push([width, py + (point[1] - py) * part]);
            end += (value - end) * part;
          }
          break;
        }
        run.push(point);
        end = value;
      }
      if (run.length) runs.push(run);

      // Each height takes the colour of its own value, so peaks near the limit are red.
      const base = heat.rgb(line.color);
      const stroke = g.createLinearGradient(0, 0, 0, height);
      const area = g.createLinearGradient(0, 0, 0, height);
      for (let step = 12; step >= 0; step -= 1) {
        const value = bounds.min + (span * step) / 12;
        const position = Math.max(0, Math.min(1, y(value) / height));
        const color = options.heat ? options.heat(line.color, value) || base : base;
        stroke.addColorStop(position, heat.css(color));
        area.addColorStop(position, heat.css(color, 0.35 * (1 - position)));
      }

      g.globalAlpha = line.alpha ?? 1;
      for (const points of runs) {
        if (points.length === 1) {
          g.fillStyle = stroke;
          g.beginPath();
          g.arc(points[0][0], points[0][1], line.width, 0, Math.PI * 2);
          g.fill();
          continue;
        }
        if (line.fill) {
          g.fillStyle = area;
          g.beginPath();
          trace(g, points);
          g.lineTo(points[points.length - 1][0], height);
          g.lineTo(points[0][0], height);
          g.closePath();
          g.fill();
        }
        g.strokeStyle = stroke;
        g.lineWidth = line.width;
        g.lineJoin = "round";
        g.lineCap = "round";
        g.beginPath();
        trace(g, points);
        g.stroke();
      }
      g.globalAlpha = 1;
      if (lineIndex === 0 && end !== null && runs.length) {
        const newest = runs[runs.length - 1];
        head = { point: newest[newest.length - 1], color: options.heat ? options.heat(line.color, end) || base : base };
      }
    });

    // The newest point of the main line, with a ring of light that pulses (wider while the alarm rings).
    if (!head) return;
    const [hx, hy] = head.point;
    const glow = options.glow || 0;
    const pulse = options.still ? 0 : 0.5 + 0.5 * Math.sin(options.now / 260);
    const halo = glow > 0 ? 4 + 9 * glow : 3 + 5 * pulse;
    g.fillStyle = heat.css(head.color, glow > 0 ? 0.3 : 0.16);
    g.beginPath();
    g.arc(hx, hy, 3.2 + halo, 0, Math.PI * 2);
    g.fill();
    g.fillStyle = heat.css(head.color);
    g.beginPath();
    g.arc(hx, hy, 3.2, 0, Math.PI * 2);
    g.fill();
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.chart = { niceCeil, range, draw };
})(typeof window !== "undefined" ? window : globalThis);
