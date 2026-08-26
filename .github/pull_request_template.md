<!--
Thanks for the PR. Fill in what applies and delete what does not.
See CONTRIBUTING.md for the full guide.
-->

## What changed

<!-- The behaviour change, in a sentence or two. Not a list of files. -->

## Why

<!-- The problem this solves. Link the issue: Fixes #123 -->

## How it was verified

<!--
Which tests you added or ran, and anything you checked by hand.
For UI work, attach a screenshot or a short clip.
For destructive git operations, say what the confirmation and undo paths do now.
-->

## Checklist

- [ ] `make check` is clean — formatting, `flutter analyze`, full test suite
- [ ] New behaviour has a test that fails without this change
- [ ] No generated files (`*.g.dart`, `*.freezed.dart`), secrets, `.env`, `dist/`
      or `coverage/` in the diff
- [ ] User-visible strings go through `lib/l10n/app_en.arb` **and**
      `lib/l10n/app_uk.arb`, with `lib/l10n/gen/` regenerated and committed
- [ ] `lib/domain/` stays free of Flutter imports
- [ ] Destructive git operations are gated behind `confirmDestructive` and
      undoable where the reflog allows it
- [ ] README updated if a feature, shortcut or make target changed

## Notes for the reviewer

<!-- Trade-offs, known gaps, follow-up work, anything you want a second opinion on. -->
