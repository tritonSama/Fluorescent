import 'dart:io';
import 'ac1_server_isolate_e2e_test.dart' as ac1;
import 'ac2_asset_pipeline_e2e_test.dart' as ac2;
import 'ac3_ecs_benchmark_e2e_test.dart' as ac3;
import 'ac4_resource_manager_e2e_test.dart' as ac4;
import 'e2e_test_harness.dart';
import 'pillar2_render_graph_e2e_test.dart' as p2;
import 'pillar6_shader_toolchain_e2e_test.dart' as p6;

Future<void> main(List<String> args) async {
  stdout.writeln('######################################################################');
  stdout.writeln('#                                                                    #');
  stdout.writeln('#          FLUORESCENT 3D ENGINE — UNIFIED E2E TEST RUNNER           #');
  stdout.writeln('#                                                                    #');
  stdout.writeln('#  Covering 4 Acceptance Criteria & 6 Core Architectural Pillars:     #');
  stdout.writeln('#    [AC 1 / Pillar 1] Server Architecture & Non-Blocking Isolates   #');
  stdout.writeln('#    [AC 2 / Pillar 3] Asset Pipeline CLI & .fworld Packaging        #');
  stdout.writeln('#    [AC 3 / Pillar 5] Contiguous TypedData ECS 10,000 Benchmark     #');
  stdout.writeln('#    [AC 4 / Pillar 4] Resource Manager RefCount & GPU VRAM          #');
  stdout.writeln('#    [Pillar 2]        Data-Driven RenderGraph DAG Resolution        #');
  stdout.writeln('#    [Pillar 6]        Multi-Target Shader Toolchain (SPIR-V / MSL)  #');
  stdout.writeln('#                                                                    #');
  stdout.writeln('######################################################################\n');

  final overallStopwatch = Stopwatch()..start();
  final summaries = <TestSummary>[];

  // 1. AC 1 & Pillar 1: Server Architecture & Isolates
  summaries.add(await runSuite(
    'AC 1 & Pillar 1: Server Architecture & Dart Isolates',
    ac1.defineTests,
  ));

  // 2. AC 2 & Pillar 3: Asset Pipeline CLI Tooling & .fworld Packaging
  summaries.add(await runSuite(
    'AC 2 & Pillar 3: Asset Pipeline CLI Tooling & .fworld Packaging',
    ac2.defineTests,
  ));

  // 3. AC 3 & Pillar 5: Contiguous TypedData ECS 10,000 Entity Benchmark
  summaries.add(await runSuite(
    'AC 3 & Pillar 5: Contiguous TypedData ECS & 10k Benchmark',
    ac3.defineTests,
  ));

  // 4. AC 4 & Pillar 4: Resource Manager Ref Counting & GPU Memory
  summaries.add(await runSuite(
    'AC 4 & Pillar 4: Resource Manager Ref Counting & GPU Memory',
    ac4.defineTests,
  ));

  // 5. Pillar 2: Data-Driven RenderGraph & DAG Resolution
  summaries.add(await runSuite(
    'Pillar 2: Data-Driven RenderGraph & DAG Execution Order',
    p2.defineTests,
  ));

  // 6. Pillar 6: Multi-Target Shader Toolchain
  summaries.add(await runSuite(
    'Pillar 6: Shader Toolchain (WGSL -> SPIR-V & MSL)',
    p6.defineTests,
  ));

  overallStopwatch.stop();

  // Aggregate Metrics
  final totalTests = summaries.fold<int>(0, (sum, s) => sum + s.total);
  final totalPassed = summaries.fold<int>(0, (sum, s) => sum + s.passed);
  final totalFailed = summaries.fold<int>(0, (sum, s) => sum + s.failed);
  final allPassed = totalFailed == 0 && totalTests > 0;

  stdout.writeln('\n======================================================================');
  stdout.writeln('                      E2E EXECUTION SUMMARY REPORT                   ');
  stdout.writeln('======================================================================');
  stdout.writeln(' Suite Name                                        | Result | Tests | Time  ');
  stdout.writeln('---------------------------------------------------+--------+-------+-------');

  for (final s in summaries) {
    final nameCol = s.suiteName.length > 50
        ? s.suiteName.substring(0, 47) + '...'
        : s.suiteName.padRight(50);
    final resultCol = s.allPassed ? ' PASS ' : '!FAIL!';
    final testsCol = '${s.passed}/${s.total}'.padLeft(5);
    final timeCol = '${s.totalDuration.inMilliseconds}ms'.padLeft(6);
    stdout.writeln(' $nameCol | $resultCol | $testsCol | $timeCol');
  }

  stdout.writeln('---------------------------------------------------+--------+-------+-------');
  stdout.writeln(
    ' TOTAL                                             | '
    '${allPassed ? "PASS " : "FAIL!"}  | '
    '${totalPassed.toString().padLeft(2)}/$totalTests | '
    '${overallStopwatch.elapsedMilliseconds}ms',
  );
  stdout.writeln('======================================================================\n');

  if (allPassed) {
    stdout.writeln('>>> SUCCESS: ALL 6 E2E TEST SUITES PASSED (100% VERIFIED) <<<\n');
    exitCode = 0;
  } else {
    stderr.writeln('>>> FAILURE: $totalFailed TEST(S) FAILED ACROSS SUITES <<<\n');
    exitCode = 1;
  }
}
