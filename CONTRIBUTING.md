# Contributing to Mergelio

Thanks for taking the time. Issues and pull requests are both welcome, and a
small, well-described change is easier to land than a large one.

## Contents

- [Ways to contribute](#ways-to-contribute)
- [Development setup](#development-setup)
- [The loop](#the-loop)
- [Branches and commits](#branches-and-commits)
- [Pull requests](#pull-requests)
- [Code conventions](#code-conventions)
- [Testing](#testing)
- [Localization](#localization)
- [Reporting bugs](#reporting-bugs)
- [Security](#security)
- [License](#license)

## Ways to contribute

- **Report a bug** — see [Reporting bugs](#reporting-bugs) for what to include.
- **Propose a feature** — open an issue first for anything larger than a fix.
  Mergelio drives the `git` binary rather than reimplementing it, so a proposal
  that maps onto real git commands is much easier to accept.
- **Send a pull request** — fixes, tests, docs and translations all count.
- **Improve the docs** — the README, this file and `RELEASING.md` are the
  project's whole documentation surface.

## Development setup

### Prerequisites

- **Flutter 3.44.6**, `stable` channel (Dart SDK 3.12.2). The version is
  pinned, not a floor — see [Toolchain version](README.md#toolchain-version) in
  the README for why a newer SDK breaks code generation.
- **Desktop toolchain** for your host: Xcode (macOS), Visual Studio with the
  *Desktop development with C++* workload (Windows), or
  `clang cmake ninja-build pkg-config libgtk-3-dev` (Linux).
- **Git** on your `PATH` — the app shells out to it at runtime.

With [fvm](https://fvm.app) the pin is picked up from `.fvmrc`:

```bash
fvm install
fvm use
```

Check the whole setup with `make doctor`.

### First build

```bash
git clone git@github.com:<you>/mergelio.git
cd mergelio

make deps    # flutter pub get
make gen     # code generation (freezed / json_serializable / drift)
make run     # debug build on the host platform
```

`make gen` is not optional after a fresh clone: `*.g.dart` and `*.freezed.dart`
are gitignored, so the tree does not compile until they exist. Re-run it
whenever you touch a model, or keep `make gen-watch` running.

On macOS the debug build fails with `window_manager` under Swift Package
Manager. Run this once:

```bash
flutter config --no-enable-swift-package-manager
```

No signing certificate is needed to build or run Mergelio locally on any
platform.

## The loop

1. Write a failing test for the behaviour you want.
2. Make it pass.
3. `make check` — formatting, `flutter analyze` and the full test suite. This is
   exactly what CI runs, so a clean `make check` locally means a green PR.

Useful targets along the way:

| Target | Purpose |
| --- | --- |
| `make test` | Unit and widget tests |
| `make coverage` | Tests with coverage → `coverage/lcov.info` |
| `make format` | Format `lib` and `test` in place |
| `make fix` | `dart fix --apply`, then format |
| `make analyze` | Static analysis only |
| `make check` | The CI gate: lint + tests |

`make help` lists everything.

## Branches and commits

- Branch off `main`. Name the branch for its scope: `feat/…`, `fix/…`,
  `chore/…`, `ci/…` (for example `feat/content-search`,
  `fix/diff-scroll-clipping`).
- Keep a commit to one coherent change. Small, reviewable commits beat one
  large squashed drop.
- Write commit subjects in the imperative mood and under ~72 characters, with a
  Conventional-Commits prefix where it fits (`feat:`, `fix:`, `chore:`,
  `refactor:`, `test:`, `docs:`, `ci:`).
- Explain *why* in the body when the reason is not obvious from the diff. Skip
  the body when it is.
- Never commit generated files — `*.g.dart`, `*.freezed.dart` and `*.config.dart`
  are ignored on purpose. The one exception is `lib/l10n/gen/`, which *is*
  tracked; see [Localization](#localization).
- Never commit `.env`, build output, `dist/` or anything under `coverage/`.

## Pull requests

Before opening one:

- [ ] `make check` is clean.
- [ ] New behaviour has a test that fails without your change.
- [ ] No generated files, secrets or build artifacts in the diff.
- [ ] User-visible strings go through the ARB files, not string literals.
- [ ] The README is updated if you changed a feature, shortcut or make target.

In the PR description, say what behaviour changed and how you verified it. For
UI work, a screenshot or a short clip saves a round trip. If the change touches
a destructive git operation, say what the confirmation and undo paths do now.

Expect review comments; they are about the code, not about you. A PR that sits
on a stale `main` should be rebased rather than merged forward.

## Code conventions

The codebase is layered, and the layering is the main thing to respect:

```
lib/domain/   pure Dart — git command construction, parsing, models
lib/data/     persistence (drift/SQLite), settings, journal
lib/state/    Riverpod providers, orchestration, busy/cancel plumbing
lib/ui/       widgets, grouped by feature (graph, diff, files, merge, …)
lib/core/     cross-cutting helpers
lib/l10n/     ARB translations and their generated bindings
```

- **Keep Flutter imports out of `lib/domain/`.** That layer stays pure so it can
  be tested without pumping a widget, and so parsing logic is not tangled with
  rendering.
- **Extract logic out of widgets.** A function that takes data and returns data
  is worth ten `testWidgets` cases. Widget tests are for wiring and behaviour,
  not for arithmetic.
- **Gate destructive git operations** behind `confirmDestructive`, and make them
  undoable where the reflog allows it. Anything that can lose uncommitted work
  should auto-stash first, the way `reset --hard` does.
- **Every mutating operation goes through the operation journal** so an
  interrupted run is reported on the next launch.
- **Do not reimplement git.** Shell out. Matching the user's own config, hooks
  and credential helpers is the point.
- **Nothing leaves the machine** without an explicit opt-in, and telemetry values
  are scrubbed of paths, e-mail addresses, remote names and URLs first.
- **Accessibility is enforced, not reviewed.** Colours must hold WCAG 2.1 AA
  contrast (3:1 for UI colours) in both themes; a test asserts it. Add semantics
  labels and keep keyboard focus visible.
- Follow `flutter_lints` (`analysis_options.yaml`). `make fix` handles most of
  what it complains about.
- Comments explain intent. Write them so they stand on their own — do not cite
  external design documents by section number.

## Testing

```bash
make test        # unit and widget tests
make coverage    # → coverage/lcov.info
```

- Tests live in `test/`, one file per feature area, named `*_test.dart`.
- Pure logic is tested directly. UI behaviour is covered with `flutter_test`
  widget tests against a `ProviderContainer`, overriding the providers the test
  needs.
- **Widget tests cannot do file I/O.** A provider that reads the filesystem
  never resolves under `testWidgets` and you will chase `pumpAndSettle`
  timeouts. Override it instead.
- **Widget tests default to the Android platform.** If you are testing
  desktop-only behaviour, set the platform explicitly inside the test body and
  reset it there too.
- Aim to leave the code you touched at or above 70% line coverage.

## Localization

User-visible strings are never literals in widgets. Add them to the ARB files:

1. Add the key and English text to `lib/l10n/app_en.arb` (the template).
2. Add the same key to `lib/l10n/app_uk.arb`. If you cannot translate it, say so
   in the PR rather than leaving the key out — a missing key is a runtime hole.
3. Rebuild so `lib/l10n/gen/` is regenerated (`make run`, `make test` or
   `flutter gen-l10n`), and commit the regenerated files — unlike the other
   generated code, `lib/l10n/gen/` is tracked.
4. Use it as `AppLocalizations.of(context).yourKey`.

New locales are welcome: copy `app_en.arb`, translate, and add the locale
alongside the existing ones.

## Reporting bugs

Open an issue with:

- Mergelio version, OS and OS version.
- `git --version`.
- What you did, what you expected, what happened instead.
- The relevant slice of `logs/mergelio.log` from your application-support
  directory — Preferences → General shows the path. Redact anything private;
  the log is never uploaded automatically.
- A screenshot for anything visual.

If the repository state matters, describe it (detached HEAD, mid-rebase, a
submodule, a linked worktree) — those paths are where the interesting bugs live.

## Security

Do not open a public issue for a vulnerability. Report it privately through
GitHub's **Security → Report a vulnerability** on this repository, and give the
maintainer a reasonable window to ship a fix before disclosing.
[SECURITY.md](SECURITY.md) has the full policy — scope, response times and what
to include.

Mergelio executes `git` and a system shell, reads and writes files inside the
opened repository, and handles SSH key material through the OS tooling. Findings
in those paths — path escapes outside the opened repository, argument injection
into a git invocation, credential leakage into logs or telemetry — are exactly
what to look for.

## License

By contributing, you agree that your contributions are licensed under the
[BSD-3-Clause](LICENSE) license that covers this project.
