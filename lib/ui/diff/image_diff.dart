import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/blob.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/binary_diff.dart';

/// Both sides of a binary change, previewed: images compared at one scale,
/// anything else as hex. [version] is handed through to [BlobRequest] so a
/// side that lives in the index or on disk is read again when the diff is.
class BinaryCompare extends ConsumerWidget {
  final String repoPath;
  final BinarySides sides;
  final Object? version;

  /// What to call each side; "Before" and "After" when not given.
  final String? beforeLabel;
  final String? afterLabel;

  const BinaryCompare({
    super.key,
    required this.repoPath,
    required this.sides,
    this.version,
    this.beforeLabel,
    this.afterLabel,
  });

  AsyncValue<BlobLoad?> _side(WidgetRef ref, BlobRef? side) => side == null
      ? const AsyncData(null)
      : ref.watch(
          blobProvider(
            BlobRequest(
              repoPath: repoPath,
              ref: side,
              // A revision names fixed content, so it can stay cached.
              version: side is RevisionBlob ? null : version,
            ),
          ),
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final before = _side(ref, sides.before);
    final after = _side(ref, sides.after);
    Widget note(String text, [String? detail]) => Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textFaint, fontSize: 12),
            ),
            if (detail != null)
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textMuted, fontSize: 11.5),
              ),
          ],
        ),
      ),
    );
    if (before.hasError || after.hasError) return note(l.bdUnavailable);
    if (!before.hasValue || !after.hasValue) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final a = before.value, b = after.value;
    final labels = (
      before: beforeLabel ?? l.bdBefore,
      after: afterLabel ?? l.bdAfter,
    );
    final sizes = sizeSummary(a?.size, b?.size);
    final preview = switch (binaryPreviewKind(a, b)) {
      BinaryPreviewKind.empty => note(l.bdNothingToShow),
      BinaryPreviewKind.tooLarge => note(l.bdTooLarge, sizes),
      BinaryPreviewKind.image => ImageCompareView(
        before: a?.bytes,
        after: b?.bytes,
        sizes: sizes,
        labels: labels,
      ),
      BinaryPreviewKind.hex => HexCompareView(
        before: a?.bytes,
        after: b?.bytes,
        sizes: sizes,
        labels: labels,
      ),
    };
    // A sheet dragged short gets a scrolling preview at a usable height
    // rather than one squeezed into overflow.
    return LayoutBuilder(
      builder: (context, box) => box.maxHeight >= _minPreviewHeight
          ? preview
          : SingleChildScrollView(
              child: SizedBox(height: _minPreviewHeight, child: preview),
            ),
    );
  }
}

/// Room the mode bar, an image and the slider need together.
const _minPreviewHeight = 160.0;

typedef SideLabels = ({String before, String after});

/// The ways two versions of an image are laid against each other.
enum ImageCompareMode { sideBySide, swipe, onionSkin, difference }

/// Two versions of an image at one shared scale. With only one side — an
/// added or deleted image — there is nothing to compare, so it is shown alone.
class ImageCompareView extends StatefulWidget {
  final Uint8List? before;
  final Uint8List? after;
  final String sizes;
  final SideLabels labels;

  const ImageCompareView({
    super.key,
    required this.before,
    required this.after,
    required this.sizes,
    required this.labels,
  });

  @override
  State<ImageCompareView> createState() => _ImageCompareViewState();
}

class _ImageCompareViewState extends State<ImageCompareView> {
  var _mode = ImageCompareMode.sideBySide;

  /// Swipe position, or the after image's opacity in onion skin.
  var _mix = 0.5;

  ui.Image? _before, _after;

  /// Header sizes of the two sides, read once per set of bytes: a JPEG's is
  /// found by walking its segments, too much to redo on every slider drag.
  ImageSize? _beforeSize, _afterSize;
  var _failed = false;

  /// Bumped per decode so a slow one for old bytes cannot land late.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(ImageCompareView old) {
    super.didUpdateWidget(old);
    if (!identical(old.before, widget.before) ||
        !identical(old.after, widget.after)) {
      _decode();
    }
  }

  @override
  void dispose() {
    _generation++;
    _before?.dispose();
    _after?.dispose();
    super.dispose();
  }

  /// [bytes], whose header gave [size], decoded with each side shrunk by
  /// [factor]; null when there is no such side.
  static Future<ui.Image?> _image(
    Uint8List? bytes,
    ImageSize? size,
    double factor,
  ) async {
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: factor < 1 && size != null
          ? math.max(1, (size.width * factor).round())
          : null,
      targetHeight: factor < 1 && size != null
          ? math.max(1, (size.height * factor).round())
          : null,
    );
    try {
      // An animation previews as its first frame.
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> _decode() async {
    final gen = ++_generation;
    _beforeSize = widget.before == null
        ? null
        : imageDimensions(widget.before!);
    _afterSize = widget.after == null ? null : imageDimensions(widget.after!);
    final factor = decodeScale([?_beforeSize, ?_afterSize]);
    // Each side settles on its own, so one that fails cannot strand the other
    // undisposed.
    var failed = false;
    Future<ui.Image?> side(Uint8List? bytes, ImageSize? size) =>
        _image(bytes, size, factor).catchError((Object _) {
          failed = true;
          return null;
        });
    final images = await Future.wait([
      side(widget.before, _beforeSize),
      side(widget.after, _afterSize),
    ]);
    if (gen != _generation || !mounted) {
      for (final i in images) {
        i?.dispose();
      }
      return;
    }
    setState(() {
      _before?.dispose();
      _after?.dispose();
      _before = images[0];
      _after = images[1];
      _failed = failed;
    });
  }

  bool get _both => widget.before != null && widget.after != null;

  @override
  Widget build(BuildContext context) {
    // Looked like an image, but is not one the codec can read: the bytes are
    // still worth seeing.
    if (_failed) {
      return HexCompareView(
        before: widget.before,
        after: widget.after,
        sizes: widget.sizes,
        labels: widget.labels,
      );
    }
    final t = context.tokens;
    final dims = dimensionSummary(_beforeSize, _afterSize);
    final summary = [?dims, widget.sizes].join(' · ');
    final slider =
        _both &&
        (_mode == ImageCompareMode.swipe ||
            _mode == ImageCompareMode.onionSkin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_both)
                _ModeToggle(
                  mode: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
              Text(
                summary,
                style: TextStyle(color: t.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        Expanded(child: _body(t)),
        if (slider)
          SizedBox(
            height: 32,
            child: Slider(
              value: _mix,
              onChanged: (v) => setState(() => _mix = v),
            ),
          ),
      ],
    );
  }

  Widget _body(AppTokens t) {
    final ready =
        (widget.before == null || _before != null) &&
        (widget.after == null || _after != null);
    final mode = _both ? _mode : ImageCompareMode.sideBySide;
    return LayoutBuilder(
      key: ready ? const ValueKey('image-compare-ready') : null,
      builder: (context, box) => mode == ImageCompareMode.sideBySide
          ? _sideBySide(t, box, ready)
          : _overlay(t, box, mode, ready),
    );
  }

  List<ImageSize> get _sizes => [
    for (final i in [_before, _after])
      if (i != null) (width: i.width, height: i.height),
  ];

  static const _labelHeight = 20.0;
  static const _pad = 8.0;

  Widget _sideBySide(AppTokens t, BoxConstraints box, bool ready) {
    final sides = [
      if (widget.before != null) (widget.labels.before, _before),
      if (widget.after != null) (widget.labels.after, _after),
    ];
    final cellW = (box.maxWidth - _pad * (sides.length + 1)) / sides.length;
    final cellH = box.maxHeight - _labelHeight - _pad * 2;
    final scale = ready
        ? sharedScale(math.max(0, cellW), math.max(0, cellH), _sizes)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.all(_pad / 2),
      child: Row(
        children: [
          for (final (label, image) in sides)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(_pad / 2),
                child: Column(
                  children: [
                    SizedBox(
                      height: _labelHeight,
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textFaint, fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: image == null
                            ? const SizedBox.shrink()
                            : _Framed(
                                t: t,
                                width: image.width * scale,
                                height: image.height * scale,
                                child: RawImage(
                                  image: image,
                                  width: image.width * scale,
                                  height: image.height * scale,
                                  fit: BoxFit.fill,
                                  filterQuality: _quality(scale),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _overlay(
    AppTokens t,
    BoxConstraints box,
    ImageCompareMode mode,
    bool ready,
  ) {
    final a = _before, b = _after;
    if (!ready || a == null || b == null) return const SizedBox.expand();
    final scale = sharedScale(
      math.max(0, box.maxWidth - _pad * 2),
      math.max(0, box.maxHeight - _pad * 2),
      _sizes,
    );
    final w = math.max(a.width, b.width) * scale;
    final h = math.max(a.height, b.height) * scale;
    final paint = _Framed(
      t: t,
      width: w,
      height: h,
      child: CustomPaint(
        size: Size(w, h),
        painter: ImageOverlayPainter(
          before: a,
          after: b,
          scale: scale,
          mode: mode,
          mix: _mix,
          divider: t.accent,
          quality: _quality(scale),
        ),
      ),
    );
    return Center(
      child: mode == ImageCompareMode.swipe
          // Dragging across the image moves the divider, as the slider does.
          ? GestureDetector(
              onHorizontalDragUpdate: (d) => setState(
                () => _mix = w <= 0
                    ? _mix
                    : (d.localPosition.dx / w).clamp(0.0, 1.0),
              ),
              child: paint,
            )
          : paint,
    );
  }

  /// Enlarged images keep hard pixel edges, which is where a one-pixel change
  /// shows; shrunk ones are smoothed.
  static FilterQuality _quality(double scale) =>
      scale >= 2 ? FilterQuality.none : FilterQuality.medium;
}

/// An image area with a hairline edge, so a transparent image still shows
/// where it ends.
class _Framed extends StatelessWidget {
  final AppTokens t;
  final double width;
  final double height;
  final Widget child;
  const _Framed({
    required this.t,
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(border: Border.all(color: t.border)),
    child: SizedBox(width: width, height: height, child: child),
  );
}

class ImageOverlayPainter extends CustomPainter {
  final ui.Image before;
  final ui.Image after;
  final double scale;
  final ImageCompareMode mode;
  final double mix;
  final Color divider;
  final FilterQuality quality;

  ImageOverlayPainter({
    required this.before,
    required this.after,
    required this.scale,
    required this.mode,
    required this.mix,
    required this.divider,
    required this.quality,
  });

  /// Draws [image] centred in [size], as the side-by-side cells place it.
  /// A side that changed size then differs evenly around its edges rather
  /// than only along the right and bottom, and in difference mode the pixels
  /// that line up are the ones compared.
  void _draw(Canvas canvas, Size size, ui.Image image, Paint paint) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final w = image.width * scale, h = image.height * scale;
    final dst = Rect.fromLTWH(
      ((size.width - w) / 2).roundToDouble(),
      ((size.height - h) / 2).roundToDouble(),
      w,
      h,
    );
    canvas.drawImageRect(image, src, dst, paint..filterQuality = quality);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Offset.zero & size;
    canvas.clipRect(whole);
    switch (mode) {
      case ImageCompareMode.swipe:
        // Before on the left of the divider, after on the right.
        _draw(canvas, size, before, Paint());
        final x = size.width * mix;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(x, 0, size.width, size.height));
        _draw(canvas, size, after, Paint());
        canvas.restore();
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = divider
            ..strokeWidth = 1.5,
        );
      case ImageCompareMode.onionSkin:
        _draw(canvas, size, before, Paint());
        canvas.saveLayer(whole, Paint()..color = Color.fromRGBO(0, 0, 0, mix));
        _draw(canvas, size, after, Paint());
        canvas.restore();
      case ImageCompareMode.difference:
        // Unchanged pixels cancel to black; anything that changed lights up.
        canvas.drawRect(whole, Paint()..color = const Color(0xFF000000));
        _draw(canvas, size, before, Paint());
        _draw(canvas, size, after, Paint()..blendMode = BlendMode.difference);
      case ImageCompareMode.sideBySide:
        break;
    }
  }

  @override
  bool shouldRepaint(ImageOverlayPainter old) =>
      old.before != before ||
      old.after != after ||
      old.scale != scale ||
      old.mode != mode ||
      old.mix != mix ||
      old.divider != divider ||
      old.quality != quality;
}

class _ModeToggle extends StatelessWidget {
  final ImageCompareMode mode;
  final ValueChanged<ImageCompareMode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    String label(ImageCompareMode m) => switch (m) {
      ImageCompareMode.sideBySide => l.bdSideBySide,
      ImageCompareMode.swipe => l.bdSwipe,
      ImageCompareMode.onionSkin => l.bdOnionSkin,
      ImageCompareMode.difference => l.bdDifference,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Wrap(
          children: [
            for (final m in ImageCompareMode.values)
              // Colour alone marks the current mode; a screen reader needs it
              // said.
              Semantics(
                button: true,
                selected: m == mode,
                child: InkWell(
                  onTap: () => onChanged(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    color: m == mode ? t.active : null,
                    child: Text(
                      label(m),
                      style: TextStyle(
                        color: m == mode ? t.textPrimary : t.textFaint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The opening bytes of each side in hex, bytes that differ from the other
/// side marked.
class HexCompareView extends StatelessWidget {
  final Uint8List? before;
  final Uint8List? after;
  final String sizes;
  final SideLabels labels;

  const HexCompareView({
    super.key,
    required this.before,
    required this.after,
    required this.sizes,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final shown = math.min(
      hexPreviewBytes,
      math.max(before?.length ?? 0, after?.length ?? 0),
    );
    final sides = [
      if (before != null)
        (labels.before, hexRows(before!, compareTo: after), t.delWord),
      if (after != null)
        (labels.after, hexRows(after!, compareTo: before), t.addWord),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Text(
            '${l.bdHexPreview(shown)} · $sizes',
            style: TextStyle(color: t.textMuted, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (label, rows, mark) in sides)
                Expanded(
                  child: _HexColumn(label: label, rows: rows, mark: mark),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HexColumn extends StatelessWidget {
  final String label;
  final List<HexRow> rows;
  final Color mark;
  const _HexColumn({
    required this.label,
    required this.rows,
    required this.mark,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final code = AppFonts.mns(size: 11.5, height: 1.4, color: t.textPrimary);
    final faint = code.copyWith(color: t.textFaint);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.textFaint, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final row in rows)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${row.offset.toRadixString(16).padLeft(8, '0')}  ',
                                style: faint,
                              ),
                              for (var i = 0; i < row.hex.length; i++)
                                TextSpan(
                                  text: '${row.hex[i]} ',
                                  style: row.changed[i]
                                      ? code.copyWith(backgroundColor: mark)
                                      : code,
                                ),
                              // Short last row: pad so the text column lines up.
                              TextSpan(
                                text:
                                    ' ${'   ' * (hexBytesPerRow - row.hex.length)}',
                                style: code,
                              ),
                              TextSpan(text: row.ascii, style: faint),
                            ],
                          ),
                          softWrap: false,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
