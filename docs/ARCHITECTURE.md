# Architecture

## Scenes and state

`TeXiumApp` declares a project-browser WindowGroup, a value-based project WindowGroup, and Settings. Project paths identify windows. `ProjectLibrary` owns recents/bookmarks; each `ProjectWindow` owns its own observable `ProjectSession`. Source buffers, build tasks, PDF state, selected files, notes, and inspectors are window-scoped. Sheets own temporary input locally. Focused scene values route menu commands to the active project.

The window bridge forwards the original SwiftUI window delegate, persists the frame, reports document-edited state, and performs coordinated saves at close/quit. SIGTERM routes through normal AppKit termination. A failed save prevents termination. On a normal quit, open project paths are recorded; the browser reopens available bookmarked projects when enabled. Native window tabbing follows macOS preferences.

## Editor

`SourceEditor` wraps a plain-text `NSTextView` in `NSScrollView` with an `NSRulerView` gutter. It uses TextKit 1 deliberately for stable NSTextView undo, find-bar, selection, and layout-manager behavior. SwiftUI never renders the document's characters. The coordinator transfers edits and UTF-16 selection ranges into the active buffer and suppresses callbacks during programmatic loads.

`LaTeXSyntaxHighlighter` colors the changed logical lines during editing. `SyntaxPalette` stores only explicit opaque sRGB overrides in UserDefaults, preserving appearance-aware macOS colors for unmodified categories. Settings exposes native color pickers, validated hex fields, and individual/global resets. A palette or highlighting preference change recolors the full open buffer without changing its source text or undo history. Comment coloring runs last so syntax inside a comment retains its comment color.

The line index adjusts offsets for the replaced range; only opening or replacing a whole buffer rebuilds it. Standard undo and NSTextFinder supply familiar editing. Command/environment/key/file completion uses NSTextView's native completion panel. Switching tabs currently clears the view's undo stack; saved source and local history remain independent of that stack.

An 800 ms idle delay triggers autosave and asynchronous indexing. Outline and bibliography scans run off the main actor and use live buffers where available. The outline recognizes structural commands with nested braces and comment-aware UTF-16 offsets. It does not expand TeX macros. The index currently rescans the project after an idle edit; very large trees need incremental per-file index caching in a future release.

## Files and persistence

A project is a user-selected folder. `ProjectFileSystem` centralizes path containment, tree enumeration, encoding/BOM handling, baseline comparison, atomic coordinated saves, and metadata locations. Source files are never serialized into an opaque project format. Small application metadata uses atomic Codable JSON rather than adding a database dependency; this is an intentional deviation from the suggested SwiftData/Core Data preference.

`ProjectSession` serializes saves and rechecks buffers edited while IO was pending. FSEvents reloads unchanged buffers and presents conflicts for dirty or missing files. Recovery JSON stores unsaved text through a background actor with monotonically increasing write generations. Recovery does not replace disk source without user choice. File mutations and history restoration temporarily prevent new source edits while snapshots and disk operations are in progress.

## Build pipeline

1. Resolve and validate the configured main file and reserved build directory.
2. Finish saving and snapshot source history.
3. Discover installed TeX tools and invoke `latexmk` with explicit argument arrays, `-norc`, file/line diagnostics, SyncTeX, and the chosen engine/shell policy.
4. Drain combined stdout/stderr continuously on a worker queue. Publish progress on the main actor.
5. Parse the final TeX log after multipass completion, avoiding stale first-pass warnings.
6. On success atomically replace the stable preview PDF/SyncTeX; on failure retain prior output and show that it is stale.
7. Record the starting history revision and build configuration in `preview/build.json`. Edits during compilation mark the resulting output stale. Because TeX reads the live project, this record describes the starting revision and does not promise an immutable build when external tools change source mid-build.

The build-root marker invalidates caches after a directory is copied or moved, because latexmk and SyncTeX contain absolute paths. Scratch compilation removes auxiliaries while preserving stable preview output. The reserved build directory cannot be a symbolic link.

`ProcessRunner` launches on a background queue, remembers pre-launch cancellation, drains output without pipe deadlock, and uses macOS child-process enumeration to stop compiler descendants. Cancellation freezes the parent while finding descendants and kills the stopped tree; it does not kill arbitrary processes by executable name. OSLog records build lifecycle events without source text.

## PDF and SyncTeX

`PDFKitView` asynchronously reads and constructs a PDFDocument, transfers ownership to the main-thread PDFView, and retains the previous document while loading. Recompilation preserves page, destination, and zoom when possible. Page/zoom preferences survive project reopen. PDFKit supplies rendering, selection, text search, thumbnails, print operations, and native context menus.

Forward navigation invokes `synctex view`; inverse navigation invokes `synctex edit`. Coordinates convert between SyncTeX's top-origin page values and PDFKit's page bounds. Inverse paths must resolve inside the project before opening. A context-menu action and Command-click both support inverse navigation.

## Workspace layout

The navigator belongs to `NavigationSplitView`; the inspector is attached to the document detail inside that split. A `GeometryReader` supplies the available rectangle to `DocumentWorkspace`, a small `NSViewRepresentable` hosting the native source/PDF `HSplitView`. Its hosting view disables inherited safe-area regions and intrinsic sizing; `sizeThatFits` answers from the proposed rectangle without measuring the nested AppKit split. This prevents the inspector's inset from conflicting with the document split's trailing-edge constraints and feeding recursive constraint updates back into the window during restoration. The hosted panes observe the same window session directly. The minimum window width accounts for the visible document modes and sidebars.

The editor tab strip stays 37 points tall. The editor, empty PDF state, and loaded PDF canvas all fill the remaining height, so opening an uncompiled project has the same pane geometry as opening a compiled one. PDF page navigation uses compact icon controls to fit narrow panes. Accessibility identifiers mark the navigator, inspector picker, and PDF pane for geometry regression checks.

## History, bibliography, Git, and exports

`HistoryService` is an actor with SHA-256 content-addressed objects and an atomic revision manifest. Automatic identical snapshots deduplicate. Restores validate every requested object before writing, retain a pre-restore snapshot, and preserve newer history. A multi-file restore is not an OS-wide transaction; an interrupted restore can be recovered using that retained snapshot. `/usr/bin/diff` generates comparisons.

`BibTeXParser` handles braced/quoted values, nesting, concatenation, and ordinary entry fields without rewriting `.bib` source. The reference browser uses parsed values while actual bibliography production belongs to BibTeX/Biber through latexmk.

`GitService` uses installed Git for repository inspection, cloning, connection, staging, commits, and branch switching. It rejects project subdirectories of a larger repository. `GitSynchronizationService` fetches and checks incoming/outgoing history, permits only clean fast-forward integration and normal pushes, and refuses conflicts/divergence. `ProjectGitActions` coordinates snapshots, editor/build exclusion, cancellation, and buffer reload. The native Git inspector, connection/commit sheets, and Project menu expose these operations.

`GitHubCredentialStore` keeps optional HTTPS tokens in app-specific macOS Keychain items. The executable entry point routes `--git-credential get` to a headless, host-validated credential protocol before SwiftUI startup. Git receives the credential through its helper pipe; tokens never enter command arguments or project configuration. SSH and external credential helpers remain available. See [GitHub synchronization](GITHUB.md).

`ArchiveService` validates ZIP structure before extraction into a temporary directory, then copies into a new destination. Source exports filter hidden and auxiliary files. Submission exports add generated `.bbl` files. The template library writes normal `.tex` and `.bib` files and requires a new folder.
