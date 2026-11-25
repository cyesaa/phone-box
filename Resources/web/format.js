// Number formats for the dashboard (design §8 "Dil ve sayı biçimi"). A value that is missing or not a finite number
// shows as "—". A unit switches after rounding, so 999.6 KB/s reads "1,0 MB/s", never "1.000 KB/s".
(function (global) {
  "use strict";

  const GiB = 1073741824;
  const MiB = 1048576;
  const dash = "—";
  const ok = (value) => typeof value === "number" && Number.isFinite(value);

  function make(language) {
    const one = new Intl.NumberFormat(language, { minimumFractionDigits: 1, maximumFractionDigits: 1 });
    const upToOne = new Intl.NumberFormat(language, { maximumFractionDigits: 1 });
    const whole = new Intl.NumberFormat(language, { maximumFractionDigits: 0 });
    const percentStyle = new Intl.NumberFormat(language, { style: "percent", maximumFractionDigits: 0 });

    // [divisor, unit, formatter, fraction digits], smallest first.
    function scaled(value, steps) {
      for (let index = 0; index < steps.length; index += 1) {
        const [divisor, unit, formatter, digits] = steps[index];
        const shown = Math.round((value / divisor) * 10 ** digits) / 10 ** digits;
        if (shown < 1000 || index === steps.length - 1) return formatter.format(value / divisor) + unit;
      }
      return dash;
    }

    return {
      dash,
      /// 64 → "%64" in Turkish, "64%" in English.
      percent: (value) => (ok(value) ? percentStyle.format(value / 100) : dash),
      /// One decimal: 3.21 → "3,2".
      decimal: (value) => (ok(value) ? one.format(value) : dash),
      celsius: (value) => (ok(value) ? whole.format(value) + " °C" : dash),
      watts: (value) => (ok(value) && value >= 0 ? one.format(value) + " W" : dash),
      /// Bytes per second: "512 B/s", "84 KB/s", "1,2 MB/s".
      speed(bytesPerSecond) {
        if (!ok(bytesPerSecond) || bytesPerSecond < 0) return dash;
        return scaled(bytesPerSecond, [[1, " B/s", whole, 0], [1e3, " KB/s", whole, 0], [1e6, " MB/s", one, 1],
                                        [1e9, " GB/s", one, 1]]);
      },
      /// The tiles' short form: "512B", "84K", "1,2M".
      speedShort(bytesPerSecond) {
        if (!ok(bytesPerSecond) || bytesPerSecond < 0) return dash;
        return scaled(bytesPerSecond, [[1, "B", whole, 0], [1e3, "K", whole, 0], [1e6, "M", one, 1], [1e9, "G", one, 1]]);
      },
      /// Binary gigabytes like the RAM ring and Activity Monitor: 16 GiB → "16", 13.74e9 bytes → "12,8".
      gibibytes: (bytes) => (ok(bytes) && bytes >= 0 ? upToOne.format(bytes / GiB) : dash),
      /// An app's memory, binary units like Activity Monitor: "640 MB", "5,3 GB".
      memory(bytes) {
        if (!ok(bytes) || bytes < 0) return dash;
        return Math.round(bytes / MiB) < 1000 ? whole.format(bytes / MiB) + " MB" : upToOne.format(bytes / GiB) + " GB";
      },
      /// Disk capacity in decimal gigabytes like Finder: "494,4".
      gigabytes: (bytes) => (ok(bytes) && bytes >= 0 ? upToOne.format(bytes / 1e9) : dash),
    };
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.format = make;
})(typeof window !== "undefined" ? window : globalThis);
