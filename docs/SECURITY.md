# Security and file integrity

TeXium is designed for direct distribution outside the App Store. The application is **not App Sandboxed** because it needs the user's installed TeX binaries, support trees, fonts, bibliography processors, Git, and arbitrary project dependencies. No custom entitlement exceptions are currently required. Hardened Runtime is enabled for certificate-signed builds; Xcode disables it for local ad-hoc debug signing.

## Trust boundary

TeX projects are executable input. Shell escape is disabled by default, restricted mode is selectable, and unrestricted mode requires an explicit per-project warning. `latexmk -norc` prevents project/user Perl configuration from executing before those flags take effect. Custom build commands require explicit approval in their native sheet and run a chosen executable with a JSON argument array, without implicit shell interpolation.

These controls reduce accidental execution; they are **not a hostile-code sandbox**. LuaTeX, distribution helpers, Git hooks/configuration, and explicitly enabled shell commands run with the current account's permissions. TeX source can read files accessible to that account. `openout_any=p` constrains TeX's own output-path policy, not every possible child program. Open and compile only projects you trust. A future isolation helper would need a separately reviewed process and filesystem capability design.

## File safeguards

- Project-relative operations reject absolute paths, traversal, NUL characters, and resolved links escaping the project. Hidden trees and directory symlinks are not traversed.
- The reserved `.texium-build` path cannot be a symlink, including a symlink to another folder inside the project. Cleanup touches only this directory and retains `preview/`.
- Saves compare exact baseline bytes inside NSFileCoordinator before atomic replacement. External edits produce a comparison sheet instead of silent overwrite.
- UTF-8 BOM, UTF-16 BOM, and existing line endings are preserved. Unsupported encoding fails explicitly.
- Destructive file actions and replace-all retain a history snapshot. Deletion uses Finder Trash. Whole-project restore explicitly confirms removal of files introduced after the selected revision.
- ZIP imports reject traversal, conflicting normalized names, symbolic links, encrypted/ZIP64 archives, and oversized archives. Limits are 512 MB compressed, 1 GB expanded, and fewer than 50,000 entries. Import requires a fresh destination folder.

Atomic replacement protects individual files, not entire multi-file operations. A process crash, hardware failure, filesystem race, or external program can still interrupt a restore or batch operation. History and recovery improve recoverability; maintain an independent backup for important work.

## Local information

Source, logs, history objects, recent paths, bookmarks, notes, and recovery copies remain on the Mac. They are not encrypted separately from the user's filesystem and may contain sensitive manuscript text. macOS account permissions and disk encryption govern access. Moving a project changes its metadata hash, so its previous history stays under the old path's metadata directory rather than following automatically.

There is no analytics client, external AI integration, embedded secret, application server, or background online service. OSLog records build state and counts, not manuscript content. Full TeX logs can contain local paths and source excerpts and should be reviewed before sharing. Git network operations are explicit user actions. Optional GitHub tokens are stored in non-synchronizing, app-specific macOS Keychain items and passed to Git through a host-validated credential helper pipe. UserDefaults contains only the public account name. SSH and existing external Git credential helpers are also supported. See [GitHub authentication and synchronization safeguards](GITHUB.md).

Security-scoped bookmarks are retained for folder access and moved-folder resolution, but they do not turn an unsandboxed app into a sandboxed one. Missing drives or unavailable bookmarks require reopening the project through a native panel.
