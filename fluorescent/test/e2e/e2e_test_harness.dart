import 'dart:async';
import 'dart:io';

/// Represents a single test case.
class TestCase {
  final String groupName;
  final String testName;
  final FutureOr<void> Function() body;
  final Duration? timeout;

  TestCase({
    required this.groupName,
    required this.testName,
    required this.body,
    this.timeout,
  });

  String get fullName => groupName.isEmpty ? testName : '$groupName > $testName';
}

/// Result of executing a [TestCase].
class TestResult {
  final TestCase testCase;
  final bool passed;
  final Duration duration;
  final Object? error;
  final StackTrace? stackTrace;

  TestResult({
    required this.testCase,
    required this.passed,
    required this.duration,
    this.error,
    this.stackTrace,
  });
}

/// Aggregate summary of a test run.
class TestSummary {
  final String suiteName;
  final List<TestResult> results;
  final Duration totalDuration;

  TestSummary({
    required this.suiteName,
    required this.results,
    required this.totalDuration,
  });

  int get total => results.length;
  int get passed => results.where((r) => r.passed).length;
  int get failed => results.where((r) => !r.passed).length;
  bool get allPassed => failed == 0 && total > 0;
}

/// Exception thrown when an assertion fails.
class TestAssertionError implements Exception {
  final String message;
  final dynamic actual;
  final dynamic expected;

  TestAssertionError({
    required this.message,
    this.actual,
    this.expected,
  });

  @override
  String toString() {
    final buffer = StringBuffer('TestAssertionError: $message');
    if (expected != null || actual != null) {
      buffer.write('\n  Expected: $expected\n  Actual:   $actual');
    }
    return buffer.toString();
  }
}

/// Global context holding active tests during definition.
class TestContext {
  static final TestContext instance = TestContext();

  String currentGroup = '';
  final List<TestCase> registered = [];
  final List<FutureOr<void> Function()> setUps = [];
  final List<FutureOr<void> Function()> tearDowns = [];

  void reset() {
    currentGroup = '';
    registered.clear();
    setUps.clear();
    tearDowns.clear();
  }
}

/// Defines a test group.
void group(String name, void Function() body) {
  final prevGroup = TestContext.instance.currentGroup;
  TestContext.instance.currentGroup =
      prevGroup.isEmpty ? name : '$prevGroup > $name';
  try {
    body();
  } finally {
    TestContext.instance.currentGroup = prevGroup;
  }
}

/// Defines a test case.
void test(String name, FutureOr<void> Function() body, {Duration? timeout}) {
  TestContext.instance.registered.add(
    TestCase(
      groupName: TestContext.instance.currentGroup,
      testName: name,
      body: body,
      timeout: timeout,
    ),
  );
}

/// Registers a setUp hook.
void setUp(FutureOr<void> Function() callback) {
  TestContext.instance.setUps.add(callback);
}

/// Registers a tearDown hook.
void tearDown(FutureOr<void> Function() callback) {
  TestContext.instance.tearDowns.add(callback);
}

// =============================================================================
// Matchers & Assertions
// =============================================================================

typedef Matcher = void Function(dynamic actual, String? reason);

void expect(dynamic actual, dynamic matcher, {String? reason}) {
  if (matcher is Matcher) {
    matcher(actual, reason);
  } else if (matcher is bool) {
    if (actual != matcher) {
      throw TestAssertionError(
        message: reason ?? 'Expected boolean $matcher, but got $actual',
        actual: actual,
        expected: matcher,
      );
    }
  } else {
    // Default to equality
    equals(matcher)(actual, reason);
  }
}

Matcher equals(dynamic expected) => (actual, reason) {
      if (expected is Iterable && actual is Iterable) {
        final expList = expected.toList();
        final actList = actual.toList();
        if (expList.length != actList.length) {
          throw TestAssertionError(
            message: reason ?? 'Iterable lengths differ: ${expList.length} vs ${actList.length}',
            actual: actual,
            expected: expected,
          );
        }
        for (int i = 0; i < expList.length; i++) {
          if (expList[i] != actList[i]) {
            throw TestAssertionError(
              message: reason ?? 'Element at index $i differs',
              actual: actList[i],
              expected: expList[i],
            );
          }
        }
        return;
      }
      if (actual != expected) {
        throw TestAssertionError(
          message: reason ?? 'Equality check failed',
          actual: actual,
          expected: expected,
        );
      }
    };

Matcher isTrue = (actual, reason) {
  if (actual != true) {
    throw TestAssertionError(
      message: reason ?? 'Expected true, but got $actual',
      actual: actual,
      expected: true,
    );
  }
};

Matcher isFalse = (actual, reason) {
  if (actual != false) {
    throw TestAssertionError(
      message: reason ?? 'Expected false, but got $actual',
      actual: actual,
      expected: false,
    );
  }
};

Matcher isNull = (actual, reason) {
  if (actual != null) {
    throw TestAssertionError(
      message: reason ?? 'Expected null, but got $actual',
      actual: actual,
      expected: null,
    );
  }
};

Matcher isNotNull = (actual, reason) {
  if (actual == null) {
    throw TestAssertionError(
      message: reason ?? 'Expected not null, but got null',
      actual: null,
      expected: 'non-null object',
    );
  }
};

Matcher lessThan(num value) => (actual, reason) {
      if (actual is! num || actual >= value) {
        throw TestAssertionError(
          message: reason ?? 'Expected value less than $value, but got $actual',
          actual: actual,
          expected: '< $value',
        );
      }
    };

Matcher lessThanOrEqualTo(num value) => (actual, reason) {
      if (actual is! num || actual > value) {
        throw TestAssertionError(
          message: reason ?? 'Expected value <= $value, but got $actual',
          actual: actual,
          expected: '<= $value',
        );
      }
    };

Matcher greaterThan(num value) => (actual, reason) {
      if (actual is! num || actual <= value) {
        throw TestAssertionError(
          message: reason ?? 'Expected value greater than $value, but got $actual',
          actual: actual,
          expected: '> $value',
        );
      }
    };

Matcher greaterThanOrEqualTo(num value) => (actual, reason) {
      if (actual is! num || actual < value) {
        throw TestAssertionError(
          message: reason ?? 'Expected value >= $value, but got $actual',
          actual: actual,
          expected: '>= $value',
        );
      }
    };

Matcher closeTo(num value, num delta) => (actual, reason) {
      if (actual is! num || (actual - value).abs() > delta) {
        throw TestAssertionError(
          message: reason ?? 'Expected value within $delta of $value, but got $actual',
          actual: actual,
          expected: '$value (+/- $delta)',
        );
      }
    };

Matcher contains(dynamic element) => (actual, reason) {
      if (actual is String) {
        if (!actual.contains(element.toString())) {
          throw TestAssertionError(
            message: reason ?? 'Expected string to contain "$element"',
            actual: actual,
            expected: 'containing "$element"',
          );
        }
      } else if (actual is Iterable) {
        if (!actual.contains(element)) {
          throw TestAssertionError(
            message: reason ?? 'Expected iterable to contain element',
            actual: actual,
            expected: 'containing $element',
          );
        }
      } else if (actual is Map) {
        if (!actual.containsKey(element)) {
          throw TestAssertionError(
            message: reason ?? 'Expected map to contain key $element',
            actual: actual,
            expected: 'containing key $element',
          );
        }
      } else {
        throw TestAssertionError(
          message: 'Unsupported container type for contains: ${actual.runtimeType}',
        );
      }
    };

Matcher hasLength(int length) => (actual, reason) {
      final actLen = (actual as dynamic).length as int;
      if (actLen != length) {
        throw TestAssertionError(
          message: reason ?? 'Expected length $length, but got $actLen',
          actual: actLen,
          expected: length,
        );
      }
    };

Matcher throwsA<T extends Object>() => (actual, reason) {
      // actual must be a Function
      if (actual is! Function) {
        throw TestAssertionError(
          message: 'Expected callable function for throwsA, got ${actual.runtimeType}',
        );
      }
      try {
        final res = actual();
        if (res is Future) {
          throw TestAssertionError(
            message: 'throwsA received async future. Use expectLater or await in test.',
          );
        }
        throw TestAssertionError(
          message: reason ?? 'Expected exception of type $T, but no exception was thrown.',
          expected: T,
          actual: 'No exception thrown',
        );
      } catch (e) {
        if (e is TestAssertionError) rethrow;
        if (e is! T) {
          throw TestAssertionError(
            message: reason ?? 'Thrown exception $e was not of expected type $T',
            actual: e.runtimeType,
            expected: T,
          );
        }
      }
    };

Matcher throwsStateError = throwsA<StateError>();
Matcher throwsArgumentError = throwsA<ArgumentError>();

// =============================================================================
// Test Suite Runner
// =============================================================================

/// Executes registered tests for a suite and prints structured output.
Future<TestSummary> runSuite(String suiteName, void Function() suiteDefinition) async {
  final context = TestContext.instance;
  context.reset();

  // Populate tests
  suiteDefinition();
  final testsToRun = List<TestCase>.from(context.registered);
  final suiteSetUps = List<FutureOr<void> Function()>.from(context.setUps);
  final suiteTearDowns = List<FutureOr<void> Function()>.from(context.tearDowns);

  stdout.writeln('======================================================================');
  stdout.writeln(' RUNNING TEST SUITE: $suiteName');
  stdout.writeln(' Total tests registered: ${testsToRun.length}');
  stdout.writeln('======================================================================');

  final results = <TestResult>[];
  final suiteStopwatch = Stopwatch()..start();

  for (int i = 0; i < testsToRun.length; i++) {
    final tc = testsToRun[i];
    final testStopwatch = Stopwatch()..start();
    bool passed = false;
    Object? error;
    StackTrace? stackTrace;

    try {
      for (final su in suiteSetUps) {
        await su();
      }

      if (tc.timeout != null) {
        await Future.value(tc.body()).timeout(tc.timeout!);
      } else {
        await tc.body();
      }
      passed = true;
    } catch (e, st) {
      passed = false;
      error = e;
      stackTrace = st;
    } finally {
      for (final td in suiteTearDowns) {
        try {
          await td();
        } catch (_) {}
      }
      testStopwatch.stop();
    }

    final result = TestResult(
      testCase: tc,
      passed: passed,
      duration: testStopwatch.elapsed,
      error: error,
      stackTrace: stackTrace,
    );
    results.add(result);

    final statusTag = passed ? '[PASS]' : '[FAIL]';
    final ms = testStopwatch.elapsedMilliseconds;
    stdout.writeln('  $statusTag  (${ms.toString().padLeft(4)} ms)  ${tc.fullName}');

    if (!passed) {
      stderr.writeln('         --> ERROR: $error');
      if (stackTrace != null) {
        final frames = stackTrace.toString().split('\n').take(8).join('\n         ');
        stderr.writeln('         $frames');
      }
    }
  }

  suiteStopwatch.stop();
  final summary = TestSummary(
    suiteName: suiteName,
    results: results,
    totalDuration: suiteStopwatch.elapsed,
  );

  stdout.writeln('----------------------------------------------------------------------');
  stdout.writeln(
    ' Suite: $suiteName | Result: ${summary.allPassed ? "ALL PASSED" : "FAILURES DETECTED"} | '
    'Passed: ${summary.passed}/${summary.total} | Elapsed: ${summary.totalDuration.inMilliseconds} ms',
  );
  stdout.writeln('======================================================================\n');

  return summary;
}
