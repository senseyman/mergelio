<div align="center">

<img src="linux/packaging/icons/com.mergelio.mergelio.png" alt="Mergelio" width="120" />

# Mergelio

**A free, cross-platform visual Git client for the desktop.**


[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)](#installation)
[![Flutter](https://img.shields.io/badge/Flutter-3.44.6-02569B.svg?logo=flutter)](https://flutter.dev)
[![Dart SDK](https://img.shields.io/badge/Dart%20SDK-3.12.x-0175C2.svg?logo=dart)](https://dart.dev)
[![Tests](https://img.shields.io/badge/tests-1229%20passing-brightgreen.svg)](#testing)

<img src=".github/screenshots/mergelio-demo.gif" alt="Mergelio in action: browsing history, editing a file, reviewing the diff and committing" width="900" />

</div>

---

## Contents

- [Why Mergelio](#why-mergelio)
- [Screenshots](#screenshots)
- [Features](#features)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Installation](#installation)
- [Building from source](#building-from-source)
- [Make targets](#make-targets)
- [Architecture](#architecture)
- [Project layout](#project-layout)
- [Testing](#testing)
- [Localization](#localization)
- [Privacy](#privacy)
- [Contributing](#contributing)
- [Releasing](#releasing)
- [License](#license)

## Why Mergelio

Most desktop Git clients are either paid, closed-source, or hide what they are
about to do to your repository. Mergelio takes the opposite position:

- **Free and open source** — BSD-3-Clause, no account, no licence server.
- **Your `git`, not a reimplementation** — every operation shells out to the
  `git` binary already on your machine, so behaviour matches your terminal and
  your config (hooks, `includeIf`, credential helpers, aliases).
- **Destructive operations are explicit** — confirmation gates, an auto-stash
  before `reset --hard`, reflog-backed undo, and a crash-safe journal that
  reports interrupted operations on the next launch.
- **Native desktop, not a web app in a shell** — one compiled binary per
  platform, no bundled browser runtime.

## Screenshots

<div align="center">

<img src=".github/screenshots/mergelio-view.png" alt="Commit graph with the branch sidebar and commit details panel" width="900" />

*Commit graph, with branches, remotes, tags, stashes and worktrees in the
sidebar, and the selected commit's message, metadata and changed files on the
right.*

<br />

<img src=".github/screenshots/mergelio-diff-view.png" alt="Split diff of a file inside a commit" width="900" />

*Side-by-side diff with syntax highlighting, inline/split toggle, and per-hunk
actions.*

<br />

<img src=".github/screenshots/mergelio-file-edit.png" alt="Project file browser, editor tabs and the built-in terminal" width="900" />

*Project file browser with tabbed editing and the built-in terminal, so a quick
change never needs a second window.*

</div>

## Features

### Repositories & workspace

- Open, clone and create repositories, with progress and a recents list.
- Multiple repositories open as tabs — drag to reorder, close-others, and
  restore on the next launch.
- **Repository groups** to scope tabs into named sets (e.g. `Work` / `OSS`),
  with three switcher styles (dropdown, pills, side rail); create, rename and
  delete groups from any of them.
- **Profiles** — separate identities, SSH keys and per-profile workspaces.
  SSH keys are generated through the system `ssh-keygen`, so key material stays
  with the OS tooling.
- Submodules: add, update, sync, deinit and remove.

### Worktrees

- Every linked worktree of the repository is listed in the sidebar — with its
  branch (or short HEAD when detached), lock state, and prunable status.
- Create a worktree on a new branch, an existing branch, or a detached head —
  and open it as its own tab.
- Move, lock, unlock and remove worktrees; removing one with uncommitted
  changes asks before forcing, and pruning shows exactly which stale entries
  would be dropped.
- Branches already checked out in another worktree are badged in the branch
  list, and switching to one offers to jump to that worktree instead of failing
  with git's error.

### Commit graph & history

- Lane-based commit graph with configurable columns, ref pills, signed-commit
  indicators and full keyboard navigation.
- Commit details with per-file stats, and a diff for any commit.
- **File history** and per-line **blame** for any changed file.
- Global search with filters, plus in-graph match highlighting.
- Content search (pickaxe): find the commits that added or removed a string, literally or by regular expression.
- **Command palette** (`⌘K` / `Ctrl+K`) with fuzzy matching and fly-to.

### Working with changes

- Stage and unstage by **file, hunk, line or a run of lines**, including partial
  patches. Drag down the diff's gutter (or shift-click) to pick out a run, then
  stage or discard exactly those lines from the right-click menu.
- Side-by-side or unified diffs with word-level intra-line highlighting and
  syntax colouring. Long lines scroll sideways instead of being cut off, and in
  split view each column scrolls on its own — a new file's empty left half no
  longer crowds out the additions.
- Expand any diff to the **whole file** instead of just the changed regions, and
  collapse it back — one toggle in the diff header.
- Select and copy diff text — line numbers, change markers, hunk headers and the
  hunk buttons are left out, so you copy source and nothing else, with each line
  on its own line. In split view each column selects on its own, so a copy is
  never the two sides interleaved. Right-click anywhere for **Select all**.
- Edit uncommitted files in place from the diff sheet, syntax-highlighted like
  the diff. Saving writes the working tree, leaves the change unstaged, and is
  undoable.
- Commit, amend, sign (`-S`) and add co-authors.
- Discard by **hunk, file, or the whole working tree** behind a confirmation
  gate, and undoable afterwards. Discarding everything reverts tracked files
  only; deleting untracked files is a separate opt-in on the prompt.

### Project files

- **Files mode** — switch a repository tab from the commit graph to a project
  browser and back; the choice is remembered per tab.
- A lazy directory tree: a folder is read the first time it is opened, so a
  repository with a huge `node_modules` costs nothing until you look inside it.
- Git context on every row — modified and untracked badges, dimmed ignored
  entries, and a hide-ignored toggle.
- **Editor tabs** with the same editor the diff sheet uses: syntax colouring,
  `⌘S` / `Ctrl+S` saving, a line-number gutter, and `⌘F` / `Ctrl+F` find and
  replace with a match count and a case toggle. Open files are restored on the
  next launch; unsaved text never is.
- Unsaved editors are asked about once — when leaving Files mode, closing the
  repository tab, or quitting.
- Right-click a row for new file, new folder, rename, delete, stage, unstage,
  discard, file history, and reveal in the system file manager. Every path is
  checked against the opened repository before disk is touched.
- An open file follows what happens on disk: renamed, its tab moves with it;
  deleted, the tab says so and saving is refused.

### Branching & remotes

- Branches: create, checkout, rename, delete, set upstream — organised into
  folders from `/`-separated names.
- Delete a branch on the remote from its remote-tracking row, or take a
  tracking branch away here and on the remote in one confirmed step.
- Fetch, pull (merge or rebase strategy), and push with **force-with-lease**.
  Fetching runs in its own lane, so a fetch — including an auto-fetch tick —
  never blocks a commit, a branch create or a push.
- The running operation is named in the status bar with a **cancel** button, so
  a fetch or push against a remote that stopped answering can be abandoned
  instead of waited out. Network commands also carry SSH connect and keepalive
  timeouts, so a dead host fails in seconds rather than minutes — whatever
  `GIT_SSH_COMMAND` or `core.sshCommand` you already set is kept.
- Merge from the branch menu, the merge dialog or by drag-and-drop, with merge
  options. **Remote-tracking branches merge too** — drag one onto a branch, or
  drop a branch onto it and the merge lands on its local counterpart. Merging
  from a remote offers to fetch first, showing how long ago you last did.
- **Interactive rebase** — reorder, reword, squash, fixup and drop.
- Cherry-pick, revert, reset (soft / hard), and reset-to-remote.
- Stash push, apply, pop, drop — with undo.
- Tags: create, push, delete.
- Remotes: add, edit name and URL, remove, prune — validated before they reach
  git, and undoable.

### Merge tool

- Three-zone conflict resolution (ours / result / theirs) with word-level diff
  and gated completion — you cannot finish a merge with conflicts left behind.

### Safety net

- `reset --hard` **auto-stashes** uncommitted work first; undo restores it.
- Reflog-backed **undo/redo** within a session — commit, merge and rebase are
  all undoable.
- A durable per-repository **operation journal**: every mutating operation is
  written to disk *before* it runs, and interrupted operations are surfaced on
  the next launch.

### Terminal

- A dockable, real system-shell terminal (`flutter_pty` + `xterm`) rooted in
  the active repository. The repository view refreshes after each command.

### Appearance & accessibility

- Dark and light themes, with optional system-theme sync.
- Customisable accent and branch-colour palettes, a free-form hex picker, saved
  themes, and theme export/import.
- WCAG 2.1 AA contrast in both themes (3:1 for UI colours), enforced by a test.
- Semantics labels, visible keyboard focus, and 100–200% UI zoom.
- Resizable, persisted panels.

## Keyboard shortcuts

`⌘` on macOS, `Ctrl` on Windows and Linux.

| Shortcut | Action |
| --- | --- |
| `⌘K` | Command palette |
| `⌘F` | Search |
| `⌘B` | Create branch |
| `` ⌘` `` | Toggle terminal |
| `⌘\` | Toggle the left panel |
| `⌘,` | Preferences |
| `⌘Z` / `⇧⌘Z` | Undo / redo |
| `⌘S` | Save the file open in the editor |
| `⌘F` | Find and replace, with an editor focused |
| `⌘+` / `⌘-` / `⌘0` | Zoom in / out / reset |
| `Esc` | Dismiss the top notification |

The full list lives in **Preferences → Shortcuts**.

## Installation

### Runtime requirement

Mergelio drives the `git` binary on your `PATH` — install
[Git](https://git-scm.com/downloads) if you do not have it already. Verify with:

```bash
git --version
```

On Windows, repositories inside a WSL2 distribution are supported.

### Verifying a download

Every release ships a `SHA256SUMS.txt` and a detached OpenPGP signature for it,
`SHA256SUMS.txt.asc`. One signature covers every file in the release.

```bash
# once — fetch the signing key
gpg --keyserver keys.openpgp.org --recv-keys 817229DD049EDD81D4D8FB2B080226BF36A5B807

# in the directory holding the downloads
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
sha256sum --check --ignore-missing SHA256SUMS.txt
```

The Fedora package carries the same signature in its header, so `rpm` can check
it directly once the key is known to it:

```bash
gpg --export --armor 817229DD049EDD81D4D8FB2B080226BF36A5B807 > mergelio.asc
sudo rpm --import mergelio.asc
rpm --checksig mergelio-*.rpm          # digests signatures OK
```

There is no equivalent for the `.deb`: `dpkg` does not check signatures inside a
package, only `apt` checks the repository it came from. For Debian and Ubuntu the
checksum file above is the verification.

## Building from source

### Prerequisites

- **Flutter 3.44.6** on the `stable` channel (Dart SDK 3.12.2) — see
  [Toolchain version](#toolchain-version) below; this one is pinned, not a floor
- **Desktop toolchain** for your host: Xcode (macOS), Visual Studio with the
  *Desktop development with C++* workload (Windows), or
  `clang cmake ninja-build pkg-config libgtk-3-dev` (Linux)
- **Git** on your `PATH`

Check your setup with `make doctor`.

### Toolchain version

The Flutter release is pinned in [`.fvmrc`](.fvmrc) and `pubspec.yaml` declares
`sdk: '>=3.12.2 <3.13.0'`. Both bounds are intentional.

`pubspec.lock` holds `analyzer` 7.7.1, and `freezed` 2.x caps it there. That
analyzer understands language version 3.9, so a Dart 3.13+ SDK hands it syntax
it cannot serialise and code generation dies with an unhelpful stack trace:

```
Exception: Missing implementation of visitDotShorthandPropertyAccess
```

The SDK bound in `pubspec.yaml` turns that into a clear `pub get` error instead.
Lifting it means migrating the codegen chain to `freezed` 3.x / `source_gen` 4.x
first.

With [fvm](https://fvm.app) the pin is picked up automatically:

```bash
fvm install    # reads .fvmrc
fvm use
fvm flutter --version
```

Without fvm, match it by hand:

```bash
flutter --version          # expect 3.44.6 / Dart 3.12.2
```

The build scripts print a warning when the running Flutter differs from the pin.

### Build and run

```bash
git clone git@github.com:senseyman/mergelio.git
cd mergelio

make deps    # flutter pub get
make gen     # code generation (freezed / json_serializable / drift)
make run     # debug build on the host platform
```

Release build for the host platform:

```bash
make build
```

Or target one explicitly: `make build-macos`, `make build-windows`,
`make build-linux`.

Each of those targets just calls a script, which you can run directly instead —
the better route on Windows, where `make` is usually absent:

```bash
./scripts/build-macos-app.sh       # .app + zip in dist/
./scripts/build-linux-tarball.sh       # bundle + tar.gz in dist/
./scripts/build-linux-deb.sh # .deb installer in dist/
.\scripts\build-windows-installer.ps1    # exe + zip + setup.exe in dist/
```

Each script fetches dependencies, runs code generation, builds, and archives the
result under a versioned name. They read `APP_NAME` and `DIST_DIR` from `.env`,
and take an explicit version as the first argument. Switches:

| Switch | Effect |
| --- | --- |
| `CLEAN=1` | `flutter clean` before building |
| `SKIP_GEN=1` | skip code generation, when the generated files are already there |
| `SKIP_PACKAGE=1` | build only, produce no archive |

In PowerShell, set them as `$env:CLEAN = 1` before the call.

None of this needs a signing certificate. Builds are unsigned on Windows and
Linux, and ad-hoc signed on macOS — enough to run on the machine that built
them.

> **macOS note** — the debug build fails with `window_manager` under Swift
> Package Manager. Run this once before `make build-macos-debug`:
>
> ```bash
> flutter config --no-enable-swift-package-manager
> ```

### Optional: macOS code signing

`make build-macos` produces an ad-hoc signed app that runs on the machine that
built it. Nothing further is needed to build and use Mergelio locally, on any
platform — no Apple Developer account, no certificates.

To produce a build other machines will accept, copy the template, fill in your
own Apple Developer values, and run the release pipeline:

```bash
cp .env.example .env
./scripts/build-macos-dmg.sh
```

`.env` is gitignored and stores names only: the certificate's private key and
the notarization password stay in the macOS keychain. See
[RELEASING.md](RELEASING.md) for the full list of variables.

Windows and Linux builds need no signing configuration.

Generated sources (`*.g.dart`, `*.freezed.dart`) are **not** committed — run
`make gen` after cloning and whenever you touch a model. `make gen-watch`
regenerates on save.

## Make targets

```
make help
```

| Target | Purpose |
| --- | --- |
| `doctor` | Flutter environment diagnostics |
| `deps` / `upgrade` | Fetch / upgrade pub dependencies |
| `gen` / `gen-watch` | Code generation (one-shot / watch) |
| `format` / `format-check` | Format sources / verify formatting |
| `analyze` | `flutter analyze` |
| `lint` | `format-check` + `analyze` |
| `fix` | Automated dart fixes, then format |
| `test` | Unit and widget tests |
| `coverage` | Tests with coverage → `coverage/lcov.info` |
| `run` | Debug build on the host platform |
| `build` | Release build for the host platform |
| `build-macos` / `build-windows` / `build-linux` | Per-platform release build |
| `installer` / `installer-linux` / `installer-windows` | Installer build (.deb, setup.exe) |
| `check` | CI gate: `lint` + `test` |
| `ci` | Full pipeline: `deps` → `gen` → `check` |
| `clean` / `distclean` | Remove build artifacts / also generated code |


## Testing

```bash
make test        # 1229 unit and widget tests
make coverage    # → coverage/lcov.info
make check       # what CI runs: format check + analyze + test
```

Development follows a test-first loop: a failing test for the behaviour, then
the implementation, then `make check`. Pure logic is tested directly; UI
behaviour is covered with `flutter_test` widget tests against a
`ProviderContainer`. Accessibility contrast is asserted by a test rather than
reviewed by eye.

## Privacy

Mergelio has no accounts and phones home to nothing by default.

- **Telemetry is opt-in** and off until you enable it in Preferences. When
  enabled, values are scrubbed of file paths, e-mail addresses, remote names
  and URLs before leaving the machine.
- Credentials are handled by your existing git credential helper and
  `ssh-agent`; Mergelio does not store passwords or tokens itself.
- Everything else — settings, recents, open tabs, the operation journal — stays
  in a local SQLite database in your OS application-support directory.
- Diagnostic logs are written to `logs/mergelio.log` in that same directory
  (2 MB per file, three archives kept) and never leave the machine. On macOS
  that is `~/Library/Application Support/com.mergelio.mergelio/logs/`.
  Preferences → General shows the path and reveals it in your file manager.

## Contributing

Issues and pull requests are welcome.

1. Fork and branch off `main`.
2. `make deps && make gen`.
3. Write a failing test first, then the implementation.
4. `make check` must be clean — formatting, `flutter analyze` and the full test
   suite.
5. Open a PR describing the behaviour change and how you verified it.

Conventions worth knowing before your first PR:

- Keep Flutter imports out of `lib/domain/` — that layer stays pure and testable.
- Extract logic from widgets into functions you can test without pumping a widget.
- Never commit generated files (`*.g.dart`, `*.freezed.dart`); they are ignored.
- Gate destructive git operations behind `confirmDestructive` and make them
  undoable where the reflog allows it.

## License

[BSD-3-Clause](LICENSE) © 2026 Neo.
