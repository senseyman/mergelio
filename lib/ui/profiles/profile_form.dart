import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../common/dialogs.dart';

/// The three values a profile needs: its display [label] plus the git identity
/// ([name] / [email]).
typedef ProfileFormData = ({String label, String name, String email});

/// Single-modal profile editor. Returns the entered values, or null if
/// cancelled. Used for both create and edit from the Profiles dialog.
Future<ProfileFormData?> showProfileFormDialog(
  BuildContext context, {
  ProfileFormData? initial,
}) => showAppModal<ProfileFormData>(
  context: context,
  title: initial == null ? 'New profile' : 'Edit profile',
  icon: Icons.person_outline,
  width: 460,
  body: ProfileFormBody(initial: initial),
);

/// The form fields. When [onSubmit] is given it is called on save (used by the
/// blocking first-run screen); otherwise the route is popped with the result.
class ProfileFormBody extends StatefulWidget {
  final ProfileFormData? initial;
  final bool showCancel;
  final String submitLabel;
  final void Function(ProfileFormData data)? onSubmit;
  const ProfileFormBody({
    super.key,
    this.initial,
    this.showCancel = true,
    this.submitLabel = 'Save',
    this.onSubmit,
  });

  @override
  State<ProfileFormBody> createState() => _ProfileFormBodyState();
}

class _ProfileFormBodyState extends State<ProfileFormBody> {
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _email = TextEditingController(text: widget.initial?.email ?? '');

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _valid =>
      _label.text.trim().isNotEmpty &&
      _name.text.trim().isNotEmpty &&
      _email.text.trim().contains('@');

  void _submit() {
    if (!_valid) return;
    final data = (
      label: _label.text.trim(),
      name: _name.text.trim(),
      email: _email.text.trim(),
    );
    if (widget.onSubmit != null) {
      widget.onSubmit!(data);
    } else {
      Navigator.of(context).pop(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget field(String label, TextEditingController c, {String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: t.textFaint, fontSize: 11.5)),
              const SizedBox(height: 4),
              TextField(
                controller: c,
                autofocus: label == 'Profile name',
                onChanged: (_) => setState(() {}),
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
        field('Profile name', _label, hint: 'Work, Personal, …'),
        field('Developer name', _name, hint: 'Your name in commits'),
        field('Email', _email, hint: 'you@example.com'),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.showCancel)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _valid ? _submit : null,
              child: Text(widget.submitLabel),
            ),
          ],
        ),
      ],
    );
  }
}
