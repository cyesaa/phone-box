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

  // State icons, drawn in the card's state colour. Fixed markup, never data.
  const icons = {
    question: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9.2 9a2.9 2.9 0 1 1 4 2.7c-.8.4-1.2 1-1.2 1.8v.6"/><path d="M12 17.4v.1"/></svg>',
    permission: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="8" cy="15" r="3.6"/><path d="M10.6 12.4 18 5m-3 3 2.2 2.2M17 6l2 2"/></svg>',
    turn: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5.5 12.5l4.2 4.2L18.5 7.8"/></svg>',
    working: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4a8 8 0 1 1-8 8"/></svg>',
    ready: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 8l4 4-4 4"/><path d="M13 16h4"/></svg>',
  };
  const states = ["waiting", "working", "ready"];

  // Written only when it changed: most seconds change nothing but the times.
  function setText(element, text) {
    if (element.textContent !== text) element.textContent = text;
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
      /// The Mac sends sessions (the feature is on): there are two pages.
      this.enabled = false;
      this.showing = "dashboard";
      this.stale = true;
      /// Each session's card, by id.
      this.cards = new Map();
      /// The list's columns and rows as last written, so an unchanged layout is not written again.
      this.layout = "";
      this.arrivalTimer = 0;
      this.wireSwipe();
      global.addEventListener("resize", () => this.fit());
    }

    /// Each snapshot's `claude` list (null or undefined while the feature is off) and the snapshot's time `now` (the
    /// Mac's ms, like each session's `since`).
    render(sessions, now) {
      const enabled = Array.isArray(sessions);
      if (enabled !== this.enabled) {
        this.enabled = enabled;
        if (!enabled) this.show("dashboard");
        this.page.hidden = !enabled;
        $("page-dots").hidden = !enabled;
        // The dashboard's own slide (its transition) while there are two pages.
        $("dashboard").classList.toggle("paged", enabled);
        this.layout = "";
      }
      if (!enabled) {
        this.list.replaceChildren();
        this.cards.clear();
        return;
      }
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
          // A card that turns up while the page shows comes in by itself; the others come in with the page.
          if (!still && this.showing === "claude" && !this.page.classList.contains("arriving")) {
            const element = card.element;
            element.classList.add("enter");
            global.setTimeout(() => element.classList.remove("enter"), entry + 100);
          }
        }
        this.fill(card, session, index, now);
      });
      for (const [id, card] of this.cards) {
        if (current.has(id)) continue;
        this.cards.delete(id);
        this.drop(card.element, still);
      }
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
      setText(card.parts.name, String(session.title || session.project || "Claude"));
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
      }
    }

    /// A gone session's card fades out where it can be seen, else it goes at once.
    drop(element, still) {
      if (still || this.stale || this.showing !== "claude") {
        element.remove();
        return;
      }
      element.classList.add("leaving");
      global.setTimeout(() => element.remove(), fadeOut);
    }

    /// The columns (`columns()`), and compact cards when the normal ones would not fit: in landscape when there are
    /// more than two rows, in portrait when they would run past the bottom.
    fit() {
      if (!this.enabled) return;
      const list = this.list;
      const count = this.cards.size;
      const landscape = global.matchMedia("(orientation: landscape)").matches;
      const columns = PB().claude.columns(count, landscape);
      const rows = Math.ceil(count / columns);
      // At least two rows: one or two sessions get cards the size of four, not cards the height of the screen.
      const layout = `${columns} ${Math.max(2, rows)}`;
      if (layout !== this.layout) {
        this.layout = layout;
        list.style.setProperty("--columns", String(columns));
        list.style.setProperty("--rows", String(Math.max(2, rows)));
      }
      if (landscape) {
        list.classList.toggle("compact", rows > 2);
        return;
      }
      list.classList.remove("compact");
      list.classList.toggle("compact", list.scrollHeight > list.clientHeight + 1);
    }

    /// Slides to `page` ("claude" or "dashboard"); without sessions only the dashboard is there.
    show(page) {
      const claude = page === "claude" && this.enabled;
      const next = claude ? "claude" : "dashboard";
      if (next === this.showing) return;
      this.showing = next;
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
