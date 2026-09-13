# Validation record

Validation date: 2026-09-14. Host: Apple silicon, macOS 26.5.2, Xcode 26.6, Swift 6.3.3. Toolchain: TeX Live 2025, latexmk 4.86a, BibTeX 0.99d, Biber 2.20, SyncTeX CLI 1.5.

## Automated results

| Check | Result |
| --- | --- |
| Swift package suite | 31 tests, zero failures, zero skips on this host |
| Offline suite | The same 31 tests passed with network access denied to the runner and descendants |
| Native Xcode Debug application | Built and launched |
| Xcode UI test target | Builds successfully; execution blocked by macOS automation initialization timeout |
| Release application | Builds for arm64 and x86_64 |
| Clean Release ZIP | Extracted into a fresh temporary directory; `codesign --verify --deep --strict` passed |
| Embedded dependencies | Only Apple frameworks and system Swift/runtime libraries; no embedded web runtime or third-party frameworks |
| Architecture scan | No WebSocket, CRDT, WKWebView, WebKit, URLSession, HTTP listener, or API-key references in application/core source |

The core tests include:

- Nested LaTeX outline titles, comments, Unicode offsets, labels/citations, matching nested environments, diagnostics, and SyncTeX parsing.
- UTF-8 BOM, UTF-16 BOM, CRLF round trips; undecodable-source rejection; external-change save conflicts; path traversal and escaping symlinks; reserved build-directory symlink rejection.
- History object deduplication, corruption detection, file diff, restore with retained newer history, and automatic snapshot behavior.
- Regex/Unicode search, replacement preview baselines, and preservation of external modifications.
- ZIP round trip, export filtering, malformed archive and symbolic-link rejection.
- Git status/staging, dirty branch-switch rejection, and refusal to initialize a nested repository.
- Large subprocess output drainage, cancellation before launch, and cancellation of descendant processes.
- A real two-page document in a folder with spaces, with a chapter, image, equation, table, contents, bibliography, resolved references, and forward/inverse SyncTeX.
- Rejection of executable project `.latexmkrc` content and preservation of previous PDF bytes after a failed scratch compile.
- Actual compilation of all ten templates; pdfLaTeX, XeLaTeX, LuaLaTeX, LaTeX → PDF; BibTeX and Biber.

Offline verification used:

```sh
/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' ./script/test.sh
```

This denied network access to the tests and TeX processes without disconnecting the user's whole Mac. It demonstrates the exercised local service workflow; it does not substitute for every manual UI acceptance check with the physical network disconnected.

## Native checks exercised

The bundled Research sample was opened in a separate verification application identity. Its native project navigator, NSTextView source, syntax coloring, line numbers, tab switching, PDFKit output, outline selection, source-to-PDF navigation, compile shortcut, full-screen layout, PDF zoom menu, project search, Settings, and tool discovery were exercised. Search returned four occurrences of “Knuth” across two sample files. Editing and native undo were also checked against the bundled sample during development.

The UI test source covers launch, sample opening, compilation/PDF creation, editing/saving/undo, search, inspector toggling, and Settings. Xcode's runner reported **“Timed out while enabling automation mode”**, before the test body executed. Do not report it as a passing UI test. Run `./script/test_ui.sh` in an Xcode-enabled graphical login session to complete that qualification. The separate identifier prevents tests from loading ordinary TeXium recents.

## Required before public release

- Run the automated UI suite successfully; expand it for template creation, error navigation, all insertion assistants, and native PDF/source export dialogs.
- Complete keyboard-only and VoiceOver testing, Full Keyboard Access, Light/Dark appearance, accent-color variants, and reduced-motion checks.
- Exercise all workflow actions with networking physically disconnected, including native history restore and both export dialogs.
- Validate older supported macOS versions, Intel execution, large projects/bibliographies/PDFs, external drives, moved folders, and disk-full recovery.
- Stress concurrent external editing, interrupted saves/restores, compiler cancellation under varied process trees, and crash recovery.
- Verify per-document undo expectations when switching source tabs; current undo is native within the active view and resets when switching files.
- Perform Developer ID signing, notarization, stapling, and clean-machine Gatekeeper acceptance. No public distribution has been performed.

## Packaging note

The host's Documents file provider can reattach `com.apple.FinderInfo` to an app directory after packaging. The build verifies a clean staged bundle, and Release also emits `dist/TeXium-macOS.zip` from that clean staging directory. That archive was extracted and signature-verified outside the provider-managed folder. Distribute the ZIP or a separately notarized package, rather than re-zipping a folder after a sync provider has attached metadata.
