# GitHub synchronization

TeXium uses your installed Git. There is no TeXium server, account requirement, automatic network polling, or real-time collaboration. Local editing, compilation, snapshots, and commits work offline.

## Connect or clone

For an existing GitHub project, choose **Clone Git Repository…** in the Project Browser, enter its HTTPS or SSH URL, and choose a new destination folder. Open an existing local clone using **File → Open Project** and select the repository root.

To publish an existing local project, create an empty repository on GitHub, then choose **Project → Connect GitHub Repository…**. Paste `https://github.com/owner/project` or `git@github.com:owner/project.git` and choose a remote name. TeXium initializes local Git if needed and excludes `.texium-build/`. Connecting records the URL locally; it does not upload files or create a repository on GitHub. An existing remote is preserved; choose another name to add a connection.

Open **Project → GitHub Synchronization** to see the selected remote, branch, incoming/outgoing commit counts, and changed files. Multiple remotes are selectable. The repository title and **Project → Open on GitHub** open its web page. Counts are cached until you explicitly Fetch, Pull, Push, or Synchronize.

## Commit and synchronize

1. Review the changed-file list. Its two-character status is Git's index/worktree status; the checkmark identifies staged changes. Context-click a file to show its diff, stage, unstage, or open it.
2. Choose **Review Commit…**. Include all changed/untracked files or commit only staged contents. Check `.gitignore` and remove private material before staging. Enter a message and an author name/email; the identity is saved in this repository's Git configuration and becomes part of the commit. A GitHub noreply email can be used.
3. Choose **Commit Locally**, or **Commit & Sync** to upload the resulting history to the displayed repository and branch.
4. Use **Synchronize** (⇧⌘U) for subsequent updates. The adjacent menu offers **Fetch Remote Status**, **Pull (Fast-Forward Only)**, **Push Local Commits**, and connection/settings actions.

Synchronize requires a clean, committed local branch. It fetches, checks the actual remote branch, fast-forwards incoming history when possible, and performs a normal push for outgoing history or an unpublished branch. An incoming-only sync does not require push access. Tracking follows the selected remote and its configured upstream branch, including differently named upstream branches. First publication sets tracking automatically.

TeXium does not auto-commit, stash, rebase, force-push, or overwrite divergent history. Dirty files, detached HEAD, unresolved conflicts, and an in-progress merge/rebase stop synchronization with an explanation. Resolve these in your Git client, then refresh. If the tracked remote branch was deleted, Synchronize stops; use **Push Local Commits** explicitly to recreate it. Server permissions, protected branches, and concurrent non-fast-forward updates can reject a push. The local commit remains intact.

A local snapshot is taken before commit, pull/sync, and branch switch. These snapshots cover the same source scope as local History; they do not replace Git history or an independent backup. Source editing and compilation pause during a Git operation, and pulled changes reload into open buffers. Clean files deleted by a pull close automatically. Quit/close waits for the operation to finish or be stopped. After cancellation, Fetch again: a push may already have reached the server. Operation logs appear in the inspector.

## Authentication

**HTTPS:** in **Settings → GitHub**, enter your GitHub username and a personal access token, then choose **Save to Keychain**. Prefer a fine-grained token restricted to the needed repositories. Contents read permission supports private clones/fetches; read/write is needed to push. GitHub may require additional permission for workflow files or organization approval. Fetch a connected repository to check access. Removing the token deletes the configured TeXium Keychain item; it does not revoke the token on GitHub.

**SSH:** use the SSH URL and your existing SSH key/agent. Establish host trust and unlock keys in your normal SSH client first. TeXium runs SSH noninteractively; a hidden password or host-key prompt cannot stall the UI.

Without a TeXium token, HTTPS uses existing Git credential helpers. Public repositories generally need no token to clone or fetch. Native token support currently targets `github.com`; GitHub Enterprise or other Git hosts can use an existing local clone and externally configured authentication.

Tokens are stored as non-synchronizing, device-local generic password items in macOS Keychain, scoped to the app's bundle identifier and GitHub username. Only the public username is stored in UserDefaults. The app runs a headless Git credential helper that releases the configured token only for the exact HTTPS `github.com` credential context. It sends credentials to Git through a private pipe, not command arguments, environment variables, project configuration, or temporary files. The native-helper path disables HTTP redirects and replaces other credential helpers for that operation. Clone URLs with embedded HTTP credentials are rejected.

Git hooks, filters, custom SSH commands, and external credential helpers remain part of your trusted local Git configuration and run with your account's permissions. Stable Developer ID signing is required for predictable Keychain access across distributed application updates. Ad-hoc developer builds can trigger macOS Keychain access prompts after rebuilding.

References: [Git credential helpers](https://git-scm.com/docs/gitcredentials), [Git credential protocol](https://git-scm.com/docs/git-credential), [GitHub personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
