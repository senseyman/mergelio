import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../common/dialogs.dart';

/// Clone-repository dialog: a source URL and a destination folder. The actual
/// clone runs in a later stage; this wires the form and returns the inputs.
Future<void> showCloneDialog(BuildContext context) async {
  final urlCtl = TextEditingController();
  final dirCtl = TextEditingController();
  await showAppModal<void>(
    context: context,
    title: 'Clone repository',
    icon: Icons.cloud_download_outlined,
    body: _CloneBody(urlCtl: urlCtl, dirCtl: dirCtl),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Clone'),
        ),
      ),
    ],
  );
  urlCtl.dispose();
  dirCtl.dispose();
}

/// Create-repository dialog: destination folder + repository name.
Future<void> showCreateDialog(BuildContext context) async {
  final nameCtl = TextEditingController();
  final dirCtl = TextEditingController();
  await showAppModal<void>(
    context: context,
    title: 'Create repository',
    icon: Icons.add_box_outlined,
    body: _CreateBody(nameCtl: nameCtl, dirCtl: dirCtl),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Create'),
        ),
      ),
    ],
  );
  nameCtl.dispose();
  dirCtl.dispose();
}

class _CloneBody extends StatelessWidget {
  final TextEditingController urlCtl;
  final TextEditingController dirCtl;
  const _CloneBody({required this.urlCtl, required this.dirCtl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          label: 'Repository URL',
          controller: urlCtl,
          hint: 'https://… or git@…',
        ),
        const SizedBox(height: 14),
        _DirField(label: 'Destination folder', controller: dirCtl),
      ],
    );
  }
}

class _CreateBody extends StatelessWidget {
  final TextEditingController nameCtl;
  final TextEditingController dirCtl;
  const _CreateBody({required this.nameCtl, required this.dirCtl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          label: 'Repository name',
          controller: nameCtl,
          hint: 'my-project',
        ),
        const SizedBox(height: 14),
        _DirField(label: 'Parent folder', controller: dirCtl),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
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
  const _DirField({required this.label, required this.controller});

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
                if (dir != null) setState(() => widget.controller.text = dir);
              },
              child: const Text('Browse'),
            ),
          ],
        ),
      ],
    );
  }
}
