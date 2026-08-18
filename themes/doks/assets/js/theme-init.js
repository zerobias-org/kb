// Presentation init, inlined synchronously in <head> so both attributes below are
// set before first paint.
//
// Theme is controlled by the parent window (kbViewer / UI app) via postMessage.
// Listen for theme_change messages and apply dark mode attribute accordingly.
// No localStorage or system preference — the parent is the source of truth.

// Mark the document as embedded so base_zb.css can drop to its app-root type scale
// (see the two-context block in that sheet: standalone reads at 1rem, embedded at
// .9rem, because a full-size article beside the platform's dense chrome reads
// oversized). The parent CANNOT set this — the article is cross-origin — so the
// document has to decide for itself, using the same embedded test KBNavClick uses.
//
// Set synchronously here rather than on load: this script is inlined in <head>, so
// the attribute is present before first paint and the article never flashes the
// standalone scale before shrinking.
if (window.self !== window.top) {
  document.documentElement.setAttribute('app-root', '');
}

// Only the window that embedded this article may drive its theme. Checked by SOURCE
// rather than by an origin allowlist on purpose: the legitimate embedders span four
// portal environments, kbviewer and local dev, and a hardcoded list of those goes
// stale silently — the failure mode is an article that stops following the app's
// theme, with nothing in the console to say why. Comparing against window.parent
// needs no list and cannot miss a valid embedder, while still ignoring anything
// posted by another frame or window.
window.addEventListener('message', function(event) {
  if (event.source !== window.parent) { return; }
  if (event.data && event.data.type === 'theme_change') {
    if (event.data.isDark) {
      document.documentElement.setAttribute('data-dark-mode', '');
    } else {
      document.documentElement.removeAttribute('data-dark-mode');
    }
  }
});
