// How tall the page's full-screen layers are in a Home Screen web app (design §8). After the phone turns, iOS can
// leave such a page's viewport shorter than the screen (seen on an iPhone in landscape: an empty band at the bottom,
// about the height of the portrait status bar), so layers pinned to the viewport end early. A Home Screen web app
// always fills the screen, so there the layers take the screen's height (`--screen-height` on the root); in a
// browser tab, whose bars take room, CSS decides as before.
(function (global) {
  "use strict";

  /// The height in CSS px for the full-screen layers, or null to leave it to CSS: only in a Home Screen web app whose
  /// window is as wide as the screen in that orientation (not in a browser tab, not in a narrower window).
  /// `screenWidth`/`screenHeight` are `screen.width`/`screen.height`, which iOS keeps in portrait terms.
  function fullScreenHeight(standalone, landscape, screenWidth, screenHeight, innerWidth) {
    if (!standalone) return null;
    const long = Math.max(screenWidth, screenHeight);
    const short = Math.min(screenWidth, screenHeight);
    if (!(short > 0)) return null;
    if (Math.abs(innerWidth - (landscape ? long : short)) > 1) return null;
    return landscape ? short : long;
  }

  function apply() {
    const standalone = global.navigator.standalone === true || global.matchMedia("(display-mode: standalone)").matches;
    const landscape = global.matchMedia("(orientation: landscape)").matches;
    const height = fullScreenHeight(standalone, landscape, global.screen.width, global.screen.height, global.innerWidth);
    const root = global.document.documentElement.style;
    if (height === null) root.removeProperty("--screen-height");
    else root.setProperty("--screen-height", height + "px");
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.fullScreenHeight = fullScreenHeight;

  if (global.document && global.addEventListener) {
    apply();
    global.addEventListener("resize", apply);
    // iOS may report the old sizes for a moment after turning.
    global.addEventListener("orientationchange", () => {
      apply();
      global.setTimeout(apply, 300);
    });
  }
})(typeof window !== "undefined" ? window : globalThis);
