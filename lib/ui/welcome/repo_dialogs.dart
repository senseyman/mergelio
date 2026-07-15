import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/repo_bootstrap.dart';
import '../common/dialogs.dart';

/// Clone-repository dialog: source URL, a folder name derived live from the
/// URL (editable), and a destination parent folder. Clone runs for real and
/// opens the new repo as a tab.
Future<void> showCloneDialog(BuildContext context) => showAppModal<void>(
  context: context,
  title: 'Clone repository',
  icon: Icons.cloud_download_outlined,
  body: const _CloneBody(),
);

/// Create-repository dialog: name + parent folder, default branch, and
/// optional README / .gitignore seeded as the initial commit.
Future<void> showCreateDialog(BuildContext context) => showAppModal<void>(
  context: context,
  title: 'Create repository',
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
  bool _nameEdited = false;
  bool _cloning = false;

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
    super.dispose();
  }

  bool get _ready =>
      !_cloning &&
      _url.text.trim().isNotEmpty &&
      _name.text.trim().isNotEmpty &&
      _dir.text.isNotEmpty;

  Future<void> _clone() async {
    setState(() => _cloning = true);
    final path = await ref
        .read(repoBootstrapProvider)
        .clone(url: _url.text, parentDir: _dir.text, folderName: _name.text);
    if (!mounted) return;
    setState(() => _cloning = false);
    if (path != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Field(
          label: 'Repository URL',
          controller: _url,
          hint: 'https://… or git@…',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _Field(
          label: 'Folder name',
          controller: _name,
          hint: 'derived from the URL',
          onChanged: (_) => setState(() => _nameEdited = true),
        ),
        const SizedBox(height: 14),
        _DirField(
          label: 'Destination folder',
          controller: _dir,
          onChanged: () => setState(() {}),
        ),
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
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _ready ? _clone : null,
              child: Text(_cloning ? 'Cloning…' : 'Clone'),
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
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Field(
          label: 'Repository name',
          controller: _name,
          hint: 'my-project',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _DirField(
          label: 'Parent folder',
          controller: _dir,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'Default branch',
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
            'Initialise with README.md',
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
            'Add an empty .gitignore',
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
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _ready ? _create : null,
              child: Text(_creating ? 'Creating…' : 'Create'),
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
                  hintText: 'Choose a folder…',
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
              child: const Text('Browse'),
            ),
          ],
        ),
      ],
    );
  }
}
