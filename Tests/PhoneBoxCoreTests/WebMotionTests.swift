import Foundation
import JavaScriptCore
import Testing

/// Runs the dashboard's `heat.js`, `motion.js` and `clock.js` (with `metrics.js` for the values that turn red) in
/// JavaScriptCore: the limits, the level, the colour path, the alarm rule, the gliding values and the clock text.
struct WebMotionTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        for name in ["i18n.js", "format.js", "metrics.js", "heat.js", "motion.js", "clock.js"] {
            context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var H = PhoneBox.heat, M = PhoneBox.motion, L = H.limits([25, 60]);
            function hex(color) { return "#" + color.map(function (c) { return (c < 16 ? "0" : "") + c.toString(16); }).join(""); }
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func takesThePowerLimitsFromTheMac() {
        #expect(string("L.power.join('-') + ' ' + L.cpu.join('-') + ' ' + L.disk.join('-')") == "25-60 40-95 30000000000-5000000000")
        for bad in ["undefined", "[1]", "[40, 20]", "['a', 3]", "[NaN, 3]"] {
            #expect(string("H.limits(\(bad)).power.join('-')") == "15-35", "\(bad)")
        }
    }

    @Test func measuresHowCloseAValueIsToItsLimit() {
        #expect(string("[30, 40, 67.5, 95, 120].map(function (v) { return H.level(L.cpu, v); }).join(',')") == "0,0,0.5,1,1")
        #expect(string("[40e9, 30e9, 17.5e9, 5e9, 1e9].map(function (v) { return H.level(L.disk, v); }).join(',')") == "0,0,0.5,1,1")
        #expect(string("[H.level(L.cpu, null), H.level(L.cpu, NaN), H.level(undefined, 3)].join(',')") == ",,")
    }

    @Test func turnsFromTheMetricsColourThroughVioletToRed() {
        #expect(string("hex(H.color('#00c2ff', 0))") == "#00c2ff")
        #expect(string("hex(H.color('#00c2ff', 1))") == "#ff2d2d")
        #expect(string("hex(H.color('#7ff3ff', 1, true))") == "#ff8a7a")
        // The hue only turns upwards: blue (~240°), violet, pink, then red (~29° + 360°).
        let hues = string("""
            [0, 0.25, 0.5, 0.75, 1].map(function (level) {
              var hue = H.oklch(H.color('#00c2ff', level))[2];
              return Math.round(hue < 200 ? hue + 360 : hue);
            }).join(',')
            """)
        let values = (hues ?? "").split(separator: ",").compactMap { Int($0) }
        #expect(values.count == 5)
        #expect(values == values.sorted())
        #expect((260...340).contains(values[2]), "half way should be violet or pink, got \(values[2])°")
    }

    @Test func ringsAfterThreeSnapshotsAtTheLimitAndStopsAfterThreeBelow() {
        let result = string("""
            (function () {
              var alarm = new H.Alarm(), log = [];
              function step(level) { var started = alarm.update({ cpu: level }); log.push(started.join("") + ":" + alarm.active().join("")); }
              step(1); step(1); step(1);            // rings on the third
              step(0.95); step(0.95); step(0.95);   // still above 0.9: keeps ringing
              step(0.5); step(null); step(0.2);     // a missing value counts as calm: stops on the third
              step(1); step(0.4); step(1);          // a spike now and then never rings
              return log.join(" ");
            })()
            """)
        #expect(result == ": : cpu:cpu :cpu :cpu :cpu :cpu :cpu : : : :")
    }

    @Test func clearsTheAlarmWhenTheValuesGoStale() {
        #expect(string("(function () { var a = new H.Alarm(); a.update({ temp: 1 }); a.update({ temp: 1 }); a.update({ temp: 1 }); a.clear(); a.update({ temp: 1 }); return a.active().length; })()") == "0")
    }

    @Test func findsTheValuesThatTurnRed() {
        let values = string("""
            JSON.stringify(PhoneBox.metrics.heatValues({ t: 1, cpu: { total: 63.6 }, mem: { used: 12, total: 16 }, gpu: { util: 17 },
              temp: { avg: 45.6, max: 54 }, power: { gpu: 0.4, system: 21.9 }, net: { rx: 1200, tx: 34 },
              disk: { free: 21.6e9, total: 494e9 }, battery: { percent: 80, charging: false, plugged: true } }))
            """)
        #expect(values == #"{"cpu":63.6,"ram":75,"gpu":17,"temp":45.6,"power":21.9,"net":1234,"disk":21600000000,"battery":null}"#)
        #expect(string("PhoneBox.metrics.heatValues({ battery: { percent: 12, charging: false, plugged: false } }).battery") == "12")
        #expect(string("PhoneBox.metrics.heatValues({ battery: { percent: 12, charging: false } }).battery") == "null")
        #expect(string("[PhoneBox.metrics.graphHeat('disk'), PhoneBox.metrics.graphHeat('net')].join(',')") == ",net")
    }

    @Test func blendsSnapshotsNumberByNumber() {
        let result = string("""
            JSON.stringify(M.between({ cpu: { total: 10, load: [1] }, mem: { used: 4 } },
                                     { cpu: { total: 30, load: [2] }, mem: { used: 8, total: 16 }, media: { title: "x" } }, 0.5))
            """)
        #expect(result == #"{"cpu":{"total":20,"load":[2]},"mem":{"used":6,"total":16},"media":{"title":"x"}}"#)
    }

    @Test func glidesToEachSnapshotFromWhatIsShown() {
        let result = string("""
            (function () {
              var glide = new M.Glide(900), out = [];
              glide.push({ v: 0 }, 0);
              out.push(glide.at(0).v);
              glide.push({ v: 100 }, 1000);
              out.push(Math.round(glide.at(1450).v), glide.at(1900).v);
              glide.push({ v: 0 }, 2000);
              glide.push({ v: 50 }, 2450);           // mid-way: starts from what is on screen
              out.push(Math.round(glide.at(2450).v), glide.at(3350).v);
              return out.join(",") + " " + (new M.Glide().at(5) === null);
            })()
            """)
        #expect(result == "0,88,100,13,50 true")
    }

    @Test func drawsTheGraphBehindTheMacsClockByTheArrivalSpread() {
        let result = string("""
            (function () {
              var line = new M.Timeline(20), out = [];
              out.push(line.at(0) === null);
              line.arrived(10000, 500);   // the Mac's 10.0 s arrived at page time 0.5 s
              out.push(line.at(1000));    // 1000 + 9500 - 150: no spread yet, the 150 ms floor
              line.arrived(11000, 1800);  // 300 ms later than the first
              out.push(line.at(2000));    // 2000 + 9500 - (300 + 100)
              line.arrived(12000, 2000);  // the quickest so far: spread 800
              out.push(line.at(3000));    // 3000 + 10000 - 900
              line.arrived(99000, 3000);  // the Mac's clock jumped: start over
              out.push(line.at(4000));    // 4000 + 96000 - 150
              var slow = new M.Timeline(20);
              slow.arrived(0, 0); slow.arrived(1000, 4000);
              out.push(slow.at(5000));    // spread 3000: capped at 1500
              return out.join(",");
            })()
            """)
        #expect(result == "true,10350,11100,12100,99850,3500")
    }

    @Test func roundsTheBatteryTimeWhileItGlides() {
        let detail = string("""
            PhoneBox.metrics.header("battery", M.between({ battery: { percent: 50, charging: false, minutesLeft: 312 } },
              { battery: { percent: 49, charging: false, minutesLeft: 305 } }, 0.37), PhoneBox.format("tr"),
              PhoneBox.i18n.texts.tr).detail
            """)
        #expect(detail == "5 sa 9 dk kaldı")
    }

    @Test func writesTheClockInBothLanguages() {
        #expect(string("JSON.stringify(PhoneBox.clock.parts(new Date(2026, 10, 26, 9, 5), 'tr'))") == #"{"time":"09:05","day":"26 Kas Per"}"#)
        #expect(string("JSON.stringify(PhoneBox.clock.parts(new Date(2026, 10, 26, 21, 40), 'en'))") == #"{"time":"21:40","day":"Thu, Nov 26"}"#)
    }
}
