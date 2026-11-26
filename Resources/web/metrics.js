// What each metric shows (design §6, §8): the values the history keeps, the graph's lines and scale, the tile text and
// the graph header. Pure functions of a snapshot, so they are tested in JavaScriptCore.
(function (global) {
  "use strict";

  const num = (value) => (typeof value === "number" && Number.isFinite(value) ? value : null);
  const GiB = 1073741824;

  // The "Okyanus" palette (design §8 "Stil"); `light` is the bright end of a ring.
  const colors = {
    cpu: "#00c2ff", ram: "#3d6bff", gpu: "#7b61ff", temp: "#00e0b0", power: "#4ff0d0", net: "#8be9ff",
    disk: "#6f8fa8", battery: "#00d0a0",
  };
  const light = { cpu: "#7ff3ff", ram: "#9db4ff" };
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
        return [{ key: "netRx", color, width: 2.2, fill: true }, { key: "netTx", color: "#7b61ff", width: 1.6, fill: false }];
      case "disk":
        return [{ key: "diskRead", color, width: 2.2, fill: true }, { key: "diskWrite", color: "#4ff0d0", width: 1.6, fill: false }];
      default:
        return [{ key: metric, color, width: 2.2, fill: true }];
    }
  }

  /// macOS's memory pressure (`mem.pressure`) as a number for `PhoneBox.heat.limits().ram`.
  const pressures = { normal: 0, warn: 1, critical: 2 };

  /// The numbers that turn a metric red (design §8, see `PhoneBox.heat.limits`): the memory pressure, the network's
  /// ↓ + ↑, free disk space in bytes, and the battery only when it is not on power.
  function heatValues(snapshot) {
    const v = values(snapshot);
    const { mem, net, disk, battery } = snapshot;
    const pressure = mem ? pressures[mem.pressure] : undefined;
    return {
      cpu: v.cpu, ram: pressure ?? null, gpu: v.gpu, temp: v.tempAvg, power: v.power,
      net: net ? num(net.rx + net.tx) : null,
      disk: disk ? num(disk.free) : null,
      battery: battery && battery.plugged === false ? num(battery.percent) : null,
    };
  }

  /// Which limits the graph's lines are measured against. The disk graph shows reading and writing, not free space,
  /// and the RAM graph shows how full memory is, while RAM turns red by memory pressure: neither graph turns red.
  function graphHeat(metric) {
    return metric === "disk" || metric === "ram" ? null : metric;
  }

  /// Which metric's heat and alarm the graph's header value and frame follow: the graph's own metric, RAM included
  /// (by memory pressure), but not disk, whose header shows reading speed, not free space.
  function headerHeat(metric) {
    return metric === "disk" ? null : metric;
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
      case "disk": {
        const free = disk ? format.gigabytes(disk.free) : format.dash;
        return free === format.dash ? free : free + " GB";
      }
      case "battery": return battery ? format.percent(battery.percent) + (battery.charging ? " ⚡" : "") : format.dash;
      default: return format.dash;
    }
  }

  function batteryDetail(battery, t) {
    // Whole minutes: on screen the estimate glides from one value to the next.
    const time = (minutes) => {
      const whole = Math.round(minutes);
      return t.duration(Math.floor(whole / 60), whole % 60);
    };
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
  global.PhoneBox.metrics = { colors, light, order, values, heatValues, graphHeat, headerHeat, lines, scale, tile, header, axisLabel, GiB };
})(typeof window !== "undefined" ? window : globalThis);
