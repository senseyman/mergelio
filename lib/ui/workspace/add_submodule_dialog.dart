import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../common/dialogs.dart';

typedef AddSubmoduleData = ({String url, String path, String? branch});

/// Single-modal "add submodule" form: repository URL, checkout path, and an
/// optional tracked branch. Returns null if cancelled.
Future<AddSubmoduleData?> showAddSubmoduleDialog(BuildContext context) =>
    showAppModal<AddSubmoduleData>(
      context: context,
      title: AppLocalizations.of(context).asdTitle,
      icon: Icons.account_tree_outlined,
      width: 480,
      body: const _AddSubmoduleBody(),
    );

class _AddSubmoduleBody extends StatefulWidget {
  const _AddSubmoduleBody();

  @override
  State<_AddSubmoduleBody> createState() => _AddSubmoduleBodyState();
}

class _AddSubmoduleBodyState extends State<_AddSubmoduleBody> {
  final _url = TextEditingController();
  final _path = TextEditingController();
  final _branch = TextEditingController();
  // Once the user edits the path by hand, stop auto-deriving it from the URL.
  bool _pathEdited = false;

  @override
  void dispose() {
    _url.dispose();
    _path.dispose();
    _branch.dispose();
    super.dispose();
  }

  void _onUrlChanged(String v) {
    if (!_pathEdited) {
      var leaf = v.trim().split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty);
      var name = leaf.isEmpty ? '' : leaf.last;
      if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
      _path.text = name;
    }
    setState(() {});
  }

  bool get _valid =>
      _url.text.trim().isNotEmpty && _path.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    final branch = _branch.text.trim();
    Navigator.of(context).pop((
      url: _url.text.trim(),
      path: _path.text.trim(),
      branch: branch.isEmpty ? null : branch,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    Widget field(
      String label,
      TextEditingController c, {
      String? hint,
      bool autofocus = false,
      ValueChanged<String>? onChanged,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.textFaint, fontSize: 11.5)),
          const SizedBox(height: 4),
          TextField(
            controller: c,
            autofocus: autofocus,
            onChanged: onChanged ?? (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field(
          l.asdRepoUrl,
          _url,
          hint: 'https://… or git@…',
          autofocus: true,
          onChanged: _onUrlChanged,
        ),
        field(
          l.asdPath,
          _path,
          hint: l.asdPathHint,
          onChanged: (_) => setState(() => _pathEdited = true),
        ),
        field(l.asdBranchOptional, _branch, hint: l.asdBranchHint),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _valid ? _submit : null,
              child: Text(l.sbAdd),
            ),
          ],
        ),
      ],
    );
  }
}
