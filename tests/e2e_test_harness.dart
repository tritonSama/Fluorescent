// tests/e2e_test_harness.dart
//
// Zero-dependency, self-contained test assertion harness and runner
// for the Fluorite AAA Engine Phase 1 E2E Integration Test Suite.
//
// Supports standalone execution via `dart run tests/e2e_runner.dart`.

import 'dart:async';
import 'dart:io';

/// Signature for synchronous or asynchronous test functions.
typedef TestBody = FutureOr<void> Function();

/// Represents an individual test case.
class TestCase {
  final String name;
  final TestBody body;
  final String groupName;

  bool passed = false;
  String? errorMessage;
  StackTrace? stackTrace;
  int durationMicros = 0;

  TestCase({
    required this.name,
    required this.body,
    required this.groupName,
  });

  Future<bool> run() async {
    final sw = Stopwatch()..start();
    try {
      final res = body();
      if (res is Future) {
        await res;
      }
      sw.stop();
      durationMicros = sw.elapsedMicroseconds;
      passed = true;
      return true;
    } catch (e, st) {
      sw.stop();
      durationMicros = sw.elapsedMicroseconds;
      passed = false;
      errorMessage = e.toString();
      stackTrace = st;
      return false;
    }
  }
}

/// Global registry of test groups and test cases.
class TestHarness {
  static final List<TestCase> _allTests = [];
  static String _currentGroup = 'General';
  static bool _useAnsi = true;

  static void group(String name, void Function() body) {
    final prev = _currentGroup;
    _currentGroup = name;
    try {
      body();
    } finally {
      _currentGroup = prev;
    }
  }

  static void test(String name, TestBody body) {
    _allTests.add(TestCase(
      name: name,
      body: body,
      groupName: _currentGroup,
    ));
  }

  static void reset() {
    _allTests.clear();
    _currentGroup = 'General';
  }

  static Future<TestSummary> runAll({bool silent = false}) async {
    // Check if terminal supports ANSI
    _useAnsi = stdout.hasTerminal && stdout.supportsAnsiEscapes;

    final sw = Stopwatch()..start();
    int passedCount = 0;
    int failedCount = 0;
    final Map<String, List<TestCase>> grouped = {};

    for (final t in _allTests) {
      grouped.putIfAbsent(t.groupName, () => []).add(t);
    }

    if (!silent) {
      _printHeader();
    }

    for (final entry in grouped.entries) {
      if (!silent) {
        _printGroupHeader(entry.key);
      }
      for (final t in entry.value) {
        final ok = await t.run();
        if (ok) {
          passedCount++;
          if (!silent) {
            _printTestPass(t);
          }
        } else {
          failedCount++;
          if (!silent) {
            _printTestFail(t);
          }
        }
      }
    }

    sw.stop();
    final summary = TestSummary(
      total: _allTests.length,
      passed: passedCount,
      failed: failedCount,
      durationMillis: sw.elapsedMilliseconds,
      tests: List.unmodifiable(_allTests),
    );

    if (!silent) {
      _printSummary(summary);
    }

    return summary;
  }

  static void _printHeader() {
    stdout.writeln('================================================================================');
    stdout.writeln('          FLUORITE AAA ENGINE — PHASE 1 E2E INTEGRATION TEST RUNNER');
    stdout.writeln('================================================================================');
  }

  static void _printGroupHeader(String group) {
    stdout.writeln('\n[GROUP] $group');
  }

  static void _printTestPass(TestCase t) {
    final timeStr = '${(t.durationMicros / 1000.0).toStringAsFixed(2)}ms';
    if (_useAnsi) {
      stdout.writeln('  \x1B[32m✔ PASS\x1B[0m  ${t.name} ($timeStr)');
    } else {
      stdout.writeln('  [PASS]  ${t.name} ($timeStr)');
    }
  }

  static void _printTestFail(TestCase t) {
    final timeStr = '${(t.durationMicros / 1000.0).toStringAsFixed(2)}ms';
    if (_useAnsi) {
      stdout.writeln('  \x1B[31m✘ FAIL\x1B[0m  ${t.name} ($timeStr)');
      stdout.writeln('         \x1B[31mError: ${t.errorMessage}\x1B[0m');
    } else {
      stdout.writeln('  [FAIL]  ${t.name} ($timeStr)');
      stdout.writeln('         Error: ${t.errorMessage}');
    }
    if (t.stackTrace != null) {
      final lines = t.stackTrace.toString().split('\n').take(3).join('\n         ');
      stdout.writeln('         $lines');
    }
  }

  static void _printSummary(TestSummary s) {
    stdout.writeln('\n--------------------------------------------------------------------------------');
    stdout.writeln('TEST SUMMARY:');
    stdout.writeln('  Total Tests:    ${s.total}');
    if (_useAnsi) {
      stdout.writeln('  Passed:         \x1B[32m${s.passed}\x1B[0m');
      if (s.failed > 0) {
        stdout.writeln('  Failed:         \x1B[31m${s.failed}\x1B[0m');
      } else {
        stdout.writeln('  Failed:         ${s.failed}');
      }
    } else {
      stdout.writeln('  Passed:         ${s.passed}');
      stdout.writeln('  Failed:         ${s.failed}');
    }
    stdout.writeln('  Execution Time: ${s.durationMillis} ms');
    stdout.writeln('================================================================================');
    if (s.failed == 0) {
      if (_useAnsi) {
        stdout.writeln('\x1B[32mOVERALL RESULT: ALL ${s.total} TESTS PASSED SUCCESSFULLY (100%)\x1B[0m\n');
      } else {
        stdout.writeln('OVERALL RESULT: ALL ${s.total} TESTS PASSED SUCCESSFULLY (100%)\n');
      }
    } else {
      if (_useAnsi) {
        stdout.writeln('\x1B[31mOVERALL RESULT: ${s.failed} TESTS FAILED\x1B[0m\n');
      } else {
        stdout.writeln('OVERALL RESULT: ${s.failed} TESTS FAILED\n');
      }
    }
  }
}

/// Summary metrics of a test execution run.
class TestSummary {
  final int total;
  final int passed;
  final int failed;
  final int durationMillis;
  final List<TestCase> tests;

  TestSummary({
    required this.total,
    required this.passed,
    required this.failed,
    required this.durationMillis,
    required this.tests,
  });

  bool get isSuccess => failed == 0 && total > 0;
}

// -----------------------------------------------------------------------------
// Fluent Assertion Matchers
// -----------------------------------------------------------------------------

void expect(dynamic actual, Matcher matcher, {String? reason}) {
  final matchResult = matcher.matches(actual);
  if (!matchResult) {
    final msg = reason != null ? '$reason: ' : '';
    throw TestFailure('${msg}Expected ${matcher.describe()}, but got: $actual');
  }
}

class TestFailure implements Exception {
  final String message;
  TestFailure(this.message);
  @override
  String toString() => message;
}

abstract class Matcher {
  bool matches(dynamic actual);
  String describe();
}

class _EqualsMatcher extends Matcher {
  final dynamic expected;
  _EqualsMatcher(this.expected);

  @override
  bool matches(dynamic actual) {
    if (expected is List && actual is List) {
      if (expected.length != actual.length) return false;
      for (int i = 0; i < expected.length; i++) {
        if (expected[i] != actual[i]) return false;
      }
      return true;
    }
    return actual == expected;
  }

  @override
  String describe() => 'equal to <$expected>';
}

Matcher equals(dynamic expected) => _EqualsMatcher(expected);

class _IsTrueMatcher extends Matcher {
  @override
  bool matches(dynamic actual) => actual == true;
  @override
  String describe() => 'true';
}

final Matcher isTrue = _IsTrueMatcher();

class _IsFalseMatcher extends Matcher {
  @override
  bool matches(dynamic actual) => actual == false;
  @override
  String describe() => 'false';
}

final Matcher isFalse = _IsFalseMatcher();

class _IsNullMatcher extends Matcher {
  @override
  bool matches(dynamic actual) => actual == null;
  @override
  String describe() => 'null';
}

final Matcher isNull = _IsNullMatcher();

class _IsNotNullMatcher extends Matcher {
  @override
  bool matches(dynamic actual) => actual != null;
  @override
  String describe() => 'not null';
}

final Matcher isNotNull = _IsNotNullMatcher();

class _GreaterThanMatcher extends Matcher {
  final num min;
  _GreaterThanMatcher(this.min);
  @override
  bool matches(dynamic actual) => actual is num && actual > min;
  @override
  String describe() => 'greater than $min';
}

Matcher greaterThan(num min) => _GreaterThanMatcher(min);

class _GreaterThanOrEqualToMatcher extends Matcher {
  final num min;
  _GreaterThanOrEqualToMatcher(this.min);
  @override
  bool matches(dynamic actual) => actual is num && actual >= min;
  @override
  String describe() => 'greater than or equal to $min';
}

Matcher greaterThanOrEqualTo(num min) => _GreaterThanOrEqualToMatcher(min);

class _LessThanMatcher extends Matcher {
  final num max;
  _LessThanMatcher(this.max);
  @override
  bool matches(dynamic actual) => actual is num && actual < max;
  @override
  String describe() => 'less than $max';
}

Matcher lessThan(num max) => _LessThanMatcher(max);

class _LessThanOrEqualToMatcher extends Matcher {
  final num max;
  _LessThanOrEqualToMatcher(this.max);
  @override
  bool matches(dynamic actual) => actual is num && actual <= max;
  @override
  String describe() => 'less than or equal to $max';
}

Matcher lessThanOrEqualTo(num max) => _LessThanOrEqualToMatcher(max);

class _InRangeMatcher extends Matcher {
  final num min;
  final num max;
  _InRangeMatcher(this.min, this.max);
  @override
  bool matches(dynamic actual) => actual is num && actual >= min && actual <= max;
  @override
  String describe() => 'in range [$min, $max]';
}

Matcher inRange(num min, num max) => _InRangeMatcher(min, max);

class _IsZeroMatcher extends Matcher {
  @override
  bool matches(dynamic actual) => actual == 0 || actual == BigInt.zero;
  @override
  String describe() => 'zero';
}

final Matcher isZero = _IsZeroMatcher();

class _ThrowsMatcher extends Matcher {
  @override
  bool matches(dynamic actual) {
    if (actual is Function) {
      try {
        actual();
        return false;
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  @override
  String describe() => 'to throw an exception';
}

Matcher throwsA<T>() => _ThrowsMatcher();
