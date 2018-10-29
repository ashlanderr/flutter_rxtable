import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:flutter_rxtable/core.dart';
import 'package:flutter_rxtable/db.dart';

abstract class StreamObserver<T> {
  void onInit(Iterable<T> items);
  void onAdd(T newItem);
  void onRemove(T oldItem);
  void onChange(T oldItem, T newItem);
}

class GroupEquality<K, V> implements Equality<MapEntry<K, List<V>>> {
  final Equality<K> keyEquality;
  final ListEquality<V> valuesEquality;

  GroupEquality(this.keyEquality, Equality<V> valueEquality)
    : valuesEquality = ListEquality(valueEquality);

  @override
  bool equals(MapEntry e1, MapEntry e2) {
    if (e1 == e2) return true;
    if (e1 == null || e2 == null) return false;
    return keyEquality.equals(e1.key, e2.key) && valuesEquality.equals(e1.value, e2.value);
  }

  @override
  bool isValidKey(Object o) {
    return true;
  }

  @override
  int hash(MapEntry e) {
    return keyEquality.hash(e.key) ^ valuesEquality.hash(e.value);
  }
}

abstract class RxStream<T> {
  RxContext get context;
  Equality<T> equality;

  RxStream(this.equality);

  RxHandle subscribe(StreamObserver<T> observer);

  RxStream<U> map<U>(Mapper<T, U> mapper, [Equality<U> equality = const DefaultEquality()]) {
    return MapStream(this, mapper, equality);
  }

  RxStream<T> filter(Mapper<T, bool> predicate) {
    return FilterStream(this, predicate);
  }

  RxStream<MapEntry<K, List<T>>> group<K>(
    Mapper<T, K> keyMapper, [Equality<K> keyEquality = const DefaultEquality()])
  {
    return GroupStream(this, keyMapper, keyEquality);
  }

  bool get isEmpty => sink((data) => data.isEmpty);

  bool get isNotEmpty => !isEmpty;

  int get count => sink((data) => data.length);

  List<T> toList() {
    final sink = ToListSink<T>(context);
    context.add(subscribe(sink));
    return sink.result;
  }

  Set<T> toSet() {
    final sink = ToSetSink<T>(context);
    context.add(subscribe(sink));
    return sink.result;
  }

  Map<K, V> toMap<K, V>(Mapper<T, MapEntry<K, V>> mapper) {
    final sink = ToMapSink<K, V, T>(mapper, context);
    context.add(subscribe(sink));
    return sink.result;
  }

  RxMaterializedView<ID, T> materialize<ID>(RxDatabase db, Mapper<T, ID> mapper) {
    final view = RxMaterializedView(db, mapper, equality);
    subscribe(view);
    return view;
  }

  U sink<U>(Mapper<Iterable<T>, U> fn) {
    final sink = FnSink<T, U>(context, fn, equality);
    context.add(subscribe(sink));
    return sink.result;
  }
}

class MapObserver<T, U> implements StreamObserver<T> {
  final Mapper<T, U> mapper;
  final StreamObserver<U> sink;
  final Equality<U> equality;

  MapObserver(this.mapper, this.sink, this.equality);

  @override
  void onInit(Iterable<T> items) {
    sink.onInit(items.map(mapper));
  }

  @override
  void onChange(T oldItem, T newItem) {
    final oldResult = mapper(oldItem);
    final newResult = mapper(newItem);
    if (!equality.equals(oldResult, newResult))
      sink.onChange(oldResult, newResult);
  }

  @override
  void onRemove(T oldItem) {
    final oldResult = mapper(oldItem);
    sink.onRemove(oldResult);
  }

  @override
  void onAdd(T newItem) {
    final newResult = mapper(newItem);
    sink.onAdd(newResult);
  }
}

class MapStream<T, U> extends RxStream<U> {
  final Mapper<T, U> mapper;
  final RxStream<T> source;
  RxContext get context => source.context;

  MapStream(this.source, this.mapper, Equality<U> equality) : super(equality);

  @override
  RxHandle subscribe(StreamObserver<U> observer) {
    final transform = MapObserver(mapper, observer, equality);
    return source.subscribe(transform);
  }
}

class FilterObserver<T> implements StreamObserver<T> {
  final Mapper<T, bool> predicate;
  final StreamObserver<T> sink;

  FilterObserver(this.predicate, this.sink);

  @override
  void onInit(Iterable<T> items) {
    sink.onInit(items.where(predicate));
  }

  @override
  void onChange(T oldItem, T newItem) {
    bool oldTest = predicate(oldItem);
    bool newTest = predicate(newItem);
    if (oldTest && !newTest) {
      sink.onRemove(oldItem);
    } else if (!oldTest && newTest) {
      sink.onAdd(newItem);
    } else if (oldTest && newTest) {
      sink.onChange(oldItem, newItem);
    }
  }

  @override
  void onRemove(T oldItem) {
    if (predicate(oldItem))
      sink.onRemove(oldItem);
  }

  @override
  void onAdd(T newItem) {
    if (predicate(newItem))
      sink.onAdd(newItem);
  }
}

class FilterStream<T> extends RxStream<T> {
  final Mapper<T, bool> predicate;
  final RxStream<T> source;
  RxContext get context => source.context;

  FilterStream(this.source, this.predicate) : super(source.equality);

  @override
  RxHandle subscribe(StreamObserver<T> observer) {
    final transform = FilterObserver(predicate, observer);
    return source.subscribe(transform);
  }
}

class GroupObserver<K, V> implements StreamObserver<V> {
  final Mapper<V, K> keyMapper;
  final Equality<K> keyEquality;
  final Equality<V> valueEquality;
  final ListEquality<V> valuesEquality;
  final StreamObserver<MapEntry<K, List<V>>> sink;
  HashMap<K, List<V>> _data;

  GroupObserver(this.keyMapper, this.sink, this.keyEquality, this.valueEquality)
    : valuesEquality = ListEquality(valueEquality)
  {
    _data = HashMap<K, List<V>>(
      equals: keyEquality.equals,
      hashCode: keyEquality.hash,
    );
  }

  @override
  void onInit(Iterable<V> items) {
    for (final item in items) {
      final k = keyMapper(item);
      final v = _data.putIfAbsent(k, () => <V>[]);
      v.add(item);
    }
    final result = _data.entries
      .map((e) => MapEntry(e.key, e.value));
    sink.onInit(result);
  }

  @override
  void onChange(V oldItem, V newItem) {
    final oldK = keyMapper(oldItem);
    final newK = keyMapper(newItem);

    if (keyEquality.equals(oldK, newK)) {
      final oldV = _data[oldK];
      final newV = oldV
        .where((v) => !valueEquality.equals(v, oldItem))
        .toList();
      _data[newK] = newV;

      newV.add(newItem);
      sink.onChange(
        MapEntry(oldK, oldV),
        MapEntry(newK, newV),
      );
    } else {

      onRemove(oldItem);
      onAdd(newItem);
    }
  }

  @override
  void onRemove(V oldItem) {
    final k = keyMapper(oldItem);
    final oldV = _data[k];
    final newV = oldV
      .where((v) => !valueEquality.equals(v, oldItem))
      .toList();

    if (newV.isNotEmpty) {
      _data[k] = newV;
      sink.onChange(
        MapEntry(k, oldV),
        MapEntry(k, newV),
      );
    } else {
      _data.remove(k);
      sink.onRemove(MapEntry(k, oldV));
    }
  }

  @override
  void onAdd(V newItem) {
    final k = keyMapper(newItem);
    final oldV = _data[k];
    final newV = oldV?.toList() ?? [];
    newV.add(newItem);

    if (oldV != null) {
      _data[k] = newV;
      sink.onChange(
        MapEntry(k, oldV),
        MapEntry(k, newV),
      );
    } else {
      _data[k] = newV;
      sink.onAdd(MapEntry(k, newV));
    }
  }
}

class GroupStream<K, V> extends RxStream<MapEntry<K, List<V>>> {
  final Mapper<V, K> keyMapper;
  final Equality<K> keyEquality;
  final RxStream<V> source;
  RxContext get context => source.context;

  GroupStream(this.source, this.keyMapper, this.keyEquality) : super(
    GroupEquality(keyEquality, source.equality)
  );

  @override
  RxHandle subscribe(StreamObserver<MapEntry<K, List<V>>> observer) {
    final transform = GroupObserver(keyMapper, observer, keyEquality, source.equality);
    return source.subscribe(transform);
  }
}

abstract class NotifySink<T> implements StreamObserver<T> {
  final RxContext context;

  NotifySink(this.context);

  @override
  void onAdd(T newItem) {
    context.notify();
  }

  @override
  void onRemove(T oldItem) {
    context.notify();
  }

  @override
  void onChange(T oldItem, T newItem) {
    context.notify();
  }
}

class FnSink<T, U> implements StreamObserver<T> {
  final Mapper<Iterable<T>, U> fn;
  final RxContext context;
  final Equality<T> equality;
  final Set<T> _data;
  U result;

  FnSink(this.context, this.fn, this.equality)
    : _data = HashSet(equals: equality.equals, hashCode: equality.hash, isValidKey: equality.isValidKey);

  @override
  void onInit(Iterable<T> items) {
    _data.addAll(items);
    result = fn(items);
  }

  @override
  void onAdd(T newItem) {
    _data.add(newItem);
    _notifyIfChanged();
  }

  @override
  void onRemove(T oldItem) {
    _data.remove(oldItem);
    _notifyIfChanged();
  }

  @override
  void onChange(T oldItem, T newItem) {
    _data.remove(oldItem);
    _data.add(newItem);
    _notifyIfChanged();
  }

  void _notifyIfChanged() {
    final newResult = fn(_data);
    if (newResult != result) {
      result = newResult;
      context.notify();
    }
  }
}

class ToListSink<T> extends NotifySink<T> {
  var result = <T>[];

  ToListSink(RxContext context) : super(context);

  @override
  void onInit(Iterable<T> items) {
    result = items.toList();
  }
}

class ToSetSink<T> extends NotifySink<T> {
  var result = Set<T>();

  ToSetSink(RxContext context) : super(context);

  @override
  void onInit(Iterable<T> items) {
    result = items.toSet();
  }
}

class ToMapSink<K, V, T> extends NotifySink<T> {
  final Mapper<T, MapEntry<K, V>> mapper;
  final result = Map<K, V>();

  ToMapSink(this.mapper, RxContext context) : super(context);

  @override
  void onInit(Iterable<T> items) {
    result.addEntries(items.map(mapper));
  }
}