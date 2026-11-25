// Screen-level behaviour (design §8): keeping the screen on, the Start screen, the first-run guide, the "⋯" menu and
// the OLED shift.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  const guideDoneKey = "phonebox-guide-done";
  let t = null;
  let started = false;

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
    if (started && global.document.visibilityState === "visible" && video.paused) keepAwake().catch(() => {});
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
    $("guide-link").value = global.location.href;
    $("guide-copy").textContent = t.copy;
    $("guide-done").textContent = started ? t.close : t.start;
    $("guide").hidden = false;
  }

  $("guide-done").addEventListener("click", () => {
    try {
      global.localStorage.setItem(guideDoneKey, "1");
    } catch (error) {}
    if (started) {
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
  function openMenu() {
    const menu = $("menu");
    menu.hidden = false;
    $("menu-backdrop").hidden = false;
    const button = $("more").getBoundingClientRect();
    menu.style.left = Math.max(8, Math.min(button.right - menu.offsetWidth, global.innerWidth - menu.offsetWidth - 8)) + "px";
    menu.style.top = Math.max(8, button.top - menu.offsetHeight - 8) + "px";
  }

  function closeMenu() {
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
    $("dashboard").style.setProperty("--dx", offsets[step][0] + "px");
    $("dashboard").style.setProperty("--dy", offsets[step][1] + "px");
  }, 180000);

  /// The first visit gets the guide (its button starts the screen keeping); later visits the Start screen.
  function setup(texts) {
    t = texts;
    if (guideDone()) $("start").hidden = false;
    else openGuide();
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.ui = { setup, openGuide, closeMenu, isStarted: () => started };
})(typeof window !== "undefined" ? window : globalThis);
