// The Claude Code page's rules (design §14): when the page comes by itself and when it goes back (`Pager`), the
// card's texts and how the cards are laid out. Pure and tested in JavaScriptCore (WebClaudeTests); claudeview.js puts
// them on the page.
(function (global) {
  "use strict";

  /// A page that came by itself goes back once no session has waited for this long (ms).
  const closeAfter = 3000;
  /// A swipe moves the finger further than this (px), and more up or down than sideways.
  const swipeDistance = 40;

  const pad = (value) => String(value).padStart(2, "0");

  /// One key for each session waiting for the user, and a new one each time it starts waiting again.
  function waitingKeys(sessions) {
    return sessions.filter((session) => session && session.state === "waiting").map((session) => `${session.id}:${session.since}`);
  }

  /// Which page shows. `update` is called with every snapshot's sessions and returns "open" or "close" when the page
  /// should move by itself, else null; `userShowed` tells it the user swiped to a page.
  class Pager {
    constructor() {
      this.on = false;
      /// The page came by itself (it goes back by itself too).
      this.auto = false;
      /// The waits the user has seen, among the current ones.
      this.seen = new Set();
      this.keys = [];
      /// Since when (ms) nothing has waited while the page that came by itself shows; null while something waits.
      this.calmSince = null;
    }

    get onClaude() {
      return this.on;
    }

    /// `sessions` is the snapshot's `claude` list, or null/undefined when the feature is off. `now` is in ms.
    update(sessions, now) {
      if (!Array.isArray(sessions)) {
        // The feature is off. The seen waits are kept: a snapshot without the list says nothing about the sessions.
        const was = this.on;
        this.on = false;
        this.auto = false;
        this.calmSince = null;
        this.keys = [];
        return was ? "close" : null;
      }
      const keys = waitingKeys(sessions);
      this.keys = keys;
      this.seen = new Set(keys.filter((key) => this.seen.has(key)));
      if (!this.on) {
        if (keys.every((key) => this.seen.has(key))) return null;
        this.seeAll();
        this.on = true;
        this.auto = true;
        this.calmSince = null;
        return "open";
      }
      // On the Claude page every wait counts as seen.
      this.seeAll();
      if (!this.auto) return null;
      if (keys.length) {
        this.calmSince = null;
        return null;
      }
      if (this.calmSince === null) this.calmSince = now;
      if (now - this.calmSince < closeAfter) return null;
      this.on = false;
      this.auto = false;
      this.calmSince = null;
      return "close";
    }

    /// The user swiped to `page` ("claude" or "dashboard"): what waits now has been seen, and the page stays where the
    /// user put it until a new wait begins.
    userShowed(page) {
      this.seeAll();
      this.on = page === "claude";
      this.auto = false;
      this.calmSince = null;
    }

    seeAll() {
      for (const key of this.keys) this.seen.add(key);
    }
  }

  /// How long a state has lasted: "0:42" and "9:59" under 10 minutes, then "12 dk", then "2 sa".
  function elapsed(t, ms) {
    const seconds = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
    if (seconds < 600) return `${Math.floor(seconds / 60)}:${pad(seconds % 60)}`;
    if (seconds < 3600) return t.claudeMinutes(Math.floor(seconds / 60));
    return t.claudeHours(Math.floor(seconds / 3600));
  }

  /// The state's words: why it waits, what it does, or "Hazır".
  function stateText(t, session) {
    if (session.state === "waiting") return t.claudeReason[session.reason] || t.claudeReason.turn;
    if (session.state === "working") return t.claudeActivity[session.activity] || t.claudeActivity.think;
    return t.claudeReady;
  }

  /// One column in portrait; in landscape two up to 4 sessions, else three.
  function columns(count, landscape) {
    if (!landscape) return 1;
    return count <= 4 ? 2 : 3;
  }

  /// The cards' grid: `columns()` columns and as many rows as the cards fill (at least one). In landscape the rows share
  /// the page's height, so one session is one tall card in the left column and two are two tall cards.
  function grid(count, landscape) {
    const across = columns(count, landscape);
    return { columns: across, rows: Math.max(1, Math.ceil(count / across)) };
  }

  /// The page a finger's move (px; up is negative) goes to: the Claude page lies below the dashboard. Null for a move
  /// that is short or mostly sideways.
  function swipe(dx, dy) {
    if (Math.abs(dy) <= swipeDistance || Math.abs(dy) <= Math.abs(dx)) return null;
    return dy < 0 ? "claude" : "dashboard";
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.claude = { Pager, elapsed, stateText, columns, grid, swipe };
})(typeof window !== "undefined" ? window : globalThis);
