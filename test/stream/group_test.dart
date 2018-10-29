import 'package:collection/collection.dart';
import 'package:flutter_rxtable/stream.dart';
import 'package:test/test.dart';

import 'core.dart';

final equality = GroupEquality(DefaultEquality<bool>(), DefaultEquality<int>());

void main() {
  test("must pass items on init", () {
    final source = TestStream([1, 2, 3, 4]);
    final sink = InitObserver([
      MapEntry(false, [1, 3]),
      MapEntry(true, [2, 4])
    ], equality);
    _execute(source, sink, (observer) {});
  });

  test("must create group on add", () {
    final source = TestStream<int>();
    final sink = AddObserver(MapEntry(false, [1]), equality);
    _execute(source, sink, (observer) {
      observer.onAdd(1);
    });
  });

  test("must change group on item change", () {
    final source = TestStream<int>([1]);
    final sink = ComplexObserver(equality)
      .init([MapEntry(false, [1])])
      .remove(MapEntry(false, [1]))
      .add(MapEntry(true, [2]));
    _execute(source, sink, (observer) {
      observer.onChange(1, 2);
    });
  });

  test("must remove group on last item remove", () {
    final source = TestStream<int>([1, 3]);
    final sink = ComplexObserver(equality)
      .init([MapEntry(false, [1, 3])])
      .change(MapEntry(false, [1, 3]), MapEntry(false, [1]))
      .remove(MapEntry(false, [1]));
    _execute(source, sink, (observer) {
      observer.onRemove(3);
      observer.onRemove(1);
    });
  });

  test("must change group on item add", () {
    final source = TestStream<int>([1]);
    final sink = ComplexObserver(equality)
      .init([MapEntry(false, [1])])
      .change(MapEntry(false, [1]), MapEntry(false, [1, 3]));
    _execute(source, sink, (observer) {
      observer.onAdd(3);
    });
  });
}

void _execute(
  TestStream<int> source,
  TestObserver<MapEntry<bool, List<int>>> sink,
  void block(StreamObserver<int> observer)
) {
  source
    .group((i) => i % 2 == 0)
    .subscribe(sink);
  block(source.observer);
  sink.test();
}