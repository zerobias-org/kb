//  ⚠ THIS THEME IS VENDORED IN TWO REPOSITORIES. CHANGE BOTH, IN THE SAME BREATH.
//
//    auditlogic/kb    themes/doks/   -> the kb fleet, and ct articles built from
//                                      @auditlogic/module-* packages
//    zerobias-org/kb  themes/doks/   -> ct articles built from @zerobias-org/module-*
//
//  They are separate copies with no sync mechanism and no shared owner. Both render into
//  the same /kb/ and /ct/ CDN namespaces, so a fix applied to one leaves the other's
//  articles serving the old behaviour — and nothing anywhere reports the gap.
//
//  This is not hypothetical. It is how the ct link-interception bug survived being
//  "fixed": the handler was corrected in one copy and stayed broken in the other. It is
//  also how the og:image 404 was fixed, verified, and still live for every ct article.
//
//  Sync direction is auditlogic/kb -> zerobias-org/kb. Copying the other way rolls back
//  theme work that only exists in auditlogic.
//
//  A rendered article is static HTML: nothing here reaches the CDN until the articles are
//  re-rendered, in BOTH pipelines.
//
//  -- The two tickets named above --------------------------------------------------
//  ⚠ A task CODE is not unique. Codes are minted per board, so every board in every org
//  has its own task-269. The UUID is the only stable identity — resolve by that, and
//  treat a bare code in any doc or commit message as ambiguous until you have the UUID.
//
//  Both are on the ZeroBias PROD platform, https://app.zerobias.com, org "ZeroBias"
//  57c741cf-a58e-5efc-bf2f-93c4f6cf76ec, Platform boundary
//  14188507-e63d-402b-964d-2b50db5b783c:
//
//    ae296b38-523b-4ba3-a5d8-757b1b87bbe2   (shown there as task-269)
//      board: UI Bugs  8f0fbc2d-be4f-449b-be0c-50106f95b84b
//      "KB article only posts KBNavClick to the parent for 'kb' links, never 'ct'"
//      https://app.zerobias.com/resource/ae296b38-523b-4ba3-a5d8-757b1b87bbe2
//
//    9ec8f1ef-2fdb-42e9-a395-4a08d54ca81a   (shown there as task-254)
//      board: UI Feature Requests  5631d499-16cd-4767-96c2-177650d780fd
//      "Fix Slack/OpenGraph link previews for KB articles (og:url and og:image both 404)"
//      https://app.zerobias.com/resource/9ec8f1ef-2fdb-42e9-a395-4a08d54ca81a

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
