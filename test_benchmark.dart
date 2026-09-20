import 'package:flutter/widgets.dart';

void main() {
  var size = const Size(800, 600);
  var painterWidth = 100.0;
  var painterHeight = 20.0;

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < 10000000; i++) {
    var offset = Offset(size.width / 2 - painterWidth / 2, size.height / 2 - painterHeight / 2);
  }
  stopwatch.stop();
  print('Offset Allocation Time: ${stopwatch.elapsedMilliseconds} ms');
}
