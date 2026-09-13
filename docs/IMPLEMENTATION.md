# Implementation plan

The starting workspace was empty: no Xcode project, package, dependencies, persistence, deployment target, or Git repository. TeXium targets macOS 14 and later, builds with Xcode 26, and uses no third-party application dependencies.

1. Native foundation: Xcode application, testable Swift package core, browser and separate project windows, folder navigator, Settings, local metadata.
2. Editor: NSTextView, incremental highlighting, line ruler, indentation, completion, find/replace, outline, atomic saves and external conflicts.
3. Toolchain: discovery, asynchronous process execution, latexmk, shell policy, cancellation, build log and diagnostics.
4. PDF: PDFKit, page/zoom/search, retained successful output, bidirectional SyncTeX.
5. Writing: project search/replace, texcount, symbols, equation/figure/table assistants.
6. References: balanced BibTeX parser, browser, insertion, source import.
7. History and Git: content-addressed snapshots, diff and restore, safe local Git operations, notes.
8. Templates and transfers: offline templates, validated ZIP import, source and submission exports.
9. Optional integrations: deferred until core acceptance; no remote services or visual rewriting in the core.
10. Polish and verification: menus, keyboard commands, drag/drop, restoration, real TeX fixtures, UI exercise, developer and release documentation.

Validate at each implementation boundary. Record actual test evidence and outstanding limitations in the README; do not substitute disabled mock controls for features.
