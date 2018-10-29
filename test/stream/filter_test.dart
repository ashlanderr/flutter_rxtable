import 'package:flutter_rxtable/stream.dart';
import 'package:test/test.dart';

import 'core.dart';

void main() {
  test("must pass even items on init", () {
    final source = TestStream([1, 2, 3, 4]);
    final sink = InitObserver([2, 4]);
    _execute(source, sink, (observer) {});
  });

  test("must pass even item on add", () {
    final source = TestStream<int>();
    final sink = AddObserver(2);
    _execute(source, sink, (observer) => observer.onAdd(2));
  });

  test("must reject odd item on add", () {
    final source = TestStream<int>();
    final sink = EmptyObserver<int>();
    _execute(source, sink, (observer) => observer.onAdd(1));
  });

  test("must pass even item on remove", () {
    final source = TestStream([2]);
    final sink = RemoveObserver(2);
    _execute(source, sink, (observer) => observer.onRemove(2));
  });

  test("must reject odd item on remove", () {
    final source = TestStream([1]);
    final sink = EmptyObserver<int>();
    _execute(source, sink, (observer) => observer.onRemove(1));
  });

  test("must add item on change from odd to even", () {
    final source = TestStream([1]);
    final sink = AddObserver(2);
    _execute(source, sink, (observer) => observer.onChange(1, 2));
  });

  test("must remove item on change from even to odd", () {
    final source = TestStream([2]);
    final sink = RemoveObserver(2);
    _execute(source, sink, (observer) => observer.onChange(2, 1));
  });

  test("must do nothing on change from odd to odd", () {
    final source = TestStream([1]);
    final sink = EmptyObserver<int>();
    _execute(source, sink, (observer) => observer.onChange(1, 3));
  });

  test("must change item on change from even to even", () {
    final source = TestStream([2]);
    final sink = ChangeObserver(2, 4);
    _execute(source, sink, (observer) => observer.onChange(2, 4));
  });
}

void _execute(TestStream<int> source, TestObserver<int> sink, void block(StreamObserver<int> observer)) {
  source
    .filter((i) => i % 2 == 0)
    .subscribe(sink);
  block(source.observer);
  sink.test();
}