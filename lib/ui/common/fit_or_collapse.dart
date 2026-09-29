import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shows [full] when its natural width fits the space given, otherwise
/// [compact] — typically a row of labelled buttons that folds into a single
/// menu button.
///
/// The choice is made from [full]'s measured width rather than a fixed
/// breakpoint, so it stays right whatever the locale, font or set of buttons
/// currently shown. Both children are laid out, but only the chosen one is
/// painted, hit-tested and exposed to accessibility; the unused one is never
/// painted, so a [full] row that does not fit reports no overflow.
///
/// Needs a bounded max width: inside a [Row], constrain it (for example with a
/// [ConstrainedBox]) rather than leaving it unbounded.
class FitOrCollapse extends MultiChildRenderObjectWidget {
  FitOrCollapse({super.key, required Widget full, required Widget compact})
    : super(children: [full, compact]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFitOrCollapse();
}

class _FitOrCollapseParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFitOrCollapse extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FitOrCollapseParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FitOrCollapseParentData> {
  bool _useFull = true;

  RenderBox get _full => firstChild!;
  RenderBox get _compact => childAfter(firstChild!)!;
  RenderBox get _shown => _useFull ? _full : _compact;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FitOrCollapseParentData) {
      child.parentData = _FitOrCollapseParentData();
    }
  }

  @override
  void performLayout() {
    final loose = constraints.loosen();
    _useFull =
        _full.getMaxIntrinsicWidth(constraints.maxHeight) <=
        constraints.maxWidth;
    _full.layout(loose, parentUsesSize: true);
    _compact.layout(loose, parentUsesSize: true);
    size = constraints.constrain(_shown.size);
    for (final child in [_full, _compact]) {
      final data = child.parentData! as _FitOrCollapseParentData;
      data.offset = Offset(0, (size.height - child.size.height) / 2);
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _compact.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _full.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _shown.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _shown.getMaxIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) {
    final data = _shown.parentData! as _FitOrCollapseParentData;
    context.paintChild(_shown, offset + data.offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final data = _shown.parentData! as _FitOrCollapseParentData;
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest: (result, transformed) =>
          _shown.hitTest(result, position: transformed),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) =>
      visitor(_shown);
}
