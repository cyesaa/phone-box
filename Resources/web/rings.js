// The CPU and RAM rings on a <canvas> (design §8 "Görünüm ve hareket"): a thick arc whose colour runs from dark to
// light, a round tip that glows, and a shine that sweeps over the filled part. Checked by eye.
(function (global) {
  "use strict";

  /// Draws one ring into a square canvas `size` CSS pixels wide. `spec`: `fraction` 0…1 filled; `from` and `to`,
  /// [r, g, b] at the arc's start and end; `now` for the shine and the tip's glow; `still` leaves those out ("Reduce
  /// Motion"); `glow` 0…1 adds a pulsing glow around the arc while the metric's alarm rings.
  function draw(canvas, size, spec) {
    if (!size) return;
    const { css, mix } = global.PhoneBox.heat;
    const ratio = Math.min(global.devicePixelRatio || 1, 3);
    const pixels = Math.round(size * ratio);
    if (canvas.width !== pixels || canvas.height !== pixels) {
      canvas.width = pixels;
      canvas.height = pixels;
    }
    const g = canvas.getContext("2d");
    g.setTransform(ratio, 0, 0, ratio, 0, 0);
    g.clearRect(0, 0, size, size);

    const center = size / 2;
    const width = size * 0.12;
    const radius = center - width / 2 - 3;
    const fraction = Math.max(0, Math.min(1, spec.fraction || 0));
    const start = -Math.PI / 2;
    const end = start + Math.PI * 2 * fraction;
    const arc = (from, to) => {
      g.beginPath();
      g.arc(center, center, radius, from, to);
    };

    g.lineWidth = width;
    g.lineCap = "round";
    g.strokeStyle = css(spec.from, 0.16);
    arc(0, Math.PI * 2);
    g.stroke();
    if (fraction <= 0) return;

    if (spec.glow > 0) {
      g.save();
      g.shadowColor = css(spec.to, 0.95);
      g.shadowBlur = width * (0.5 + spec.glow);
      g.strokeStyle = css(spec.from, 0.3 + 0.5 * spec.glow);
      arc(start, end);
      g.stroke();
      g.restore();
    }

    // The arc in short pieces, each a step further from `from` towards `to`.
    const steps = 72;
    const pieces = Math.max(1, Math.ceil(steps * fraction));
    for (let index = 0; index < pieces; index += 1) {
      g.strokeStyle = css(mix(spec.from, spec.to, index / steps));
      g.lineCap = index === 0 ? "round" : "butt";
      arc(start + (index / steps) * Math.PI * 2, Math.min(end, start + ((index + 1.4) / steps) * Math.PI * 2));
      g.stroke();
    }

    const tip = mix(spec.from, spec.to, fraction);
    g.save();
    g.beginPath();
    g.arc(center + Math.cos(end) * radius, center + Math.sin(end) * radius, width / 2, 0, Math.PI * 2);
    g.fillStyle = css(tip);
    if (!spec.still) {
      g.shadowColor = css(spec.to);
      g.shadowBlur = width * (0.9 + 0.25 * Math.sin(spec.now / 400));
    }
    g.fill();
    g.restore();
    if (spec.still) return;

    const sweep = (spec.now / 1400) % 1;
    g.lineWidth = width * 0.55;
    g.lineCap = "round";
    g.strokeStyle = "rgba(255, 255, 255, 0.24)";
    arc(start + (end - start) * sweep, start + (end - start) * Math.min(1, sweep + 0.08));
    g.stroke();
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.rings = { draw };
})(typeof window !== "undefined" ? window : globalThis);
