/// Reading one side of a binary diff: what format an image is, how big it is,
/// how a blob is named to git, and the hex rows for anything that is not an
/// image. Only [BlobReader] runs git or touches the filesystem.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../file_edit.dart';
import 'git_service.dart';
import 'lfs.dart' show formatLfsSize;

/// Largest blob read into the app for a preview. A side above this shows its
/// size and nothing else, so a 300 MB PSD never lands in memory.
const blobPreviewMaxBytes = 32 * 1024 * 1024;

/// How much of a non-image binary the hex preview shows.
const hexPreviewBytes = 256;

/// Raster formats Flutter's codec decodes. SVG is text and git diffs it as
/// such, so it is not one of these.
enum ImageFormat { png, jpeg, gif, webp, bmp }

bool _startsWith(List<int> bytes, List<int> prefix, [int at = 0]) {
  if (bytes.length < at + prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[at + i] != prefix[i]) return false;
  }
  return true;
}

const _pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
final _riff = 'RIFF'.codeUnits;

/// Sizes a bitmap's info header can declare. Two bytes of `BM` are common
/// enough at the start of other files that they alone prove nothing.
const _bmpInfoSizes = {12, 40, 52, 56, 64, 108, 124};
final _webp = 'WEBP'.codeUnits;

/// The image format [bytes] open with, or null when they are not one of
/// [ImageFormat]. Decided by content, not by file name: a renamed or
/// extensionless image still previews, and a `.png` that is not one does not
/// reach the decoder.
ImageFormat? sniffImageFormat(List<int> bytes) {
  if (_startsWith(bytes, _pngMagic)) return ImageFormat.png;
  if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) return ImageFormat.jpeg;
  if (_startsWith(bytes, 'GIF87a'.codeUnits) ||
      _startsWith(bytes, 'GIF89a'.codeUnits)) {
    return ImageFormat.gif;
  }
  if (_startsWith(bytes, _riff) && _startsWith(bytes, _webp, 8)) {
    return ImageFormat.webp;
  }
  if (_startsWith(bytes, 'BM'.codeUnits) &&
      bytes.length >= 26 &&
      _bmpInfoSizes.contains(_le32(bytes, 14))) {
    return ImageFormat.bmp;
  }
  return null;
}

typedef ImageSize = ({int width, int height});

int _be16(List<int> b, int i) => (b[i] << 8) | b[i + 1];
int _be32(List<int> b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
int _le16(List<int> b, int i) => b[i] | (b[i + 1] << 8);
int _le24(List<int> b, int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16);
int _le32(List<int> b, int i) => _le24(b, i) | (b[i + 3] << 24);

/// Pixel size read from the header alone, without decoding the image. Null
/// for anything [sniffImageFormat] does not recognise or a header cut short.
ImageSize? imageDimensions(List<int> bytes) {
  try {
    return switch (sniffImageFormat(bytes)) {
      ImageFormat.png =>
        bytes.length < 24
            ? null
            : (width: _be32(bytes, 16), height: _be32(bytes, 20)),
      ImageFormat.gif => (width: _le16(bytes, 6), height: _le16(bytes, 8)),
      // The oldest header holds 16-bit sizes; every later one 32-bit signed.
      ImageFormat.bmp when _le32(bytes, 14) == 12 => (
        width: _le16(bytes, 18),
        height: _le16(bytes, 20),
      ),
      ImageFormat.bmp => (
        width: _le32(bytes, 18).toSigned(32).abs(),
        height: _le32(bytes, 22).toSigned(32).abs(),
      ),
      ImageFormat.webp => _webpSize(bytes),
      ImageFormat.jpeg => _jpegSize(bytes),
      null => null,
    };
  } on RangeError {
    return null;
  }
}

ImageSize? _webpSize(List<int> b) {
  const payload = 20;
  final chunk = String.fromCharCodes(b.sublist(12, 16));
  switch (chunk) {
    case 'VP8 ':
      return (
        width: _le16(b, payload + 6) & 0x3fff,
        height: _le16(b, payload + 8) & 0x3fff,
      );
    case 'VP8L':
      final bits = _le32(b, payload + 1);
      return (width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1);
    case 'VP8X':
      return (
        width: _le24(b, payload + 4) + 1,
        height: _le24(b, payload + 7) + 1,
      );
  }
  return null;
}

ImageSize? _jpegSize(List<int> b) {
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xff) return null;
    final marker = b[i + 1];
    // Padding fill bytes before a marker.
    if (marker == 0xff) {
      i++;
      continue;
    }
    // Start-of-frame markers carry the size; C4, C8 and CC share the range
    // but are tables, not frames.
    final isFrame =
        marker >= 0xc0 &&
        marker <= 0xcf &&
        marker != 0xc4 &&
        marker != 0xc8 &&
        marker != 0xcc;
    if (isFrame) {
      return (width: _be16(b, i + 7), height: _be16(b, i + 5));
    }
    i += 2 + _be16(b, i + 2);
  }
  return null;
}

/// One line of the hex preview. [changed] marks, per byte, where the other
/// side holds something different or nothing at all.
class HexRow {
  final int offset;
  final List<String> hex;
  final String ascii;
  final List<bool> changed;
  const HexRow({
    required this.offset,
    required this.hex,
    required this.ascii,
    required this.changed,
  });
}

/// The first [limit] bytes of [bytes] as rows of [perRow]. With [compareTo]
/// each byte is marked where that side differs.
List<HexRow> hexRows(
  Uint8List bytes, {
  Uint8List? compareTo,
  int limit = hexPreviewBytes,
  int perRow = 16,
}) {
  final end = bytes.length < limit ? bytes.length : limit;
  return [
    for (var start = 0; start < end; start += perRow)
      () {
        final stop = start + perRow < end ? start + perRow : end;
        final slice = bytes.sublist(start, stop);
        return HexRow(
          offset: start,
          hex: [for (final b in slice) b.toRadixString(16).padLeft(2, '0')],
          ascii: String.fromCharCodes([
            for (final b in slice) b >= 0x20 && b < 0x7f ? b : 0x2e,
          ]),
          changed: [
            for (var i = start; i < stop; i++)
              compareTo != null &&
                  (i >= compareTo.length || compareTo[i] != bytes[i]),
          ],
        );
      }(),
  ];
}

/// `+212 B`, `−2.0 KB`, `±0 B`; null when either side is missing, since an
/// added or deleted file has a size but no change in size.
String? formatSizeDelta(int? before, int? after) {
  if (before == null || after == null) return null;
  final d = after - before;
  final sign = d > 0 ? '+' : (d < 0 ? '−' : '±');
  return '$sign${formatLfsSize(d.abs())}';
}

/// `1000 B → 1.2 KB (+212 B)`, or the one size there is when a side is
/// missing.
String sizeSummary(int? before, int? after) {
  if (before == null || after == null) {
    final only = before ?? after;
    return only == null ? '' : formatLfsSize(only);
  }
  return '${formatLfsSize(before)} → ${formatLfsSize(after)} '
      '(${formatSizeDelta(before, after)})';
}

/// `10×20 → 12×20`, a single size when they match or only one side has one,
/// and null when neither does.
String? dimensionSummary(ImageSize? before, ImageSize? after) {
  String fmt(ImageSize s) => '${s.width}×${s.height}';
  if (before == null || after == null) {
    final only = before ?? after;
    return only == null ? null : fmt(only);
  }
  return before == after ? fmt(before) : '${fmt(before)} → ${fmt(after)}';
}

/// Longest side, in pixels, an image is decoded at. The byte cap bounds
/// what is read, not what it decodes to: a small file can hold a huge,
/// flat image, and each decoded pixel costs four bytes.
const maxDecodeExtent = 4096;

/// One factor to decode every image in [sizes] by, so the largest side of
/// any fits [maxDecodeExtent]. Shared, so the sides still compare at one
/// scale. 1 when everything fits.
double decodeScale(List<ImageSize> sizes) {
  var longest = 0;
  for (final s in sizes) {
    longest = [longest, s.width, s.height].reduce((a, b) => a > b ? a : b);
  }
  return longest > maxDecodeExtent ? maxDecodeExtent / longest : 1;
}

/// Upper bound on how far a small image is enlarged to fill the view.
const maxPreviewScale = 8.0;

/// One scale for every image in [sizes], fitting the largest extent of each
/// axis into [width]×[height]. Shared so a changed size reads as a change
/// instead of being scaled away.
double sharedScale(double width, double height, List<ImageSize> sizes) {
  if (sizes.isEmpty) return 1;
  var maxW = 0, maxH = 0;
  for (final s in sizes) {
    if (s.width > maxW) maxW = s.width;
    if (s.height > maxH) maxH = s.height;
  }
  if (maxW == 0 || maxH == 0) return 1;
  final fit = (width / maxW) < (height / maxH) ? width / maxW : height / maxH;
  if (fit <= 0) return 0;
  return fit > maxPreviewScale ? maxPreviewScale : fit;
}

/// Where one side of a binary diff lives.
sealed class BlobRef {
  const BlobRef();
  String get path;
}

/// `<rev>:<path>` — a file as some commit holds it.
class RevisionBlob extends BlobRef {
  final String rev;
  @override
  final String path;
  const RevisionBlob(this.rev, this.path);

  /// The name `git cat-file` takes, or null for a revision it would read as
  /// an option (or as nothing).
  String? get objectName =>
      rev.isEmpty || rev.startsWith('-') ? null : '$rev:$path';

  @override
  bool operator ==(Object other) =>
      other is RevisionBlob && other.rev == rev && other.path == path;

  @override
  int get hashCode => Object.hash('rev', rev, path);
}

/// A file as the index holds it. [stage] 2 and 3 are the two sides of a
/// conflict; 0 is the ordinary staged copy.
class IndexBlob extends BlobRef {
  @override
  final String path;
  final int stage;
  const IndexBlob(this.path, {this.stage = 0});

  String get objectName => stage == 0 ? ':$path' : ':$stage:$path';

  @override
  bool operator ==(Object other) =>
      other is IndexBlob && other.path == path && other.stage == stage;

  @override
  int get hashCode => Object.hash('index', path, stage);
}

/// The file on disk in the working tree.
class WorktreeBlob extends BlobRef {
  @override
  final String path;
  const WorktreeBlob(this.path);

  @override
  bool operator ==(Object other) => other is WorktreeBlob && other.path == path;

  @override
  int get hashCode => Object.hash('worktree', path);
}

/// One side of a binary diff as read. [bytes] is null when the side is over
/// the preview cap, so only its [size] is known.
class BlobLoad {
  final int size;
  final Uint8List? bytes;
  const BlobLoad({required this.size, this.bytes});

  bool get tooLarge => bytes == null;
}

/// Reads [BlobRef]s of the repository at [repoPath], never more than
/// [maxBytes] of any one.
class BlobReader {
  final GitService git;
  final GitBytesRunner bytes;
  final String repoPath;
  final int maxBytes;
  const BlobReader({
    required this.git,
    required this.bytes,
    required this.repoPath,
    this.maxBytes = blobPreviewMaxBytes,
  });

  /// The side [ref] names, or null when it does not exist or cannot be read
  /// safely.
  Future<BlobLoad?> read(BlobRef ref) => switch (ref) {
    RevisionBlob(:final objectName) => _object(objectName),
    IndexBlob(:final objectName) => _object(objectName),
    WorktreeBlob(:final path) => _worktree(path),
  };

  Future<BlobLoad?> _object(String? name) async {
    if (name == null) return null;
    // Sized first, so a blob over the cap is never streamed at all.
    final r = await git.run(['cat-file', '-s', name], repoPath: repoPath);
    final size = r.ok ? int.tryParse(r.out) : null;
    if (size == null) return null;
    if (size > maxBytes) return BlobLoad(size: size);
    final out = await bytes.runBytes(
      ['cat-file', 'blob', name],
      repoPath: repoPath,
      maxBytes: maxBytes,
    );
    return out == null ? null : BlobLoad(size: out.length, bytes: out);
  }

  Future<BlobLoad?> _worktree(String path) async {
    if (!isRepoRelativePath(path)) return null;
    final full = p.join(repoPath, path);
    final file = File(full);
    if (!await file.exists() || !isInsideRepo(repoPath, full)) return null;
    final size = await file.length();
    if (size > maxBytes) return BlobLoad(size: size);
    // Bounded too: the file can grow between being sized and being read.
    final out = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, maxBytes + 1)) {
      out.add(chunk);
    }
    if (out.length > maxBytes) return BlobLoad(size: out.length);
    final data = out.takeBytes();
    return BlobLoad(size: data.length, bytes: data);
  }
}

/// What a binary diff can show for its two sides.
enum BinaryPreviewKind { image, hex, tooLarge, empty }

BinaryPreviewKind binaryPreviewKind(BlobLoad? before, BlobLoad? after) {
  final sides = [?before, ?after];
  if (sides.isEmpty) return BinaryPreviewKind.empty;
  if (sides.any((s) => s.tooLarge)) return BinaryPreviewKind.tooLarge;
  return sides.every((s) => sniffImageFormat(s.bytes!) != null)
      ? BinaryPreviewKind.image
      : BinaryPreviewKind.hex;
}
