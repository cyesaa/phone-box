// Screen-level behaviour (design §8): keeping the screen on, the Start screen, the first-run guide, the "⋯" menu and
// the OLED shift.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  const guideDoneKey = "phonebox-guide-done";
  let t = null;
  let started = false;
  /// The pairing was lost ("Eşleşmedi"): the page is dead and lets the screen sleep.
  let dead = false;

  // ---- Keep the screen on (spike V4): an unmuted, silent video that never loops, in an "ambient" audio session so
  // music on the phone keeps playing. A tap must start it.
  const video = $("keepawake");
  video.addEventListener("timeupdate", () => {
    if (video.currentTime > 0.5) video.currentTime = Math.random() * 0.4;
  });

  function keepAwake() {
    try {
      if (global.navigator.audioSession) global.navigator.audioSession.type = "ambient";
    } catch (error) {}
    video.muted = false;
    video.loop = false;
    return video.play();
  }

  // Chrome does not fire visibilitychange when the phone is unlocked, and WebKit pauses media while the page is
  // hidden: restart the video every few seconds if it stopped.
  global.setInterval(() => {
    if (dead || !started || global.document.visibilityState !== "visible" || !video.paused) return;
    keepAwake().catch((error) => {
      // iOS will not restart it without a tap: ask for one, or the screen will go to sleep.
      if (error && error.name === "NotAllowedError") {
        started = false;
        $("start").hidden = false;
      }
    });
  }, 3000);

  /// Resolves true once the video plays (the screen then stays on).
  function begin() {
    return keepAwake().then(() => {
      started = true;
      return true;
    }, () => false);
  }

  // ---- Start screen: shown on every visit (the video needs a tap).
  $("start-button").addEventListener("click", () => {
    begin().then((ok) => {
      $("start").hidden = ok;
    });
  });

  // ---- First-run guide (also from "⋯ → Kurulum rehberi").
  function guideDone() {
    try {
      return global.localStorage.getItem(guideDoneKey) === "1";
    } catch (error) {
      return false;
    }
  }

  function openGuide() {
    const standalone = global.navigator.standalone === true || global.matchMedia("(display-mode: standalone)").matches;
    const step1 = $("guide1-text");
    step1.textContent = standalone ? t.guide1Done : /CriOS/.test(global.navigator.userAgent) ? t.guide1Chrome : t.guide1Safari;
    step1.classList.toggle("done", standalone);
    // The personal link from the stored key, not the address bar (the page may have been opened without #k=).
    let link = "";
    try {
      const key = global.localStorage.getItem("phonebox-key");
      if (key) link = `${global.location.origin}/#k=${key}`;
    } catch (error) {}
    $("guide-link").value = link;
    $("guide-link-row").hidden = !link;
    $("guide-audio").hidden = Boolean(global.navigator.audioSession);
    $("guide-copy").textContent = t.copy;
    // On a dead page the button only closes the guide: it must not keep the screen on.
    $("guide-done").textContent = started || dead ? t.close : t.start;
    $("guide").hidden = false;
  }

  $("guide-done").addEventListener("click", () => {
    try {
      global.localStorage.setItem(guideDoneKey, "1");
    } catch (error) {}
    if (started || dead) {
      $("guide").hidden = true;
      return;
    }
    begin().then((ok) => {
      $("guide").hidden = true;
      $("start").hidden = ok;
    });
  });

  // Plain http:// has no Clipboard API on iOS; copying the selected text still works inside a tap.
  $("guide-copy").addEventListener("click", () => {
    const input = $("guide-link");
    input.focus();
    input.setSelectionRange(0, input.value.length);
    let copied = false;
    try {
      copied = global.document.execCommand("copy");
    } catch (error) {}
    input.blur();
    if (copied) {
      $("guide-copy").textContent = t.copied;
      global.setTimeout(() => {
        $("guide-copy").textContent = t.copy;
      }, 2000);
    }
  });

  // ---- "⋯" menu: opens above its button.
  /// When it last opened and closed (`performance.now()`): controls.js ignores a tap on its commands that comes too
  /// soon after it opened, and a tap on the strip that comes too soon after it closed.
  let menuOpenedAt = -Infinity;
  let menuClosedAt = -Infinity;

  function openMenu() {
    const menu = $("menu");
    menu.hidden = false;
    $("menu-backdrop").hidden = false;
    const button = $("more").getBoundingClientRect();
    menu.style.left = Math.max(8, Math.min(button.right - menu.offsetWidth, global.innerWidth - menu.offsetWidth - 8)) + "px";
    menu.style.top = Math.max(8, button.top - menu.offsetHeight - 8) + "px";
    menuOpenedAt = global.performance.now();
  }

  function closeMenu() {
    if (!$("menu").hidden) menuClosedAt = global.performance.now();
    $("menu").hidden = true;
    $("menu-backdrop").hidden = true;
  }

  $("more").addEventListener("click", openMenu);
  $("menu-backdrop").addEventListener("click", closeMenu);
  global.addEventListener("resize", closeMenu);
  $("menu-guide").addEventListener("click", () => {
    closeMenu();
    openGuide();
  });

  // ---- OLED: every 3 minutes the whole page moves by up to 2 px.
  const offsets = [[0, 0], [2, 1], [-1, 2], [-2, -1], [1, -2]];
  let step = 0;
  global.setInterval(() => {
    step = (step + 1) % offsets.length;
    // On the root, so the state card moves with the dashboard.
    global.document.documentElement.style.setProperty("--dx", offsets[step][0] + "px");
    global.document.documentElement.style.setProperty("--dy", offsets[step][1] + "px");
  }, 180000);

  /// The first visit gets the guide (its button starts the screen keeping); later visits the Start screen. A page
  /// without a key gets neither, but "⋯ → Kurulum rehberi" still works.
  function setup(texts, hasKey) {
    t = texts;
    if (!hasKey) return;
    if (guideDone()) $("start").hidden = false;
    else openGuide();
  }

  /// A wrong key or a pairing reset: the page is dead. The screen may sleep (the video stops and is not started again),
  /// and nothing asks for a tap that would keep it on: the Start screen and the guide go.
  function stopKeepAwake() {
    dead = true;
    started = false;
    video.pause();
    $("start").hidden = true;
    $("guide").hidden = true;
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.ui = {
    setup, openGuide, closeMenu, stopKeepAwake, isStarted: () => started,
    /// The Start screen or the guide is over the dashboard (the Start screen hides it, the guide all but).
    covers: () => !$("start").hidden || !$("guide").hidden,
    get menuOpenedAt() {
      return menuOpenedAt;
    },
    get menuClosedAt() {
      return menuClosedAt;
    },
  };
})(typeof window !== "undefined" ? window : globalThis);
