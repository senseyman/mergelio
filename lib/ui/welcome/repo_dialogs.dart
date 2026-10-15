import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/clone_options.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_bootstrap.dart';
import '../common/dialogs.dart';

/// Clone-repository dialog: source URL, a folder name derived live from the
/// URL (editable), a destination parent folder, and optional clone options
/// (shallow, blobless, branch, submodules). Clone runs for real and opens the
/// new repo as a tab.
Future<void> showCloneDialog(BuildContext context) => showAppModal<void>(
  context: context,
  title: AppLocalizations.of(context).rdlgCloneTitle,
  icon: Icons.cloud_download_outlined,
  body: const _CloneBody(),
);

/// Create-repository dialog: name + parent folder, default branch, and
/// optional README / .gitignore seeded as the initial commit.
Future<void> showCreateDialog(BuildContext context) => showAppModal<void>(
  context: context,
  title: AppLocalizations.of(context).rdlgCreateTitle,
  icon: Icons.add_box_outlined,
  body: const _CreateBody(),
);

class _CloneBody extends ConsumerStatefulWidget {
  const _CloneBody();

  @override
  ConsumerState<_CloneBody> createState() => _CloneBodyState();
}

class _CloneBodyState extends ConsumerState<_CloneBody> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _dir = TextEditingController();
  final _depth = TextEditingController(text: '1');
  final _branch = TextEditingController();
  bool _nameEdited = false;
  bool _cloning = false;
  bool _showOptions = false;
  bool _shallow = false;
  bool _blobless = false;
  bool _singleBranch = false;
  bool _submodules = true;

  @override
  void initState() {
    super.initState();
    // Keep the folder name derived from the URL until the user edits it.
    _url.addListener(() {
      if (_nameEdited) return;
      final derived = RepoBootstrap.folderNameFromUrl(_url.text);
      if (derived != _name.text) {
        _name.text = derived;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _dir.dispose();
    _depth.dispose();
    _branch.dispose();
    super.dispose();
  }

  // An unparseable depth stays 0 rather than null, so it is reported as bad
  // instead of quietly cloning the whole history.
  CloneOptions get _options => CloneOptions(
    depth: _shallow ? (parseDepth(_depth.text) ?? 0) : null,
    blobless: _blobless,
    branch: _branch.text,
    singleBranch: _singleBranch,
    submodules: _submodules,
  );

  /// Anything set away from a plain clone, so the collapsed toggle can say
  /// so rather than hide it.
  bool get _optionsChanged =>
      _shallow ||
      _blobless ||
      _branch.text.trim().isNotEmpty ||
      _singleBranch ||
      !_submodules;

  bool get _ready =>
      !_cloning &&
      _url.text.trim().isNotEmpty &&
      _name.text.trim().isNotEmpty &&
      _dir.text.isNotEmpty &&
      _options.problem == null;

  Future<void> _clone() async {
    setState(() => _cloning = true);
    final path = await ref
        .read(repoBootstrapProvider)
        .clone(
          url: _url.text,
          parentDir: _dir.text,
          folderName: _name.text,
          options: _options,
        );
    if (!mounted) return;
    setState(() => _cloning = false);
    if (path != null) Navigator.of(context).pop();
  }

  Widget _optionsSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    Widget check(String label, bool value, ValueChanged<bool> onChanged) =>
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            label,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
          value: value,
          onChanged: (v) => setState(() => onChanged(v ?? false)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: check(l.cloShallow, _shallow, (v) => _shallow = v)),
            SizedBox(
              width: 120,
              child: TextField(
                key: const ValueKey('clone-depth'),
                controller: _depth,
                enabled: _shallow,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.cloDepth,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(t.rButton),
                  ),
                ),
              ),
            ),
          ],
        ),
        check(l.cloBlobless, _blobless, (v) => _blobless = v),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('clone-branch'),
          controller: _branch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l.cloBranch,
            hintText: l.cloBranchHint,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.rButton),
            ),
          ),
        ),
        check(l.cloSingleBranch, _singleBranch, (v) => _singleBranch = v),
        check(l.cloSubmodules, _submodules, (v) => _submodules = v),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final problem = _options.problem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Field(
          label: l.asdRepoUrl,
          controller: _url,
          hint: 'https://… or git@…',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _Field(
          label: l.rdlgFolderName,
          controller: _name,
          hint: l.rdlgFolderHint,
          onChanged: (_) => setState(() => _nameEdited = true),
        ),
        const SizedBox(height: 14),
        _DirField(
          label: l.rdlgDestFolder,
          controller: _dir,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _showOptions = !_showOptions),
            icon: Icon(
              _showOptions ? Icons.expand_more : Icons.chevron_right,
              size: 18,
            ),
            label: Text(
              l.cloOptions,
              style: _optionsChanged ? TextStyle(color: t.accent) : null,
            ),
          ),
        ),
        if (_showOptions) _optionsSection(context),
        // Outside the section: a collapsed one must not hide why Clone is off.
        if (problem != null)
          Text(switch (problem) {
            CloneProblem.badDepth => l.cloBadDepth,
            CloneProblem.badBranch => l.cloBadBranch,
          }, style: TextStyle(color: t.danger, fontSize: 12)),
        const SizedBox(height: 18),
        if (_cloning) ...[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _cloning ? null : () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _ready ? _clone : null,
              child: Text(_cloning ? l.rdlgCloning : l.rdlgClone),
            ),
          ],
        ),
      ],
    );
  }
}

class _CreateBody extends ConsumerStatefulWidget {
  const _CreateBody();

  @override
  ConsumerState<_CreateBody> createState() => _CreateBodyState();
}

class _CreateBodyState extends ConsumerState<_CreateBody> {
  final _name = TextEditingController();
  final _dir = TextEditingController();
  String _branch = 'main';
  bool _readme = true;
  bool _gitignore = false;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _dir.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_creating && _name.text.trim().isNotEmpty && _dir.text.isNotEmpty;

  Future<void> _create() async {
    setState(() => _creating = true);
    final path = await ref
        .read(repoBootstrapProvider)
        .create(
          name: _name.text,
          parentDir: _dir.text,
          defaultBranch: _branch,
          readme: _readme,
          gitignore: _gitignore,
        );
    if (!mounted) return;
    setState(() => _creating = false);
    if (path != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Field(
          label: l.rdlgRepoName,
          controller: _name,
          hint: 'my-project',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _DirField(
          label: l.rdlgParentFolder,
          controller: _dir,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                l.rdlgDefaultBranch,
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
            ),
            for (final b in const ['main', 'master'])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(b, style: const TextStyle(fontSize: 12)),
                  selected: _branch == b,
                  onSelected: (_) => setState(() => _branch = b),
                ),
              ),
          ],
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            l.rdlgInitReadme,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
          value: _readme,
          onChanged: (v) => setState(() => _readme = v ?? true),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            l.rdlgAddGitignore,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
          value: _gitignore,
          onChanged: (v) => setState(() => _gitignore = v ?? false),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _creating ? null : () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _ready ? _create : null,
              child: Text(_creating ? l.rdlgCreating : l.create),
            ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: t.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.rButton),
            ),
          ),
        ),
      ],
    );
  }
}

class _DirField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback? onChanged;
  const _DirField({
    required this.label,
    required this.controller,
    this.onChanged,
  });

  @override
  State<_DirField> createState() => _DirFieldState();
}

class _DirFieldState extends State<_DirField> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: TextStyle(color: t.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: l.rdlgChooseFolder,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(t.rButton),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final dir = await getDirectoryPath();
                if (dir != null) {
                  setState(() => widget.controller.text = dir);
                  widget.onChanged?.call();
                }
              },
              child: Text(l.rdlgBrowse),
            ),
          ],
        ),
      ],
    );
  }
}
