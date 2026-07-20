import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/profiles.dart';
import 'profile_form.dart';

/// Blocking first-run screen shown when no profile exists. Groups and repos all
/// belong to a profile, so one must be created before the app is usable. There
/// is no way to dismiss it.
class FirstProfileScreen extends ConsumerWidget {
  const FirstProfileScreen({super.key});

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
    return Scaffold(
      backgroundColor: t.bgApp,
      body: Center(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.person_add_alt_1, size: 40, color: t.accent),
              const SizedBox(height: 16),
              Text(
                'Create your first profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Every group and repository belongs to a profile. Switching '
                'profiles later shows only that profile’s work.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textFaint, fontSize: 12.5),
              ),
              const SizedBox(height: 24),
              ProfileFormBody(
                showCancel: false,
                submitLabel: 'Create profile',
                onSubmit: (d) => ref
                    .read(profilesProvider.notifier)
                    .add(
                      Profile(
                        id: 'p${DateTime.now().microsecondsSinceEpoch}',
                        label: d.label,
                        name: d.name,
                        email: d.email,
                        colorValue: _palette[0],
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
