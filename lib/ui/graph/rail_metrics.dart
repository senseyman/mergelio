/// Fixed geometry of the commit graph rail: where lanes sit horizontally and
/// where the node sits within a row. Pure values so the painter and the row
/// widgets never disagree.
class RailMetrics {
  final bool compact;
  const RailMetrics({this.compact = false});

  static const double laneWidth = 20;
  static const double pad = 16;

  double get rowHeight => compact ? 34 : 52;
  double get nodeY => rowHeight / 2;

  double laneX(int lane) => pad + lane * laneWidth;

  /// Width of the rail column when [maxLane] is the highest visible lane.
  double railWidth(int maxLane) => pad * 2 + maxLane * laneWidth;

  double nodeRadius({required bool merge}) => merge ? 8 : 7;
  double centerRadius({required bool merge}) => merge ? 3 : 2.5;
}
