// What each metric shows (design §6, §8): the values the history keeps, the graph's lines and scale, the tile text and
// the graph header. Pure functions of a snapshot, so they are tested in JavaScriptCore.
(function (global) {
  "use strict";

  const num = (value) => (typeof value === "number" && Number.isFinite(value) ? value : null);
  const GiB = 1073741824;

  const colors = {
    cpu: "#30d158", ram: "#0a84ff", gpu: "#bf5af2", temp: "#ff9f0a", power: "#ffd60a", net: "#64d2ff",
    disk: "#8e8e93", battery: "#30d158",
  };
  const order = ["cpu", "ram", "gpu", "temp", "power", "net", "disk", "battery"];

  /// The numbers the history keeps for one snapshot.
  function values(snapshot) {
    const { cpu, mem, gpu, temp, power, net, disk, battery } = snapshot;
    return {
      cpu: cpu ? num(cpu.total) : null,
      ram: mem && mem.total > 0 ? num((mem.used / mem.total) * 100) : null,
      gpu: gpu ? num(gpu.util) : null,
      tempAvg: temp ? num(temp.avg) : null,
      tempMax: temp ? num(temp.max) : null,
      power: power ? num(power.system ?? power.gpu) : null,
      netRx: net ? num(net.rx) : null,
      netTx: net ? num(net.tx) : null,
      diskRead: disk ? num(disk.read) : null,
      diskWrite: disk ? num(disk.write) : null,
      battery: battery ? num(battery.percent) : null,
    };
  }

  /// The graph's lines for a metric: history key, colour, width, and whether the area under it is filled.
  function lines(metric) {
    const color = colors[metric];
    switch (metric) {
      case "temp":
        return [{ key: "tempAvg", color, width: 2.2, fill: true }, { key: "tempMax", color, width: 1, fill: false, alpha: 0.55 }];
      case "net":
        return [{ key: "netRx", color, width: 2.2, fill: true }, { key: "netTx", color: "#bf5af2", width: 1.6, fill: false }];
      case "disk":
        return [{ key: "diskRead", color: "#d1d1d6", width: 2.2, fill: true }, { key: "diskWrite", color: "#ff9f0a", width: 1.6, fill: false }];
      default:
        return [{ key: metric, color, width: 2.2, fill: true }];
    }
  }

  /// How the graph's vertical axis is chosen (see `PhoneBox.chart.range`).
  function scale(metric) {
    if (metric === "temp") return "temperature";
    if (metric === "power" || metric === "net" || metric === "disk") return "fromZero";
    return "percent";
  }

  /// The big text on a tile.
  function tile(metric, snapshot, format) {
    const { gpu, temp, power, net, disk, battery } = snapshot;
    switch (metric) {
      case "gpu": return gpu ? format.percent(gpu.util) : format.dash;
      case "temp": return temp ? format.celsius(temp.avg) : format.dash;
      case "power": return power ? format.watts(power.system ?? power.gpu) : format.dash;
      case "net": return net ? `↓${format.speedShort(net.rx)} ↑${format.speedShort(net.tx)}` : format.dash;
      case "disk": return disk ? format.gigabytes(disk.free) + " GB" : format.dash;
      case "battery": return battery ? format.percent(battery.percent) + (battery.charging ? " ⚡" : "") : format.dash;
      default: return format.dash;
    }
  }

  function batteryDetail(battery, t) {
    const time = (minutes) => t.duration(Math.floor(minutes / 60), minutes % 60);
    if (battery.minutesLeft != null) return battery.charging ? t.untilFull(time(battery.minutesLeft)) : t.untilEmpty(time(battery.minutesLeft));
    return battery.charging ? t.charging : t.onPower;
  }

  /// The graph header's value and detail for the selected metric.
  function header(metric, snapshot, format, t) {
    const { cpu, mem, gpu, temp, power, net, disk, battery } = snapshot;
    const none = { value: format.dash, detail: "" };
    switch (metric) {
      case "cpu":
        if (!cpu) return none;
        return { value: format.percent(cpu.total), detail: cpu.load && cpu.load.length ? t.load(format.decimal(cpu.load[0])) : "" };
      case "ram":
        if (!mem || !(mem.total > 0)) return none;
        return { value: format.percent((mem.used / mem.total) * 100), detail: t.memory(format.gibibytes(mem.used), format.gibibytes(mem.total)) };
      case "gpu":
        if (!gpu) return none;
        return { value: format.percent(gpu.util), detail: power && num(power.gpu) !== null ? t.gpuWatts(format.watts(power.gpu)) : "" };
      case "temp":
        if (!temp) return none;
        return { value: format.celsius(temp.avg), detail: temp.max - temp.avg >= 1 ? t.hottest(format.celsius(temp.max)) : "" };
      case "power":
        if (!power || num(power.system ?? power.gpu) === null) return none;
        return { value: format.watts(power.system ?? power.gpu), detail: num(power.system) !== null ? t.systemPower : t.gpuPower };
      case "net":
        if (!net) return none;
        return { value: "↓ " + format.speed(net.rx), detail: t.upload(format.speed(net.tx), net.iface) };
      case "disk":
        if (!disk) return none;
        return { value: t.diskRead(format.speed(disk.read)),
                 detail: t.diskDetail(format.speed(disk.write), format.gigabytes(disk.free), format.gigabytes(disk.total)) };
      case "battery":
        if (!battery) return none;
        return { value: format.percent(battery.percent), detail: batteryDetail(battery, t) };
      default:
        return none;
    }
  }

  /// The top-of-axis label for a graph's range.
  function axisLabel(metric, range, format) {
    switch (scale(metric)) {
      case "temperature": return format.celsius(range.max);
      case "fromZero": return metric === "power" ? format.watts(range.max) : format.speed(range.max);
      default: return format.percent(range.max);
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.metrics = { colors, order, values, lines, scale, tile, header, axisLabel, GiB };
})(typeof window !== "undefined" ? window : globalThis);
