import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blob.dart';

/// Big-endian u32.
List<int> _be32(int v) => [
  (v >> 24) & 0xff,
  (v >> 16) & 0xff,
  (v >> 8) & 0xff,
  v & 0xff,
];

/// Little-endian u16 / u32.
List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [..._le16(v & 0xffff), ..._le16(v >> 16)];

const _pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

List<int> _png(int w, int h) => [
  ..._pngMagic,
  ..._be32(13),
  ...'IHDR'.codeUnits,
  ..._be32(w),
  ..._be32(h),
  8, 6, 0, 0, 0, // bit depth, colour type, compression, filter, interlace
];

List<int> _gif(int w, int h) => [
  ...'GIF89a'.codeUnits,
  ..._le16(w),
  ..._le16(h),
  0,
  0,
  0,
];

List<int> _riff(String chunk, List<int> payload) => [
  ...'RIFF'.codeUnits,
  ..._le32(4 + 8 + payload.length),
  ...'WEBP'.codeUnits,
  ...chunk.codeUnits,
  ..._le32(payload.length),
  ...payload,
];

void main() {
  group('sniffImageFormat', () {
    test('recognises each raster format by its magic bytes', () {
      expect(sniffImageFormat(_png(1, 1)), ImageFormat.png);
      expect(
        sniffImageFormat([0xff, 0xd8, 0xff, 0xe0, 0, 0]),
        ImageFormat.jpeg,
      );
      expect(sniffImageFormat(_gif(1, 1)), ImageFormat.gif);
      expect(
        sniffImageFormat('GIF87a\x01\x00\x01\x00'.codeUnits),
        ImageFormat.gif,
      );
      expect(
        sniffImageFormat(_riff('VP8 ', List.filled(10, 0))),
        ImageFormat.webp,
      );
      expect(
        sniffImageFormat([
          ...'BM'.codeUnits,
          ...List.filled(12, 0),
          ..._le32(40),
          ...List.filled(16, 0),
        ]),
        ImageFormat.bmp,
      );
    });

    test('a file that merely starts with BM is not taken for a bitmap', () {
      // A bitmap's info header declares one of a few known sizes.
      final notBmp = [...'BM'.codeUnits, ...List.filled(30, 0x41)];
      expect(sniffImageFormat(notBmp), isNull);
      final bmp = [
        ...'BM'.codeUnits,
        ...List.filled(12, 0),
        ..._le32(124),
        ...List.filled(16, 0),
      ];
      expect(sniffImageFormat(bmp), ImageFormat.bmp);
    });

    test('a RIFF container that is not WebP is not an image', () {
      final wav = [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits];
      expect(sniffImageFormat(wav), isNull);
    });

    test('anything else, or too few bytes, is not an image', () {
      expect(sniffImageFormat(const []), isNull);
      expect(sniffImageFormat(_pngMagic.sublist(0, 4)), isNull);
      expect(sniffImageFormat('%PDF-1.7'.codeUnits), isNull);
      expect(sniffImageFormat([0x50, 0x4b, 0x03, 0x04]), isNull);
    });
  });

  group('imageDimensions', () {
    test('PNG reads width and height from IHDR', () {
      expect(imageDimensions(_png(640, 480)), (width: 640, height: 480));
    });

    test('GIF reads the logical screen size', () {
      expect(imageDimensions(_gif(300, 2)), (width: 300, height: 2));
    });

    test('BMP reads the info header, a negative height meaning top-down', () {
      List<int> bmp(int w, int h) => [
        ...'BM'.codeUnits,
        ...List.filled(12, 0),
        ..._le32(40),
        ..._le32(w),
        ..._le32(h & 0xffffffff),
      ];
      expect(imageDimensions(bmp(17, 9)), (width: 17, height: 9));
      expect(imageDimensions(bmp(17, -9)), (width: 17, height: 9));
    });

    test('WebP lossy reads the 14-bit sizes after the frame tag', () {
      final vp8 = [
        0, 0, 0, // frame tag
        0x9d, 0x01, 0x2a, // start code
        ..._le16(400),
        ..._le16(300 | (1 << 14)), // a scale bit above the size is ignored
      ];
      expect(imageDimensions(_riff('VP8 ', vp8)), (width: 400, height: 300));
    });

    test('WebP lossless unpacks width-1 and height-1 from 28 bits', () {
      const w = 1000, h = 750;
      final bits = (w - 1) | ((h - 1) << 14);
      final vp8l = [0x2f, ..._le32(bits)];
      expect(imageDimensions(_riff('VP8L', vp8l)), (width: w, height: h));
    });

    test('WebP extended reads 24-bit canvas size minus one', () {
      List<int> le24(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff];
      final vp8x = [0, 0, 0, 0, ...le24(1919), ...le24(1079)];
      expect(imageDimensions(_riff('VP8X', vp8x)), (width: 1920, height: 1080));
    });

    test('JPEG skips segments until a start-of-frame marker', () {
      final jpeg = [
        0xff, 0xd8, // SOI
        0xff, 0xe0, 0x00, 0x04, 0xaa, 0xbb, // APP0, 2 payload bytes
        0xff, 0xc2, 0x00, 0x0b, 0x08, // SOF2 (progressive), precision
        0x01, 0x2c, // height 300
        0x01, 0x90, // width 400
        0x03,
      ];
      expect(imageDimensions(jpeg), (width: 400, height: 300));
    });

    test('a DHT marker (0xC4) is not mistaken for a frame', () {
      final jpeg = [
        0xff, 0xd8,
        0xff, 0xc4, 0x00, 0x07, 0x00, 0x09, 0x00, 0x09, 0x00, // DHT
        0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x10, 0x00, 0x20, 0x03,
      ];
      expect(imageDimensions(jpeg), (width: 32, height: 16));
    });

    test('JPEG fill bytes before a marker are skipped', () {
      final jpeg = [
        0xff,
        0xd8,
        0xff,
        0xff,
        0xff,
        0xc0,
        0x00,
        0x0b,
        0x08,
        0x00,
        0x02,
        0x00,
        0x03,
        0x03,
      ];
      expect(imageDimensions(jpeg), (width: 3, height: 2));
    });

    test('WebP lossy ignores the scale bits on the width too', () {
      final vp8 = [
        0,
        0,
        0,
        0x9d,
        0x01,
        0x2a,
        ..._le16(400 | (2 << 14)),
        ..._le16(300),
      ];
      expect(imageDimensions(_riff('VP8 ', vp8)), (width: 400, height: 300));
    });

    test('truncated or unknown input gives null rather than throwing', () {
      expect(imageDimensions(_png(1, 1).sublist(0, 20)), isNull);
      expect(imageDimensions([0xff, 0xd8, 0xff, 0xe0, 0x00]), isNull);
      expect(imageDimensions(_riff('VP8 ', [0, 0])), isNull);
      expect(imageDimensions('hello'.codeUnits), isNull);
    });
  });

  group('hexRows', () {
    test(
      'lays bytes out sixteen to a row with offsets and printable ascii',
      () {
        final bytes = Uint8List.fromList([...'Hello'.codeUnits, 0, 0x7f, 0x41]);
        final rows = hexRows(bytes);
        expect(rows, hasLength(1));
        expect(rows.single.offset, 0);
        expect(rows.single.hex, [
          '48',
          '65',
          '6c',
          '6c',
          '6f',
          '00',
          '7f',
          '41',
        ]);
        expect(rows.single.ascii, 'Hello..A');
      },
    );

    test('stops at the limit and starts each row at its offset', () {
      final bytes = Uint8List.fromList(List.generate(40, (i) => i));
      final rows = hexRows(bytes, limit: 20);
      expect(rows.map((r) => r.offset), [0, 16]);
      expect(rows.last.hex, ['10', '11', '12', '13']);
    });

    test('marks bytes that differ from, or run past, the other side', () {
      final mine = Uint8List.fromList([1, 2, 3, 4]);
      final other = Uint8List.fromList([1, 9, 3]);
      final row = hexRows(mine, compareTo: other).single;
      expect(row.changed, [false, true, false, true]);
    });

    test('nothing is marked changed without another side', () {
      final row = hexRows(Uint8List.fromList([1, 2])).single;
      expect(row.changed, [false, false]);
    });
  });

  group('formatSizeDelta', () {
    test('signs the difference in human units', () {
      expect(formatSizeDelta(1000, 1212), '+212 B');
      expect(formatSizeDelta(4096, 2048), '−2.0 KB');
      expect(formatSizeDelta(5, 5), '±0 B');
    });

    test('a missing side has no delta', () {
      expect(formatSizeDelta(null, 10), isNull);
      expect(formatSizeDelta(10, null), isNull);
    });
  });

  group('BlobRef', () {
    test(
      'names revision, index and conflict-stage blobs the way git reads them',
      () {
        expect(
          const RevisionBlob('abc123', 'img/a.png').objectName,
          'abc123:img/a.png',
        );
        expect(const RevisionBlob('abc^', 'a.png').objectName, 'abc^:a.png');
        expect(const IndexBlob('a.png').objectName, ':a.png');
        expect(const IndexBlob('a.png', stage: 2).objectName, ':2:a.png');
      },
    );

    test('a revision that git would read as an option has no object name', () {
      expect(const RevisionBlob('-x', 'a.png').objectName, isNull);
      expect(const RevisionBlob('', 'a.png').objectName, isNull);
    });

    test('equal refs are equal, so providers keyed on them are shared', () {
      expect(const RevisionBlob('a', 'p'), const RevisionBlob('a', 'p'));
      expect(const IndexBlob('p', stage: 3), const IndexBlob('p', stage: 3));
      expect(const IndexBlob('p'), isNot(const IndexBlob('p', stage: 2)));
      expect(const WorktreeBlob('p'), const WorktreeBlob('p'));
      expect(const WorktreeBlob('p'), isNot(const IndexBlob('p')));
    });
  });

  group('binaryPreviewKind', () {
    final png = BlobLoad(size: 24, bytes: Uint8List.fromList(_png(2, 2)));
    final bin = BlobLoad(size: 3, bytes: Uint8List.fromList([0, 1, 2]));
    const huge = BlobLoad(size: 1 << 30);

    test('images on every side present preview as images', () {
      expect(binaryPreviewKind(png, png), BinaryPreviewKind.image);
      expect(binaryPreviewKind(null, png), BinaryPreviewKind.image);
      expect(binaryPreviewKind(png, null), BinaryPreviewKind.image);
    });

    test('a side that is not an image turns the whole preview to hex', () {
      expect(binaryPreviewKind(png, bin), BinaryPreviewKind.hex);
      expect(binaryPreviewKind(bin, null), BinaryPreviewKind.hex);
    });

    test('a side over the cap means no preview, whatever the other is', () {
      expect(binaryPreviewKind(huge, png), BinaryPreviewKind.tooLarge);
      expect(binaryPreviewKind(bin, huge), BinaryPreviewKind.tooLarge);
    });

    test('no side at all is empty', () {
      expect(binaryPreviewKind(null, null), BinaryPreviewKind.empty);
    });
  });

  group('summaries', () {
    test('sizes read old to new with the delta, or the one size alone', () {
      expect(sizeSummary(1000, 1212), '1000 B → 1.2 KB (+212 B)');
      expect(sizeSummary(null, 2048), '2.0 KB');
      expect(sizeSummary(2048, null), '2.0 KB');
      expect(sizeSummary(null, null), '');
    });

    test('dimensions read old to new, and a side without one is left out', () {
      expect(
        dimensionSummary((width: 10, height: 20), (width: 12, height: 20)),
        '10×20 → 12×20',
      );
      expect(
        dimensionSummary((width: 10, height: 20), (width: 10, height: 20)),
        '10×20',
      );
      expect(dimensionSummary(null, (width: 3, height: 4)), '3×4');
      expect(dimensionSummary(null, null), isNull);
    });
  });

  group('sharedScale', () {
    test('fits the larger image, so both sides keep one scale', () {
      final s = sharedScale(400, 300, [
        (width: 800, height: 300),
        (width: 200, height: 600),
      ]);
      expect(s, 0.5);
    });

    test('small images grow, but never past the cap', () {
      expect(sharedScale(400, 400, [(width: 200, height: 100)]), 2);
      expect(sharedScale(4000, 4000, [(width: 2, height: 2)]), maxPreviewScale);
    });

    test('nothing to fit, or no room, is scale 1 or 0', () {
      expect(sharedScale(100, 100, const []), 1);
      expect(sharedScale(0, 100, [(width: 2, height: 2)]), 0);
    });
  });

  group('decodeScale', () {
    test('images within the pixel budget decode at full size', () {
      expect(decodeScale([(width: 4000, height: 3000)]), 1);
      expect(decodeScale(const []), 1);
    });

    test('one factor shrinks every side so the largest fits the budget', () {
      final f = decodeScale([
        (width: 16384, height: 16384),
        (width: 100, height: 100),
      ]);
      expect(16384 * f, lessThanOrEqualTo(maxDecodeExtent));
      expect(16384 * f, greaterThan(maxDecodeExtent - 1));
    });

    test('a long thin image is bounded by its long side', () {
      final f = decodeScale([(width: 100, height: 60000)]);
      expect(60000 * f, lessThanOrEqualTo(maxDecodeExtent));
    });
  });
}
