/// Fixed geometry of the commit graph rail: where lanes sit horizontally and
/// where the node sits within a row. Pure values so the painter and the row
/// widgets never disagree.
class RailMetrics {
  final bool compact;

  /// Hard width of the branch-name gutter drawn to the left of the rail (when
  /// the Branch column is enabled). Branch names ellipsize within it.
  final double branchWidth;

  /// Fixed width of the rail column, in px. `0` means auto-size to the widest
  /// visible lane; any positive value is honoured exactly, clipping the graph
  /// when it needs more lanes than fit.
  final double railFixedWidth;

  const RailMetrics({
    this.compact = false,
    this.branchWidth = 116,
    this.railFixedWidth = 0,
  });

  static const double laneWidth = 20;
  static const double pad = 16;

  double get rowHeight => compact ? 34 : 52;
  double get nodeY => rowHeight / 2;

  double laneX(int lane) => pad + lane * laneWidth;

  /// Width of the rail column. Uses [railFixedWidth] when set, otherwise
  /// auto-sizes to fit [maxLane], the highest visible lane, plus padding.
  double railWidth(int maxLane) =>
      railFixedWidth > 0 ? railFixedWidth : pad * 2 + maxLane * laneWidth;

  double nodeRadius({required bool merge}) => merge ? 8 : 7;
  double centerRadius({required bool merge}) => merge ? 3 : 2.5;
}
