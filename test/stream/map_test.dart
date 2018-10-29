import 'package:flutter_rxtable/stream.dart';
import "package:test/test.dart";

import 'core.dart';

void main() {
  test("must transform items on init", () {
    final source = TestStream([1, 2, 3]);
    final sink = InitObserver([2, 4, 6]);
    _execute(source, sink, (observer) {});
  });

  test("must transform item on add", () {
    final source = TestStream<int>();
    final sink = AddObserver(2);
    _execute(source, sink, (observer) => observer.onAdd(1));
  });

  test("must transform item on remove", () {
    final source = TestStream([2]);
    final sink = RemoveObserver(2);
    _execute(source, sink, (observer) => observer.onRemove(1));
  });

  test("must transform item on change", () {
    final source = TestStream([2]);
    final sink = ChangeObserver(2, 4);
    _execute(source, sink, (observer) => observer.onChange(1, 2));
  });

  test("must not transform item if it is not changed", () {
    final source = TestStream([2]);
    final sink = EmptyObserver<int>();
    _execute(source, sink, (observer) => observer.onChange(2, 2));
  });
}

void _execute(TestStream<int> source, TestObserver<int> sink, void block(StreamObserver<int> observer)) {
  source
    .map((i) => i * 2)
    .subscribe(sink);
  block(source.observer);
  sink.test();
}