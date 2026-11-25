// The 60-second graph on a <canvas> (design §8 "Grafik"). `range` is pure and tested; `draw` is checked by eye.
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

  function rgba(hex, alpha) {
    const value = parseInt(hex.slice(1), 16);
    return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${alpha})`;
  }

  /// Draws `lines` ([{values, color, width, fill, alpha}]) scaled to `bounds`, with `label` at the top left.
  function draw(canvas, lines, bounds, label) {
    const ratio = global.devicePixelRatio || 1;
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    if (!width || !height) return;
    if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
    }
    const g = canvas.getContext("2d");
    g.setTransform(ratio, 0, 0, ratio, 0, 0);
    g.clearRect(0, 0, width, height);

    g.strokeStyle = "#2c2c2e";
    g.lineWidth = 1;
    g.setLineDash([3, 4]);
    g.beginPath();
    g.moveTo(0, Math.round(height / 2) + 0.5);
    g.lineTo(width, Math.round(height / 2) + 0.5);
    g.stroke();
    g.setLineDash([]);

    if (label) {
      g.fillStyle = "#8e8e93";
      g.font = "10px -apple-system, system-ui, sans-serif";
      g.textBaseline = "top";
      g.fillText(label, 0, 0);
    }

    const pad = 3;
    const span = bounds.max - bounds.min || 1;
    const y = (value) => pad + (1 - (Math.min(Math.max(value, bounds.min), bounds.max) - bounds.min) / span) * (height - 2 * pad);
    for (const line of lines) {
      const count = line.values.length;
      const x = (index) => (count <= 1 ? width : (index / (count - 1)) * width);
      const runs = [];
      let run = [];
      line.values.forEach((value, index) => {
        if (value === null) {
          if (run.length) runs.push(run);
          run = [];
        } else {
          run.push([x(index), y(value)]);
        }
      });
      if (run.length) runs.push(run);
      g.globalAlpha = line.alpha ?? 1;
      for (const points of runs) {
        if (points.length === 1) {
          g.fillStyle = line.color;
          g.beginPath();
          g.arc(points[0][0], points[0][1], line.width, 0, Math.PI * 2);
          g.fill();
          continue;
        }
        if (line.fill) {
          const gradient = g.createLinearGradient(0, 0, 0, height);
          gradient.addColorStop(0, rgba(line.color, 0.35));
          gradient.addColorStop(1, rgba(line.color, 0));
          g.fillStyle = gradient;
          g.beginPath();
          g.moveTo(points[0][0], height);
          for (const [px, py] of points) g.lineTo(px, py);
          g.lineTo(points[points.length - 1][0], height);
          g.closePath();
          g.fill();
        }
        g.strokeStyle = line.color;
        g.lineWidth = line.width;
        g.lineJoin = "round";
        g.lineCap = "round";
        g.beginPath();
        points.forEach(([px, py], index) => (index ? g.lineTo(px, py) : g.moveTo(px, py)));
        g.stroke();
      }
      g.globalAlpha = 1;
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.chart = { niceCeil, range, draw };
})(typeof window !== "undefined" ? window : globalThis);
