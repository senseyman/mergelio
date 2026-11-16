import 'package:mergelio/data/app_database.dart';
import 'package:mergelio/state/recents.dart';

/// A [RecentsRepository] that starts empty and stores nothing, so a test can
/// build a [RecentsController] without a database.
class MemoryRecents implements RecentsRepository {
  @override
  AppDatabase get db => throw UnimplementedError();

  @override
  Future<List<RecentRepo>> load() async => const [];

  @override
  Future<void> save(List<RecentRepo> items) async {}
}
