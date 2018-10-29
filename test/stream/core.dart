import 'package:collection/collection.dart';
import 'package:flutter_rxtable/core.dart';
import 'package:flutter_rxtable/db.dart';
import 'package:flutter_rxtable/stream.dart';
import 'package:test/test.dart';

void expectEquals<T>(T expected, T actual, Equality<T> equality) {
  if (equality == null)
    expect(expected, equals(actual));
  else
    expect(equality.equals(expected, actual), equals(true));
}

class EmptyHandle implements RxHandle {
  @override
  void close() {}
}

class TestStream<T> extends RxStream<T> {
  StreamObserver<T> observer;
  final List<T> items;

  @override
  final RxContext context;

  TestStream([
    this.items = const [],
    this.context = const NullRxContext(),
    Equality<T> equality = const DefaultEquality()
  ]) : super(equality);

  @override
  RxHandle subscribe(StreamObserver<T> observer) {
    this.observer = observer;
    observer.onInit(items);
    return EmptyHandle();
  }
}

abstract class TestObserver<T> implements StreamObserver<T> {
  var _completed = false;

  @override
  void onInit(Iterable<T> items) {}

  @override
  void onChange(T oldItem, T newItem) {
    expect(true, equals(false));
  }

  @override
  void onRemove(T oldItem) {
    expect(true, equals(false));
  }

  @override
  void onAdd(T newItem) {
    expect(true, equals(false));
  }

  void completed() {
    expect(_completed, equals(false));
    _completed = true;
  }

  void test() {
    expect(_completed, equals(true));
  }
}

class InitObserver<T> extends TestObserver<T> {
  final List<T> data;
  final ListEquality<T> equality;

  InitObserver(this.data, [Equality<T> equality])
    : equality = equality != null ? ListEquality(equality) : null;

  @override
  void onInit(Iterable<T> items) {
    expectEquals(data, items.toList(), equality);
    completed();
  }
}

class AddObserver<T> extends TestObserver<T> {
  final T newItem;
  final Equality<T> equality;

  AddObserver(this.newItem, [this.equality]);

  @override
  void onAdd(T newItem) {
    expectEquals(this.newItem, newItem, equality);
    completed();
  }
}

class RemoveObserver<T> extends TestObserver<T> {
  final T oldItem;
  final Equality<T> equality;

  RemoveObserver(this.oldItem, [this.equality]);

  @override
  void onRemove(T oldItem) {
    expectEquals(this.oldItem, oldItem, equality);
    completed();
  }
}

class ChangeObserver<T> extends TestObserver<T> {
  final T oldItem;
  final T newItem;
  final Equality<T> equality;

  ChangeObserver(this.oldItem, this.newItem, [this.equality]);

  @override
  void onChange(T oldItem, T newItem) {
    expectEquals(this.oldItem, oldItem, equality);
    expectEquals(this.newItem, newItem, equality);
    completed();
  }
}

class EmptyObserver<T> extends TestObserver<T> {
  @override
  void onInit(Iterable<T> items) {
    completed();
  }
}

class ComplexObserver<T> extends TestObserver<T> {
  final _actions = <TestObserver<T>>[];
  final Equality<T> equality;

  ComplexObserver([this.equality]);

  ComplexObserver<T> init(List<T> data) {
    _actions.add(InitObserver(data, equality));
    return this;
  }

  ComplexObserver<T> add(T newItem) {
    _actions.add(AddObserver(newItem, equality));
    return this;
  }

  ComplexObserver<T> remove(T oldItem) {
    _actions.add(RemoveObserver(oldItem, equality));
    return this;
  }

  ComplexObserver<T> change(T oldItem, T newItem) {
    _actions.add(ChangeObserver(oldItem, newItem, equality));
    return this;
  }

  @override
  void onInit(Iterable<T> items) {
    final action = _actions.removeAt(0);
    action.onInit(items);
    action.test();
  }

  @override
  void onChange(T oldItem, T newItem) {
    final action = _actions.removeAt(0);
    action.onChange(oldItem, newItem);
    action.test();
  }

  @override
  void onRemove(T oldItem) {
    final action = _actions.removeAt(0);
    action.onRemove(oldItem);
    action.test();
  }

  @override
  void onAdd(T newItem) {
    final action = _actions.removeAt(0);
    action.onAdd(newItem);
    action.test();
  }

  @override
  void test() {
    if (_actions.isEmpty) completed();
    super.test();
  }
}