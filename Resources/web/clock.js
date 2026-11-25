// The phone's clock at the top of the page (design §8 "Saat ve telefonun pili"). `parts` is pure and tested in
// JavaScriptCore; `Clock` rolls a changed digit up and out and the new one in from below.
(function (global) {
  "use strict";

  const pad = (value) => String(value).padStart(2, "0");

  /// "09:05" (24-hour in both languages) and the date: "26 Kas Per" in Turkish, "Thu, Nov 26" in English.
  function parts(date, language) {
    const day = new Intl.DateTimeFormat(language, { weekday: "short", day: "numeric", month: "short" }).format(date);
    return { time: `${pad(date.getHours())}:${pad(date.getMinutes())}`, day };
  }

  class Clock {
    constructor(element) {
      this.element = element;
      this.text = "";
    }

    /// Shows `text`; with `still` ("Reduce Motion") the digits change without rolling.
    show(text, still) {
      if (text === this.text) return;
      const document = global.document;
      if (this.element.childElementCount !== text.length) {
        this.element.replaceChildren(...Array.from(text, (character) => {
          const cell = document.createElement("span");
          cell.className = character === ":" ? "clock-colon" : "clock-digit";
          if (character === ":") cell.textContent = ":";
          return cell;
        }));
      }
      Array.from(text).forEach((character, index) => {
        const cell = this.element.children[index];
        if (character === ":" || cell.dataset.value === character) return;
        cell.dataset.value = character;
        const old = cell.lastElementChild;
        if (old) {
          if (still) old.remove();
          else {
            old.className = "out";
            global.setTimeout(() => old.remove(), 700);
          }
        }
        const next = document.createElement("span");
        next.className = still ? "" : "in";
        next.textContent = character;
        cell.appendChild(next);
      });
      this.text = text;
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.clock = { parts, Clock };
})(typeof window !== "undefined" ? window : globalThis);
