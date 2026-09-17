// tests/e2e_runner.dart
//
// Master E2E Test Runner for the Fluorite AAA Engine Phase 1.
// Executes all 4 tiers of the systematic testing methodology:
// - Tier 1: Feature Coverage (20 tests)
// - Tier 2: Boundary & Corner Cases (21 tests)
// - Tier 3: Cross-Feature Combinations (5 tests)
// - Tier 4: Real-World Application Scenarios (5 scenarios)
// Total: 51 tests.
//
// Can be executed with: `dart run tests/e2e_runner.dart`

import 'dart:io';
import 'e2e_test_harness.dart';
import 'tier1_feature_coverage_test.dart';
import 'tier2_boundary_corner_test.dart';
import 'tier3_cross_feature_test.dart';
import 'tier4_real_world_scenarios_test.dart';

void main() async {
  TestHarness.reset();

  // Register all 4 tiers
  registerTier1Tests();
  registerTier2Tests();
  registerTier3Tests();
  registerTier4Tests();

  // Run all tests
  final summary = await TestHarness.runAll();

  // Exit code: 0 if all tests passed, 1 otherwise
  if (!summary.isSuccess) {
    exit(1);
  }
}
