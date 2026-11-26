// The command side of the page (design §7, §8 "Komut etkileşimleri"): the control strip (previous, play/pause, next,
// the volume slider, mute), the app panel (Quit, Force quit), the "⋯" menu's Mac commands, the confirmation that
// Sleep and Force quit ask for, and the 2-second toast. Commands go only from the cable; elsewhere the controls are
// dim and a tap says why. A tap that comes just as an overlay opens or closes is ignored (`settleTaps`). Checked by
// eye.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  /// After the slider is let go, the Mac's own volume is shown again only after this long, so the knob does not jump
  /// back to the old value before the Mac has taken the new one.
  const settleAfterDrag = 1500;
  /// The panel and the confirmation take taps the moment they open and let them through the moment they close, while
  /// their fade takes 0.25–0.35 s. For this long after either, their buttons and the commands beneath ignore taps, and
  /// so do the "⋯" menu's commands after the menu opens: the second tap of a double tap must not press a button the
  /// user has not seen (the Sleep confirmation's "Uyut" lies over the menu's "Uyut", the panel's "Kapat" over app rows,
  /// its "Vazgeç" over the control strip).
  const settleTaps = 400;

  class Controls {
    constructor(t, format, commands) {
      this.t = t;
      this.format = format;
      this.commands = commands;
      this.access = null;
      this.audio = null;
      this.media = null;
      this.dragging = false;
      this.quietUntil = 0;
      /// Until then taps on the overlays and the commands are ignored (`settleTaps`).
      this.calmUntil = 0;
      this.toastTimer = null;
      this.onConfirm = null;
      /// The app whose panel is open.
      this.app = null;
      this.throttle = new global.PhoneBox.Throttle(250, (level) => this.run("volume", { level }, null));
      this.wire();
      this.render();
    }

    setAccess(access) {
      this.access = access;
      this.render();
    }

    /// The Mac's audio and what is playing, from each snapshot.
    setSnapshot(snapshot) {
      this.audio = snapshot.audio || null;
      this.media = snapshot.media || null;
      this.render();
    }

    /// Commands may go out: the Mac allows them (cable) and the socket is authenticated.
    allowed() {
      return Boolean(this.access && this.access.commands) && this.commands.canSend();
    }

    /// True just after the panel or the confirmation opened or closed, or the "⋯" menu closed (`settleTaps`): the
    /// second tap of a double tap would land on something the user has not seen.
    calm() {
      const now = global.performance.now();
      return now < this.calmUntil || now - global.PhoneBox.ui.menuClosedAt < settleTaps;
    }

    render() {
      const allowed = this.allowed();
      for (const id of ["media-previous", "media-play", "media-next"]) $(id).classList.toggle("off", !allowed);
      $("media-play").classList.toggle("playing", Boolean(this.media && this.media.playing));
      const audio = allowed && Boolean(this.audio);
      $("volume").classList.toggle("off", !audio);
      $("mute").classList.toggle("off", !audio);
      $("mute").classList.toggle("muted", Boolean(this.audio && this.audio.muted));
      if (this.audio && !this.dragging && global.performance.now() >= this.quietUntil) this.paintVolume(this.audio.volume);
      for (const item of global.document.querySelectorAll("#menu [data-command]")) item.classList.toggle("off", !allowed);
      $("sheet-quit").classList.toggle("off", !allowed);
      $("sheet-force").classList.toggle("off", !allowed);
    }

    /// A tap on an app row: its panel with Quit, Force quit and Cancel. A row the phone cannot quit (grey) only says
    /// so: `quitApp` needs a regular app with a bundle identifier (design §7).
    openApp(app) {
      if (!app) return;
      this.app = app;
      const quittable = Boolean(app.quittable && app.bundleId);
      $("sheet-name").textContent = app.name;
      $("sheet-figures").textContent = `${this.format.percent(app.cpu)} · ${this.format.memory(app.mem)}`;
      $("sheet-note").hidden = quittable;
      $("sheet-quit").hidden = !quittable;
      $("sheet-force").hidden = !quittable;
      this.render();
      this.calmUntil = global.performance.now() + settleTaps;
      $("sheet").removeAttribute("inert");
      $("sheet").classList.add("show");
    }

    /// Closed, the panel is inert: neither a tap nor the keyboard or VoiceOver reaches its buttons.
    closeApp() {
      this.app = null;
      this.calmUntil = global.performance.now() + settleTaps;
      $("sheet").setAttribute("inert", "");
      $("sheet").classList.remove("show");
    }

    /// Quit at once; Force quit only after a confirmation (unsaved work is lost).
    quit(force) {
      const app = this.app;
      const t = this.t;
      if (!app || !this.ready("quitApp")) return;
      this.closeApp();
      const go = () => this.run("quitApp", { bundleId: app.bundleId, force }, force ? t.doneForce(app.name) : t.doneQuit(app.name));
      if (force) this.confirm(t.confirmForceTitle(app.name), t.confirmForceText, t.forceQuit, go);
      else go();
    }

    paintVolume(level) {
      const slider = $("volume");
      slider.style.setProperty("--volume", `${(Math.max(0, Math.min(1, level)) * 100).toFixed(1)}%`);
      slider.setAttribute("aria-valuenow", String(Math.round(level * 100)));
    }

    /// True when a tap may send `name` now. A tap that comes just as the panel or the confirmation opens or closes is
    /// ignored without a word (`settleTaps`); otherwise a red toast says why the command cannot go.
    ready(name) {
      return !this.calm() && this.possible(name);
    }

    /// True when `name` may go out now; otherwise a red toast says why.
    possible(name) {
      if (!this.allowed()) {
        this.toast(this.access && this.access.commands ? this.t.errorFailed : this.t.errorNotAllowed, false);
        return false;
      }
      if ((name === "volume" || name === "mute") && !this.audio) {
        this.toast(this.t.errorAudio, false);
        return false;
      }
      return true;
    }

    /// Sends a command. A failure always shows a red toast; success shows `done` (a text) in green, or nothing when
    /// the screen already shows the change (media, volume, mute). Not held back by `settleTaps`: a command the user
    /// just confirmed, or the slider's last value, still goes out; the taps that start them check `ready`.
    run(name, args, done) {
      if (!this.possible(name)) return;
      this.commands.run(name, args, (result) => {
        if (result === "ok") {
          if (done) this.toast(done, true);
          return;
        }
        this.toast(this.failure(name, result), false);
      });
    }

    failure(name, result) {
      const t = this.t;
      switch (result) {
        case "not-allowed": return t.errorNotAllowed;
        case "app-changed": return t.errorAppChanged;
        case "unsupported": return name === "volume" || name === "mute" ? t.errorAudio : t.errorUnsupported;
        default: return t.errorFailed;
      }
    }

    /// A message at the top for 2 seconds: a green tick for success, red for a failure.
    toast(text, ok) {
      const toast = $("toast");
      $("toast-icon").textContent = ok ? "✓" : "!";
      $("toast-text").textContent = text;
      toast.classList.toggle("ok", ok);
      toast.classList.toggle("bad", !ok);
      toast.classList.add("show");
      global.clearTimeout(this.toastTimer);
      this.toastTimer = global.setTimeout(() => toast.classList.remove("show"), 2000);
    }

    /// A question with a red action button; `then` runs only on that button.
    confirm(title, text, action, then) {
      $("confirm-title").textContent = title;
      $("confirm-text").textContent = text;
      $("confirm-ok").textContent = action;
      this.onConfirm = then;
      this.calmUntil = global.performance.now() + settleTaps;
      $("confirm").removeAttribute("inert");
      $("confirm").classList.add("show");
    }

    /// Closed, the confirmation is inert like the panel.
    closeConfirm(accepted) {
      this.calmUntil = global.performance.now() + settleTaps;
      $("confirm").setAttribute("inert", "");
      $("confirm").classList.remove("show");
      const then = this.onConfirm;
      this.onConfirm = null;
      if (accepted && then) then();
    }

    wire() {
      const t = this.t;
      for (const button of global.document.querySelectorAll("[data-media]")) {
        button.addEventListener("click", () => {
          if (this.ready("media")) this.run("media", { action: button.dataset.media }, null);
        });
      }
      $("mute").addEventListener("click", () => {
        if (!this.ready("mute")) return;
        const on = !this.audio.muted;
        // Shown at once; the next snapshot confirms it.
        this.audio = Object.assign({}, this.audio, { muted: on });
        this.render();
        this.run("mute", { on }, null);
      });

      const slider = $("volume");
      // The fill and the knob sit in the track, inside the slider's side padding: measuring the track keeps the knob
      // under the finger.
      const track = slider.querySelector(".volume-track");
      const level = (event) => {
        const box = track.getBoundingClientRect();
        return Math.max(0, Math.min(1, (event.clientX - box.left) / box.width));
      };
      const slide = (value) => {
        this.paintVolume(value);
        this.throttle.push(Math.round(value * 100) / 100);
      };
      slider.addEventListener("pointerdown", (event) => {
        if (!this.ready("volume")) return;
        this.dragging = true;
        this.throttle.reset();
        slider.classList.add("dragging");
        // Keeps the drag on the slider when the finger slides off it; refused for a pointer that is not down.
        try {
          slider.setPointerCapture(event.pointerId);
        } catch (error) {}
        slide(level(event));
      });
      slider.addEventListener("pointermove", (event) => {
        if (this.dragging) slide(level(event));
      });
      const end = () => {
        if (!this.dragging) return;
        this.dragging = false;
        slider.classList.remove("dragging");
        this.throttle.flush();
        this.quietUntil = global.performance.now() + settleAfterDrag;
      };
      slider.addEventListener("pointerup", end);
      slider.addEventListener("pointercancel", end);

      const done = { lock: t.doneLock, displaySleep: t.doneDisplay, sleep: t.doneSleep };
      for (const item of global.document.querySelectorAll("#menu [data-command]")) {
        item.addEventListener("click", () => {
          // So soon after the menu opened, this is the second tap of a double tap on "⋯": it closes nothing and sends
          // nothing.
          if (global.performance.now() - global.PhoneBox.ui.menuOpenedAt < settleTaps) return;
          const name = item.dataset.command;
          // Checked before the menu closes, which starts a calm period of its own.
          const go = this.ready(name);
          global.PhoneBox.ui.closeMenu();
          if (!go) return;
          if (name === "sleep") {
            this.confirm(t.confirmSleepTitle, t.confirmSleepText, t.sleep, () => this.run(name, {}, done[name]));
          } else {
            this.run(name, {}, done[name]);
          }
        });
      }
      // The panel's and the confirmation's buttons and backdrops do nothing just as they open or close.
      $("sheet-quit").addEventListener("click", () => {
        if (!this.calm()) this.quit(false);
      });
      $("sheet-force").addEventListener("click", () => {
        if (!this.calm()) this.quit(true);
      });
      $("sheet-cancel").addEventListener("click", () => {
        if (!this.calm()) this.closeApp();
      });
      $("sheet").addEventListener("click", (event) => {
        if (event.target === $("sheet") && !this.calm()) this.closeApp();
      });
      $("confirm-ok").addEventListener("click", () => {
        if (!this.calm()) this.closeConfirm(true);
      });
      $("confirm-cancel").addEventListener("click", () => {
        if (!this.calm()) this.closeConfirm(false);
      });
      $("confirm").addEventListener("click", (event) => {
        if (event.target === $("confirm") && !this.calm()) this.closeConfirm(false);
      });
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.Controls = Controls;
})(typeof window !== "undefined" ? window : globalThis);
