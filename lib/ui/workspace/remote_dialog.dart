import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/remote_spec.dart';
import '../common/dialogs.dart';

/// The name and URL a user entered for a remote.
typedef RemoteEdit = ({String name, String url});

const remoteNameFieldKey = Key('remoteName');
const remoteUrlFieldKey = Key('remoteUrl');

/// Prompts for a remote's name and URL, refusing to confirm until both are
/// valid. Returns null on cancel. [current] names the remote being edited so
/// it can keep its own name; [existing] are the names already in use.
Future<RemoteEdit?> showRemoteDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String initialUrl = '',
  Iterable<String> existing = const [],
  String? current,
  String confirmLabel = 'Save',
}) => showAppModal<RemoteEdit>(
  context: context,
  title: title,
  icon: Icons.dns_outlined,
  width: 460,
  // Fields and buttons live in a stateful widget so the controllers are
  // disposed with the route rather than mid-transition.
  body: _RemoteDialogBody(
    initialName: initialName,
    initialUrl: initialUrl,
    existing: existing.toList(),
    current: current,
    confirmLabel: confirmLabel,
  ),
);

class _RemoteDialogBody extends StatefulWidget {
  final String initialName;
  final String initialUrl;
  final List<String> existing;
  final String? current;
  final String confirmLabel;

  const _RemoteDialogBody({
    required this.initialName,
    required this.initialUrl,
    required this.existing,
    required this.current,
    required this.confirmLabel,
  });

  @override
  State<_RemoteDialogBody> createState() => _RemoteDialogBodyState();
}

class _RemoteDialogBodyState extends State<_RemoteDialogBody> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _url = TextEditingController(text: widget.initialUrl);

  @override
  void initState() {
    super.initState();
    _name.addListener(_revalidate);
    _url.addListener(_revalidate);
  }

  void _revalidate() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  String? get _nameError => remoteNameError(
    _name.text,
    existing: widget.existing,
    current: widget.current,
  );

  String? get _urlError => remoteUrlError(_url.text);

  bool get _valid => _nameError == null && _urlError == null;

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop((name: _name.text.trim(), url: _url.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = TextStyle(color: t.textPrimary, fontSize: 13);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: remoteNameFieldKey,
          controller: _name,
          autofocus: true,
          style: style,
          decoration: InputDecoration(
            labelText: 'Name',
            hintText: 'upstream',
            // An untouched field is blank, not wrong — the confirm button
            // still stays disabled until it is filled in.
            errorText: _name.text.isEmpty ? null : _nameError,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: remoteUrlFieldKey,
          controller: _url,
          style: style,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'URL',
            hintText: 'https://example.com/owner/repo.git',
            errorText: _url.text.isEmpty ? null : _urlError,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _valid ? _submit : null,
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      ],
    );
  }
}
