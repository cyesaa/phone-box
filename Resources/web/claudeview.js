// The Claude Code page (design §14): a second page below the dashboard with a card for each of the Mac's Claude Code
// sessions. When it shows, the dashboard slides up out of view and this page comes in from below; a vertical swipe
// switches pages. Cards are kept by session id and changed in place, so their animations run on: new ones come in,
// gone ones fade out. Text always goes in with textContent: titles and folder names come from the Mac's sessions.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  const PB = () => global.PhoneBox;
  /// How long a gone card fades out (ms).
  const fadeOut = 350;
  /// How long the cards take to come in, one after another, once the page starts sliding in (ms; styles.css).
  const arrival = 1800;
  /// How long a card that turns up on the page takes to come in (ms; styles.css).
  const entry = 600;
  /// How long the pages slide (ms; styles.css).
  const slide = 800;

  // State icons, drawn in the card's state colour. Fixed markup, never data.
  const icons = {
    question: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9.2 9a2.9 2.9 0 1 1 4 2.7c-.8.4-1.2 1-1.2 1.8v.6"/><path d="M12 17.4v.1"/></svg>',
    permission: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="8" cy="15" r="3.6"/><path d="M10.6 12.4 18 5m-3 3 2.2 2.2M17 6l2 2"/></svg>',
    turn: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5.5 12.5l4.2 4.2L18.5 7.8"/></svg>',
    working: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4a8 8 0 1 1-8 8"/></svg>',
    ready: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 8l4 4-4 4"/><path d="M13 16h4"/></svg>',
  };
  const states = ["waiting", "working", "ready"];

  // Written only when it changed: most seconds change nothing but the times. True when it changed.
  function setText(element, text) {
    if (element.textContent === text) return false;
    element.textContent = text;
    return true;
  }

  function setHidden(element, hidden) {
    if (element.hidden !== hidden) element.hidden = hidden;
  }

  class ClaudeView {
    /// `pager` hears about the user's swipes; `clock` is the dashboard's clock, whose time the page's header shows.
    constructor(t, pager, clock) {
      this.t = t;
      this.pager = pager;
      this.source = clock;
      this.clock = new (PB().clock.Clock)($("claude-clock"));
      this.page = $("claude-page");
      this.list = $("claude-list");
      this.more = $("claude-more");
      /// The Mac sends sessions (the feature is on): there are two pages.
      this.enabled = false;
      this.showing = "dashboard";
      /// When `showing` last changed (`performance.now()`).
      this.shownAt = -Infinity;
      this.stale = true;
      /// Each session's card, by id.
      this.cards = new Map();
      /// Cards of gone sessions that are still fading out: they keep their place in the grid until they are removed.
      this.leaving = new Set();
      /// The list's columns and rows as last written, so an unchanged layout is not written again.
      this.layout = "";
      /// The cards have to be measured again (portrait): the set of cards, a title or the screen changed.
      this.measure = true;
      /// Hides the page once the dashboard has slid back after the feature was turned off.
      this.closeTimer = 0;
      this.arrivalTimer = 0;
      this.wireSwipe();
      const remeasure = () => {
        this.measure = true;
        this.fit();
      };
      global.addEventListener("resize", remeasure);
      // Turning the phone: iOS may still report the old sizes for a moment, and screen.js sets `--screen-height` again
      // 300 ms after turning without a `resize`; measured once more after that.
      global.addEventListener("orientationchange", () => {
        remeasure();
        global.setTimeout(remeasure, 350);
      });
    }

    /// Each snapshot's `claude` list (null or undefined while the feature is off) and the snapshot's time `now` (the
    /// Mac's ms, like each session's `since`).
    render(sessions, now) {
      const enabled = Array.isArray(sessions);
      if (enabled !== this.enabled) {
        this.enabled = enabled;
        this.layout = "";
        global.clearTimeout(this.closeTimer);
        if (enabled) {
          this.setPaged(true);
        } else if (this.showing === "claude" && !PB().motion.reduced()) {
          // Turned off while the page shows: the dashboard slides back down as after a swipe (`.paged` gives it the
          // swipe's transition), and the page goes once the slide is over.
          this.show("dashboard");
          this.closeTimer = global.setTimeout(() => this.setPaged(false), slide + 50);
        } else {
          this.show("dashboard");
          // With "Reduce Motion" the dashboard is back at once: its place is settled under `.paged`, before the class
          // and its transition go.
          void $("dashboard").offsetWidth;
          this.setPaged(false);
        }
      }
      if (!enabled) return;
      const t = this.t;
      const still = PB().motion.reduced();
      const waiting = sessions.filter((session) => session && session.state === "waiting").length;
      setText($("claude-count"), t.claudeSessions(sessions.length));
      setText($("claude-waiting"), waiting ? t.claudeWaiting(waiting) : "");
      setHidden($("claude-empty"), sessions.length > 0);

      const current = new Set();
      sessions.forEach((session, index) => {
        if (!session) return;
        const id = String(session.id);
        current.add(id);
        let card = this.cards.get(id);
        if (!card) {
          card = this.makeCard();
          this.cards.set(id, card);
          this.list.appendChild(card.element);
          this.measure = true;
          // A card that turns up while the page shows comes in by itself; the others come in with the page.
          if (!still && this.showing === "claude" && !this.page.classList.contains("arriving")) {
            const element = card.element;
            element.classList.add("enter");
            global.setTimeout(() => element.classList.remove("enter"), entry + 100);
          }
        }
        this.fill(card, session, index, now);
      });
      const gone = [];
      for (const [id, card] of this.cards) {
        if (current.has(id)) continue;
        this.cards.delete(id);
        gone.push(card.element);
      }
      if (gone.length) this.drop(gone, still);
      this.fit();
    }

    makeCard() {
      const element = global.document.createElement("article");
      element.className = "claude-card";
      element.innerHTML = '<span class="claude-icon"></span><span class="claude-state"></span><span class="claude-time"></span>'
        + '<span class="claude-name"></span><span class="claude-bar"></span><span class="claude-chips"><i></i><i></i></span>';
      const [icon, state, time, name, , chips] = element.children;
      return { element, icon: null, index: -1, parts: { icon, state, time, name, project: chips.children[0], model: chips.children[1] } };
    }

    fill(card, session, index, now) {
      const claude = PB().claude;
      const state = states.includes(session.state) ? session.state : "ready";
      const icon = state !== "waiting" ? state : session.reason === "question" || session.reason === "permission" ? session.reason : "turn";
      const element = card.element;
      for (const name of states) element.classList.toggle(name, name === state);
      if (card.icon !== icon) {
        card.icon = icon;
        card.parts.icon.innerHTML = icons[icon];
      }
      setText(card.parts.state, claude.stateText(this.t, session));
      setText(card.parts.time, claude.elapsed(this.t, now - session.since));
      // A title can take one line or two.
      if (setText(card.parts.name, String(session.title || session.project || "Claude"))) this.measure = true;
      const project = session.project ? String(session.project) : "";
      const model = session.model ? String(session.model) : "";
      setText(card.parts.project, project);
      setHidden(card.parts.project, !project);
      setText(card.parts.model, model);
      setHidden(card.parts.model, !model);
      // The Mac's order (waiting first) by the grid's `order`, not by moving the element: a moved element would start
      // its animations over.
      if (card.index !== index) {
        card.index = index;
        element.style.order = String(index);
        element.style.setProperty("--i", String(index));
        // Which cards are cut (portrait) depends on the order.
        this.measure = true;
      }
    }

    /// The cards of gone sessions fade out where they can be seen, else they go at once. While they fade they keep their
    /// places in the grid; once they are gone the grid is fitted again, once for all of them.
    drop(elements, still) {
      this.measure = true;
      if (still || this.stale || this.showing !== "claude") {
        for (const element of elements) element.remove();
        return;
      }
      for (const element of elements) {
        element.classList.add("leaving");
        this.leaving.add(element);
      }
      global.setTimeout(() => {
        let removed = false;
        for (const element of elements) {
          if (!this.leaving.delete(element)) continue;
          element.remove();
          removed = true;
        }
        if (!removed) return;
        this.measure = true;
        this.fit();
      }, fadeOut);
    }

    /// Two pages (the feature is on), or only the dashboard; without the second page its cards go.
    setPaged(paged) {
      this.page.hidden = !paged;
      $("page-dots").hidden = !paged;
      // The dashboard's own slide (its transition) while there are two pages.
      $("dashboard").classList.toggle("paged", paged);
      if (paged) return;
      this.list.replaceChildren();
      this.cards.clear();
      this.leaving.clear();
    }

    /// The grid (`grid()`, counting the cards still fading out), and compact cards when the normal ones would not
    /// fit: in landscape when there are more than two rows, in portrait when they would run past the bottom. Portrait
    /// cards are measured only when that can have changed: measuring right after `render`'s writes would make the
    /// browser lay the page out again every second.
    fit() {
      if (!this.enabled) return;
      const list = this.list;
      const landscape = global.matchMedia("(orientation: landscape)").matches;
      const { columns, rows } = PB().claude.grid(this.cards.size + this.leaving.size, landscape);
      const layout = `${columns} ${rows} ${landscape}`;
      if (layout !== this.layout) {
        this.layout = layout;
        this.measure = true;
        list.style.setProperty("--columns", String(columns));
        list.style.setProperty("--rows", String(rows));
      }
      if (landscape) {
        list.classList.toggle("compact", rows > 2);
        this.cut(0);
        return;
      }
      if (!this.measure) return;
      this.measure = false;
      this.cut(0);
      list.classList.remove("compact");
      list.classList.toggle("compact", this.reach() > list.clientHeight + 1);
      // Even compact cards do not fit (many sessions on a small phone): only the cards that fit completely stay, the
      // lowest-ranked ones go, and a line under them says how many. No scrolling.
      if (this.reach() > list.clientHeight + 1) this.cutToFit();
    }

    /// How far down the list the cards reach where they rest. Cards are measured by their place in the layout (the list
    /// is their offset parent, styles.css), not where they are on screen: a card that is still coming in is drawn up to
    /// 24 px lower (`scrollHeight` counts that too), and nothing measures again once it has arrived.
    reach() {
      let bottom = 0;
      for (const element of this.ordered()) bottom = Math.max(bottom, element.offsetTop + element.offsetHeight);
      return bottom;
    }

    /// The cards in the Mac's order, the ones fading out in their places too.
    ordered() {
      return Array.from(this.list.querySelectorAll(".claude-card")).sort((a, b) => Number(a.style.order) - Number(b.style.order));
    }

    /// Shows the cards from the `keep`-th on again or hides them (all shown when `keep` is 0), and the "more" line with
    /// the number of cards hidden. Cards that are fading out are not counted.
    cut(keep) {
      let hidden = 0;
      this.ordered().forEach((element, index) => {
        const cut = keep > 0 && index >= keep;
        element.classList.toggle("cut", cut);
        if (cut && !this.leaving.has(element)) hidden += 1;
      });
      setHidden(this.more, hidden === 0);
      if (hidden) setText(this.more, this.t.claudeMore(hidden));
    }

    /// Hides the cards that run past the bottom, leaving room for the "more" line under the last one that fits.
    cutToFit() {
      const list = this.list;
      // The line takes its place first, so that the list's height is what is left for the cards.
      setText(this.more, this.t.claudeMore(this.cards.size));
      setHidden(this.more, false);
      const room = list.clientHeight + 1;
      const elements = this.ordered();
      // Where each card rests, as in `reach`.
      let keep = 0;
      while (keep < elements.length && elements[keep].offsetTop + elements[keep].offsetHeight <= room) keep += 1;
      this.cut(Math.max(1, keep));
    }

    /// Slides to `page` ("claude" or "dashboard"); without sessions only the dashboard is there.
    show(page) {
      const claude = page === "claude" && this.enabled;
      const next = claude ? "claude" : "dashboard";
      if (next === this.showing) return;
      this.showing = next;
      this.shownAt = global.performance.now();
      const dashboard = $("dashboard");
      // The page may have been shown just now: its slide needs a place to start from.
      void this.page.offsetWidth;
      this.page.classList.toggle("on", claude);
      dashboard.classList.toggle("away", claude);
      // Only the page in view takes focus and VoiceOver.
      this.page.toggleAttribute("inert", !claude);
      dashboard.toggleAttribute("inert", claude);
      const [top, bottom] = $("page-dots").children;
      top.classList.toggle("on", !claude);
      bottom.classList.toggle("on", claude);
      // The cards come in one after another behind the sliding page (none with "Reduce Motion").
      global.clearTimeout(this.arrivalTimer);
      this.page.classList.remove("arriving");
      if (claude && !PB().motion.reduced()) {
        this.page.classList.add("arriving");
        this.arrivalTimer = global.setTimeout(() => this.page.classList.remove("arriving"), arrival);
      }
    }

    /// The Claude page is over the whole dashboard at `now` (a frame's time): it shows and has finished sliding in.
    covers(now) {
      return this.showing === "claude" && now - this.shownAt >= slide;
    }

    /// Stale data dims the page like the dashboard, and stops what would look live.
    setStale(stale) {
      this.stale = stale;
      this.page.classList.toggle("stale", stale);
    }

    /// On every animation frame: the dashboard clock's time in the page's header.
    frame() {
      if (this.enabled) this.clock.show(this.source.text, PB().motion.reduced() || this.stale);
    }

    /// The sheet, the confirmation, the "⋯" menu, the guide or the Start screen is open: a swipe does nothing.
    covered() {
      return $("sheet").classList.contains("show") || $("confirm").classList.contains("show") || !$("menu").hidden
        || !$("guide").hidden || !$("start").hidden;
    }

    // A vertical swipe anywhere switches pages (up to the Claude page, down to the dashboard); a tap works as before.
    // The volume slider keeps its own drags.
    wireSwipe() {
      const document = global.document;
      let start = null;
      document.addEventListener("touchstart", (event) => {
        start = null;
        if (!this.enabled || event.touches.length !== 1 || this.covered()) return;
        if (event.target && event.target.closest && event.target.closest("#volume")) return;
        start = { x: event.touches[0].clientX, y: event.touches[0].clientY };
      }, { passive: true });
      // While a swipe may be under way the page itself must not move: no rubber band, no pull to refresh in Chrome.
      document.addEventListener("touchmove", (event) => {
        if (start && event.cancelable) event.preventDefault();
      }, { passive: false });
      document.addEventListener("touchend", (event) => {
        const from = start;
        start = null;
        if (!from || !this.enabled || this.covered() || !event.changedTouches.length) return;
        const touch = event.changedTouches[0];
        const page = PB().claude.swipe(touch.clientX - from.x, touch.clientY - from.y);
        if (!page || page === this.showing) return;
        this.pager.userShowed(page);
        this.show(page);
      });
      document.addEventListener("touchcancel", () => {
        start = null;
      });
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.ClaudeView = ClaudeView;
})(typeof window !== "undefined" ? window : globalThis);
