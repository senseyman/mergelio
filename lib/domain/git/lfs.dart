/// LFS pointer file parsing: extract the content identifier and size.
/// Nothing here runs git, touches the filesystem, or networks.
library;

import 'dart:convert';

/// The version line every LFS pointer opens with.
const lfsPointerVersion = 'version https://git-lfs.github.com/spec/v1';

/// Pointers are tiny by definition; anything bigger is real content that
/// merely looks like one.
const lfsPointerMaxBytes = 1024;

/// What a pointer file says about the content it stands in for.
class LfsPointer {
  /// Lowercase hex sha256 of the real content, without the `sha256:` prefix.
  final String oid;
  final int size;
  const LfsPointer({required this.oid, required this.size});

  @override
  bool operator ==(Object other) =>
      other is LfsPointer && other.oid == oid && other.size == size;

  @override
  int get hashCode => Object.hash(oid, size);
}

final _oidValue = RegExp(r'^sha256:([0-9a-f]{64})$');
final _sizeValue = RegExp(r'^(0|[1-9][0-9]*)$');
final _keyName = RegExp(r'^[a-z0-9.-]+$');

/// Parses [text] as a pointer, returning null for anything else.
///
/// Strict on purpose: a loose match would turn an ordinary small text file
/// that happens to mention the spec into an "LFS object" and hide its
/// real diff.
LfsPointer? parseLfsPointer(String text) {
  // UTF-16 units never outnumber UTF-8 bytes, so this cheap check rejects
  // big files before any encoding work.
  if (text.length > lfsPointerMaxBytes) return null;
  if (utf8.encode(text).length > lfsPointerMaxBytes) return null;
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  if (lines.isEmpty || lines.first != lfsPointerVersion) return null;

  String? oid;
  int? size;
  String? previousKey;

  for (final line in lines.skip(1)) {
    final space = line.indexOf(' ');
    if (space <= 0) return null;
    final key = line.substring(0, space);
    final value = line.substring(space + 1);
    if (!_keyName.hasMatch(key)) return null;
    // Keys must be in sorted order.
    if (previousKey != null && key.compareTo(previousKey) <= 0) return null;
    previousKey = key;
    switch (key) {
      case 'oid':
        oid = _oidValue.firstMatch(value)?.group(1);
        if (oid == null) return null;
      case 'size':
        if (!_sizeValue.hasMatch(value)) return null;
        size = int.tryParse(value);
        if (size == null) return null;
    }
  }
  if (oid == null || size == null) return null;
  return LfsPointer(oid: oid, size: size);
}
