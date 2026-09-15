# Validation record

Validation date: 2026-09-14. Host: Apple silicon, macOS 26.5.2, Xcode 26.6, Swift 6.3.3. Toolchain: TeX Live 2025, latexmk 4.86a, BibTeX 0.99d, Biber 2.20, SyncTeX CLI 1.5.

## Automated results

| Check | Result |
| --- | --- |
| Swift package service baseline | 41 tests, zero failures, zero skips before the syntax-color feature |
| Offline service baseline | The same 41 tests passed with network access denied to the runner and descendants |
| Syntax palette and highlighter | Five focused tests passed with zero failures |
| Context completion engine | 15 focused tests passed with zero failures |
| Context completion native UI | Command/heading snippets, label and citation lookup, argument navigation, dismissal, and undo passed in the isolated Debug app |
| Native Xcode Debug application | Built and launched |
| Xcode Release UI baseline | Three tests passed together before the syntax-color feature: compiled-project restoration, authoring workflow, and uncompiled workspace layout |
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

The in-app synchronization verification used disposable local repositories; it did not exercise authenticated GitHub synchronization. Repository changes and release assets were later pushed with the GitHub CLI. Authenticated HTTPS/SSH operations from TeXium, expired/organization-restricted tokens, and Developer ID Keychain behavior across app updates still require account-based release qualification. The Keychain test requires a logged-in macOS session with Keychain access; a restricted tool sandbox returned a Keychain parameter error, while the normal macOS process passed save/update/read/removal. The final offline suite ran with normal filesystem/Keychain access and network access denied.

The universal Release ZIP was rebuilt with the feature, extracted outside the Documents file provider, and passed strict signature verification. The Release executable's credential-helper mode exited without opening SwiftUI or returning a credential for an unrelated host.

## Syntax color customization verification

In the separate verification app, **Settings → Syntax Colors** changed commands to orange and comments to green using hex fields. The open editor recolored immediately while its source remained unchanged and saved. Both colors persisted after a normal quit and relaunch. Individual reset retained the other custom color, and Restore Default Colors cleared all overrides. The final build also verified that resetting while a hex field is focused refreshes the field to match the default color. [Settings](screenshots/syntax-colors.jpg) and [live editor colors](screenshots/syntax-custom-editor.jpg).

`./script/test.sh --filter SyntaxHighlightingTests` passed five tests covering hex validation, UserDefaults persistence, individual resets, malformed preference recovery, all seven text categories, comment precedence, incremental recoloring, disabling highlighting, and preservation of source text and unrelated attributes. The final native Debug test build and universal Release build succeeded; Release remained running through its ten-second startup check. The final Release ZIP passed strict signature verification after extraction to a fresh temporary directory.

The GUI automation runner could not reliably activate Settings for a native color-panel interaction probe, so native panel selection is not recorded as an automated pass. The hex-field workflow and resets were verified through the application's native interface. The existing three-test workspace UI result above remains a baseline from before this feature.

## Context-aware completion verification

`./script/test.sh --filter CompletionTests` passed 15 tests. Coverage includes command snippets and argument stops, command replacement within existing code, reference variants, section-title lookup, citation metadata and substring search, optional citation arguments, comma-separated keys, CRLF/Unicode offsets, live-buffer replacement of stale symbols, custom macro signatures and overrides, filtered file/environment suggestions, duplicate keys, and comment/literal exclusions.

The focused native test passed against the final Debug application in 26.108 seconds: `.build/UI-20260914-122943.xcresult`. It exercised automatic popup display, section-heading insertion, referencing a label by its heading title, citing a bibliography entry by its book title, Tab/Return acceptance, multiple argument stops, Escape dismissal, and single-edit undo. One intermediate run failed at initial popup detection while Release startup and UI automation overlapped; the sequential rerun passed without further application changes.

Manual checks in a disposable project verified the visible label list with section titles and file locations, explicit completion, arrow selection, and mouse acceptance while the editor retained focus. [Completion screenshot](screenshots/context-completion.jpg). The final universal Release app passed the ten-second startup/restoration probe, and its ZIP passed strict signature verification after extraction into a clean temporary directory.

Completion uses local source analysis rather than a TeX interpreter or online language service. Full IME/VoiceOver coverage, unusual macro/category-code conventions, and large-document performance remain part of release qualification. See [completion behavior and shortcuts](COMPLETION.md).

## PDF download verification

The Download PDF toolbar button was checked in the isolated verification app with a disposable project: it appears immediately beside Compile, is disabled before the first PDF exists, and becomes enabled after successful compilation. It opens the existing native PDF save dialog. The saved PDF matched the compiled preview byte for byte. Native Debug and universal Release builds passed.

## Complete environment template verification

`./script/test.sh --filter Completion` passed 27 tests with zero failures or skips. The 12 template tests cover complete figure/list/table structures, selected defaults and field navigation, required environment arguments, nested same-name environments, preservation of existing options/bodies/ends, both closing-brace positions and missing braces, custom indentation, CRLF/UTF-16 offsets, command options, and valid ordered fields across the catalog. The compilation test fills the generated figure, itemize, enumerate, description, table, tabularx, equation, matrix, minipage, and frame templates, builds article and Beamer PDFs with the normal compilation service, and checks rendered text.

The isolated Debug app passed the context completion regression (27.279 seconds) and complete template workflow (23.264 seconds), recorded in `.build/UI-20260914-173850.xcresult`. The template workflow accepts a figure through `\begin{}`, replaces its image/caption/label fields, returns to an edited caption with Shift-Tab, accepts and undoes an enumerate template, and completes itemize after typing its closing brace. A separate test with brace closure disabled and two-space indentation passed in 8.679 seconds in `.build/UI-20260914-173607.xcresult`, against the same application source. Initial test failures were traced to a lost first synthetic backslash and the native undo operation selecting the restored token; the rerun primes keyboard input and collapses that selection before explicitly requesting suggestions.

The successful native screenshot was inspected for complete structures and indentation: [figure and list templates](screenshots/completion-templates.png). The universal Release app was rebuilt, relaunched, and remained running through the ten-second restoration check. The Release ZIP was extracted to a clean temporary directory, passed strict signature verification, and contained both arm64 and x86_64 executable slices.

## Required before public release

- Expand the automated UI suite for template creation, error navigation, all insertion assistants, and native PDF/source export dialogs.
- Complete keyboard-only and VoiceOver testing, Full Keyboard Access, Light/Dark appearance, accent-color variants, and reduced-motion checks.
- Exercise all workflow actions with networking physically disconnected, including native history restore and both export dialogs.
- Validate older supported macOS versions, Intel execution, large projects/bibliographies/PDFs, external drives, moved folders, and disk-full recovery.
- Stress concurrent external editing, interrupted saves/restores, compiler cancellation under varied process trees, and crash recovery.
- Verify per-document undo expectations when switching source tabs; current undo is native within the active view and resets when switching files.
- Perform Developer ID signing, notarization, stapling, and clean-machine Gatekeeper acceptance. The public 1.0.0 developer build does not satisfy this requirement.

## Packaging note

The host's Documents file provider can reattach `com.apple.FinderInfo` to an app directory after packaging. The build verifies a clean staged bundle, and Release also emits `dist/TeXium-macOS.zip` from that clean staging directory. That archive was extracted and signature-verified outside the provider-managed folder. Distribute the ZIP or a separately notarized package, rather than re-zipping a folder after a sync provider has attached metadata.
