import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/profiles.dart';
import '../common/dialogs.dart';
import 'profile_form.dart';

/// Manage commit-identity profiles: list, add, edit, delete, and pick the
/// active one (which drives commit author name/email).
Future<void> showProfilesDialog(BuildContext context) => showAppModal<void>(
  context: context,
  title: 'Profiles',
  icon: Icons.person_outline,
  width: 460,
  body: const _ProfilesBody(),
);

class _ProfilesBody extends ConsumerWidget {
  const _ProfilesBody();

  static const _palette = [
    0xFF6C8CFF,
    0xFF3DD68C,
    0xFFF5C451,
    0xFFEB6F92,
    0xFF9D7CFF,
    0xFF4CC9F0,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = ref.watch(profilesProvider);
    final ctl = ref.read(profilesProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.profiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No profiles yet. Add one to set your commit identity.',
              style: TextStyle(color: t.textFaint, fontSize: 12.5),
            ),
          ),
        for (final p in state.profiles)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Color(p.colorValue),
                shape: BoxShape.circle,
              ),
            ),
            title: Text(
              p.label,
              style: TextStyle(color: t.textPrimary, fontSize: 13),
            ),
            subtitle: Text(
              '${p.name} · ${p.email}',
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p.id == state.activeId)
                  Icon(Icons.check_circle, size: 16, color: t.success)
                else
                  TextButton(
                    onPressed: () => ctl.setActive(p.id),
                    child: const Text('Use', style: TextStyle(fontSize: 12)),
                  ),
                IconButton(
                  iconSize: 15,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      _edit(context, ctl, p, state.profiles.length),
                ),
                IconButton(
                  iconSize: 15,
                  icon: Icon(Icons.delete_outline, color: t.danger),
                  onPressed: () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Delete profile ${p.label}?',
                      body:
                          'The profile is removed. Any keys it references in '
                          'the keychain are left untouched.',
                      confirmLabel: 'Delete',
                    );
                    if (ok) ctl.remove(p.id);
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add profile'),
            onPressed: () => _edit(context, ctl, null, state.profiles.length),
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    ProfilesController ctl,
    Profile? existing,
    int count,
  ) async {
    final data = await showProfileFormDialog(
      context,
      initial: existing == null
          ? null
          : (label: existing.label, name: existing.name, email: existing.email),
    );
    if (data == null) return;

    if (existing == null) {
      ctl.add(
        Profile(
          id: 'p${DateTime.now().microsecondsSinceEpoch}',
          label: data.label,
          name: data.name,
          email: data.email,
          colorValue: _palette[count % _palette.length],
        ),
      );
    } else {
      ctl.update(
        existing.copyWith(
          label: data.label,
          name: data.name,
          email: data.email,
        ),
      );
    }
  }
}
