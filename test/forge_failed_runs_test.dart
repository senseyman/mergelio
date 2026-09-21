import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';

CheckRun _run(String name, CheckState state) =>
    CheckRun(name: name, state: state);

void main() {
  test('a summary with no runs has nothing to expand', () {
    const summary = ChecksSummary(overall: ChecksOverall.mixed, runs: []);
    expect(forgeFailedRuns(summary), isEmpty);
  });

  test('keeps failures and drops everything green or pending', () {
    final summary = ChecksSummary(
      overall: ChecksOverall.mixed,
      runs: [
        _run('build', CheckState.success),
        _run('test', CheckState.failure),
        _run('lint', CheckState.running),
        _run('e2e', CheckState.failure),
      ],
    );
    expect(forgeFailedRuns(summary).map((r) => r.name), ['test', 'e2e']);
  });

  test('a ref with no CI read at all has nothing to expand', () {
    expect(forgeFailedRuns(null), isEmpty);
  });
}
