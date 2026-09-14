# Validation record

Validation date: 2026-09-14. Host: Apple silicon, macOS 26.5.2, Xcode 26.6, Swift 6.3.3. Toolchain: TeX Live 2025, latexmk 4.86a, BibTeX 0.99d, Biber 2.20, SyncTeX CLI 1.5.

## Automated results

| Check | Result |
| --- | --- |
| Swift package suite | 41 tests, zero failures, zero skips on this host |
| Offline suite | The same 41 tests passed with network access denied to the runner and descendants |
| Native Xcode Debug application | Built and launched |
| Xcode Release UI tests | Three tests passed together: compiled-project restoration, authoring workflow, and uncompiled workspace layout |
| Release startup/restoration | Existing saved window state remained running through the extended 10-second launch check; no matching layout-constraint errors |
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
- Git status/staging, initial publication, two-writer fetch/pull/push, differently named upstream branches, dirty-worktree and divergence preservation, conflicts/detached HEAD, deleted remote branches, rejecting server hooks, destination mismatch, and refusal to initialize a nested repository.
- GitHub URL validation, credential-protocol host/account isolation, synthetic Keychain save/update/read/removal in a unique test service, and a headless credential-helper smoke check against an unrelated host. No real token was read or written.
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

The UI test source covers launch, sample opening, compilation/PDF creation, editing/saving/undo, search, inspector toggling, Settings, and saved-window restoration. All three native UI tests passed together in Release (141.254 seconds, zero failures), including actual compilation, editing/saving/undo, four search matches across two files, and Settings. Result bundle: `.build/UI-20260914-095253.xcresult`. The separate identifier prevents tests from loading ordinary TeXium recents.

The workspace layout regression opens a new uncompiled project, repeatedly hides/restores both sidebars, and shrinks the window. It asserts source viewport height, preview header/action alignment, and non-overlapping visible pane bounds. This test passed. Manual checks also verified all four sidebar combinations, the first compilation transition, and full screen. [Uncompiled workspace with both sidebars](screenshots/layout-uncompiled.jpg).

The reported launch crash occurred about 2.5 seconds after launch, during recursive AppKit constraint updates. Baseline tests reproduced the conflicting inspector-inset and native split-edge constraints even when the process recovered. `DocumentWorkspace` isolates the source/PDF split's safe areas and size measurement. After the fix, the Release app launched with its existing saved window state, and the original constraint-conflict/recursion messages were absent during launch and the final UI tests. The new regression compiles a disposable project, quits normally, restores both a full workspace and a compact source window, and checks pane bounds after repeated inspector toggles. Manual checks verified native divider dragging, PDF-only/combined layout switching, and full screen. [Verified compiled workspace](screenshots/layout-restored.jpg).

The launch script now watches the specific newly launched instance for ten seconds, catching delayed exits that its previous one-second process-name check missed. The rebuilt universal Release ZIP was extracted into a fresh temporary directory and passed strict signature verification.

## GitHub synchronization verification

The separate verification app exercised **Project → GitHub Synchronization**, the native commit review sheet with author identity, **Commit & Sync**, and a subsequent **Synchronize** that pulled a second writer's commit. Both repositories and the bare remote were disposable local fixtures. The inspector showed zero incoming/outgoing commits after success, and the open source buffer reloaded the incoming revision. The GitHub Settings tab was inspected, including its SecureField and Keychain controls. [Settings screenshot](screenshots/github-settings.jpg).

No real GitHub repository was pushed or changed during verification. Authenticated HTTPS/SSH operations against GitHub, expired/organization-restricted tokens, and Developer ID Keychain behavior across app updates still require account-based release qualification. The Keychain test requires a logged-in macOS session with Keychain access; a restricted tool sandbox returned a Keychain parameter error, while the normal macOS process passed save/update/read/removal. The final offline suite ran with normal filesystem/Keychain access and network access denied.

The universal Release ZIP was rebuilt with the feature, extracted outside the Documents file provider, and passed strict signature verification. The Release executable's credential-helper mode exited without opening SwiftUI or returning a credential for an unrelated host.

## Required before public release

- Expand the automated UI suite for template creation, error navigation, all insertion assistants, and native PDF/source export dialogs.
- Complete keyboard-only and VoiceOver testing, Full Keyboard Access, Light/Dark appearance, accent-color variants, and reduced-motion checks.
- Exercise all workflow actions with networking physically disconnected, including native history restore and both export dialogs.
- Validate older supported macOS versions, Intel execution, large projects/bibliographies/PDFs, external drives, moved folders, and disk-full recovery.
- Stress concurrent external editing, interrupted saves/restores, compiler cancellation under varied process trees, and crash recovery.
- Verify per-document undo expectations when switching source tabs; current undo is native within the active view and resets when switching files.
- Perform Developer ID signing, notarization, stapling, and clean-machine Gatekeeper acceptance. No public distribution has been performed.

## Packaging note

The host's Documents file provider can reattach `com.apple.FinderInfo` to an app directory after packaging. The build verifies a clean staged bundle, and Release also emits `dist/TeXium-macOS.zip` from that clean staging directory. That archive was extracted and signature-verified outside the provider-managed folder. Distribute the ZIP or a separately notarized package, rather than re-zipping a folder after a sync provider has attached metadata.
