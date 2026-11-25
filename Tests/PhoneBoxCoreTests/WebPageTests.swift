import Foundation
import JavaScriptCore
import Testing

/// Runs the dashboard's pure scripts (`Resources/web/i18n.js`, `format.js`, `history.js`, `metrics.js`, `chart.js`)
/// in JavaScriptCore, the engine behind Safari and iOS Chrome. No browser, Node or npm needed.
struct WebPageTests {
    static let webDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/web")

    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        for name in ["i18n.js", "format.js", "history.js", "metrics.js", "chart.js"] {
            context.evaluateScript(try String(contentsOf: Self.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var tr = PhoneBox.format("tr"), en = PhoneBox.format("en"), T = PhoneBox.i18n.texts.tr;
            var GiB = 1073741824, MiB = 1048576;
            var snapshot = { t: 5000, cpu: { total: 63.6, cores: [], pCores: 4, load: [3.21, 2, 1] },
              mem: { used: 12884901888, total: 17179869184 }, gpu: { util: 17.4 }, temp: { avg: 45.6, max: 54.2 },
              power: { gpu: 0.41, system: 21.94 }, net: { rx: 1234567, tx: 84000, iface: "en0" },
              disk: { free: 21.6e9, total: 494.4e9, read: 20.6e6, write: 3.3e6 },
              battery: { percent: 80, charging: true } };
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func picksTurkishOnlyForTurkish() {
        #expect(string(#"PhoneBox.i18n.pick("tr-TR")"#) == "tr")
        #expect(string(#"PhoneBox.i18n.pick("TR")"#) == "tr")
        #expect(string(#"PhoneBox.i18n.pick("en-GB")"#) == "en")
        #expect(string("PhoneBox.i18n.pick(undefined)") == "en")
    }

    @Test func bothLanguagesHaveTheSameTexts() {
        let check = """
            (function () {
              var tr = PhoneBox.i18n.texts.tr, en = PhoneBox.i18n.texts.en, bad = [];
              function compare(a, b, path) {
                Object.keys(a).concat(Object.keys(b)).forEach(function (key) {
                  if (!(key in a) || !(key in b) || typeof a[key] !== typeof b[key]) bad.push(path + key);
                  else if (typeof a[key] === "object") compare(a[key], b[key], path + key + ".");
                });
              }
              compare(tr, en, "");
              return bad.join(",");
            })()
            """
        #expect(string(check) == "")
    }

    @Test func formatsNumbersForTheLanguage() {
        #expect(string("tr.percent(63.6)") == "%64")
        #expect(string("en.percent(63.6)") == "64%")
        #expect(string("tr.decimal(3.21)") == "3,2")
        #expect(string("en.decimal(3.21)") == "3.2")
        #expect(string("tr.celsius(45.6)") == "46 °C")
        #expect(string("tr.watts(21.94)") == "21,9 W")
        #expect(string("tr.gibibytes(16 * GiB)") == "16")
        #expect(string("tr.gibibytes(13743895347)") == "12,8")
        #expect(string("tr.gigabytes(494.4e9)") == "494,4")
    }

    @Test func switchesUnitsAfterRounding() {
        #expect(string("tr.speed(512)") == "512 B/s")
        #expect(string("tr.speed(999.6)") == "1 KB/s")
        #expect(string("tr.speed(84000)") == "84 KB/s")
        #expect(string("tr.speed(999499)") == "999 KB/s")
        #expect(string("tr.speed(999600)") == "1,0 MB/s")
        #expect(string("en.speed(1234567)") == "1.2 MB/s")
        #expect(string("tr.speed(2.5e9)") == "2,5 GB/s")
        #expect(string("tr.speedShort(1234567)") == "1,2M")
        #expect(string("tr.speedShort(84000)") == "84K")
        #expect(string("tr.speedShort(12)") == "12B")
        #expect(string("tr.memory(640 * MiB)") == "640 MB")
        #expect(string("tr.memory(1023.6 * MiB)") == "1 GB")
        #expect(string("tr.memory(5.3 * GiB)") == "5,3 GB")
    }

    @Test func showsADashForMissingOrBrokenValues() {
        for call in ["tr.percent(null)", "tr.percent(NaN)", "tr.speed(undefined)", "tr.speed(-1)", "tr.watts(Infinity)",
                     "tr.memory(-5)", "tr.celsius('40')", "tr.speedShort(NaN)", "tr.gibibytes(null)"] {
            #expect(string(call) == "—", "\(call)")
        }
    }

    @Test func historyKeepsSixtySecondsWithGaps() {
        let result = string("""
            (function () {
              var h = new PhoneBox.History(60);
              h.push(1000, { cpu: 10 }); h.push(2500, { cpu: 20 }); h.push(4000, { cpu: NaN });
              var s = h.series("cpu");
              return [s.length, s[56], s[57], s[58], s[59], h.series("ram")[59]].join(",");
            })()
            """)
        #expect(result == "60,10,20,,,")
    }

    @Test func historyDropsOldSecondsAndStartsOverAfterAClockJump() {
        let result = string("""
            (function () {
              var h = new PhoneBox.History(3);
              h.push(1000, { cpu: 1 }); h.push(2000, { cpu: 2 }); h.push(5000, { cpu: 5 });
              var kept = h.series("cpu").join("|");
              h.push(1000, { cpu: 7 });              // the Mac's clock went back
              var back = h.series("cpu").join("|");
              h.push(1000 + 3601000, { cpu: 9 });    // and then far forward
              return [kept, back, h.series("cpu").join("|")].join(" / ");
            })()
            """)
        #expect(result == "||5 / ||7 / ||9")
    }

    @Test func keepsTheNumbersOfASnapshot() {
        #expect(string("JSON.stringify(PhoneBox.metrics.values(snapshot))")
            == #"{"cpu":63.6,"ram":75,"gpu":17.4,"tempAvg":45.6,"tempMax":54.2,"power":21.94,"netRx":1234567,"netTx":84000,"diskRead":20600000,"diskWrite":3300000,"battery":80}"#)
        #expect(string("JSON.stringify(PhoneBox.metrics.values({ t: 1, mem: { used: 1, total: 0 }, power: { gpu: 2 } }))")
            == #"{"cpu":null,"ram":null,"gpu":null,"tempAvg":null,"tempMax":null,"power":2,"netRx":null,"netTx":null,"diskRead":null,"diskWrite":null,"battery":null}"#)
    }

    @Test func writesTheTiles() {
        let tiles = string("""
            ["gpu", "temp", "power", "net", "disk", "battery"].map(function (m) { return PhoneBox.metrics.tile(m, snapshot, tr); }).join(" | ")
            """)
        #expect(tiles == "%17 | 46 °C | 21,9 W | ↓1,2M ↑84K | 21,6 GB | %80 ⚡")
        #expect(string(#"PhoneBox.metrics.tile("net", { t: 1 }, tr)"#) == "—")
        #expect(string(#"PhoneBox.metrics.tile("disk", { disk: { total: 5 } }, tr)"#) == "—")
    }

    @Test func writesTheGraphHeader() {
        func header(_ metric: String) -> String? {
            string(#"(function (h) { return h.value + " | " + h.detail; })(PhoneBox.metrics.header("\#(metric)", snapshot, tr, T))"#)
        }
        #expect(header("cpu") == "%64 | yük 3,2")
        #expect(header("ram") == "%75 | 12 / 16 GB")
        #expect(header("gpu") == "%17 | 0,4 W GPU gücü")
        #expect(header("temp") == "46 °C | en yüksek 54 °C")
        #expect(header("power") == "21,9 W | Mac'in tamamı")
        #expect(header("net") == "↓ 1,2 MB/s | ↑ 84 KB/s · en0")
        #expect(header("disk") == "okuma 20,6 MB/s | yazma 3,3 MB/s · 21,6 / 494,4 GB boş")
        #expect(header("battery") == "%80 | şarj oluyor")
        #expect(string(#"PhoneBox.metrics.header("temp", { t: 1 }, tr, T).value"#) == "—")
    }

    @Test func describesBatteryTime() {
        #expect(string(#"PhoneBox.metrics.header("battery", { battery: { percent: 50, charging: false, minutesLeft: 135 } }, tr, T).detail"#)
            == "2 sa 15 dk kaldı")
        #expect(string(#"PhoneBox.metrics.header("battery", { battery: { percent: 99, charging: false } }, tr, T).detail"#) == "prizde")
    }

    @Test func choosesRoundGraphRanges() {
        #expect(string("[0, 0.03, 1.2, 7, 500, 1234].map(PhoneBox.chart.niceCeil).join(',')") == "1,0.05,2,10,500,2000")
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("percent", [[5, 200]]))"#) == #"{"min":0,"max":100}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("temperature", [[46, null], [54.2]]))"#) == #"{"min":40,"max":60}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("temperature", [[12, 71]]))"#) == #"{"min":5,"max":80}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("temperature", [[]]))"#) == #"{"min":30,"max":60}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("fromZero", [[null, 3e6], [8e5]]))"#) == #"{"min":0,"max":5000000}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("fromZero", [[null]]))"#) == #"{"min":0,"max":1}"#)
    }

    @Test func describesEachMetricsGraph() {
        #expect(string(#"PhoneBox.metrics.lines("temp").map(function (l) { return l.key; }).join(",")"#) == "tempAvg,tempMax")
        #expect(string(#"PhoneBox.metrics.lines("net").map(function (l) { return l.key; }).join(",")"#) == "netRx,netTx")
        #expect(string(#"PhoneBox.metrics.lines("cpu")[0].color"#) == "#30d158")
        #expect(string(#"["cpu", "temp", "net", "power", "battery"].map(PhoneBox.metrics.scale).join(",")"#)
            == "percent,temperature,fromZero,fromZero,percent")
        #expect(string(#"PhoneBox.metrics.axisLabel("net", { min: 0, max: 5e6 }, tr)"#) == "5,0 MB/s")
    }
}
