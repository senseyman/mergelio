import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/diagnostics.dart';

/// Preferences row pointing at the diagnostic log, with a button that opens it
/// in the file manager. The path is shown in full so it can still be found by
/// hand — for a bug report, say — when the reveal itself fails.
class LogsRow extends ConsumerStatefulWidget {
  const LogsRow({super.key});

  @override
  ConsumerState<LogsRow> createState() => _LogsRowState();
}

class _LogsRowState extends ConsumerState<LogsRow> {
  String? _error;

  Future<void> _reveal(String path) async {
    setState(() => _error = null);
    try {
      await ref.read(revealProvider)(path);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the log folder: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final path = ref.watch(logFilePathProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diagnostic logs',
                      style: TextStyle(color: t.textPrimary, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      path ?? 'File logging is not active',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textFaint,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: path == null ? null : () => _reveal(path),
                child: const Text('Reveal', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: TextStyle(color: t.danger, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
