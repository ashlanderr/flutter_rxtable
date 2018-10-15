library flutter_rxtable;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:collection/collection.dart';

abstract class RxHandle {
  void close();
}

abstract class RxObserver<T> {
  void changed(T t);
}

typedef U Mapper<T, U>(T t);

abstract class RxContext extends RxHandle {
  void add(RxHandle handle);
  void notify();
}

class CallbackRxContext extends RxContext {
  final List<RxHandle> _handles = [];
  VoidCallback _callback;

  CallbackRxContext(this._callback);

  @override
  void add(RxHandle handle) {
    if (_callback == null) return;

    _handles.add(handle);
  }

  @override
  void notify() {
    if (_callback == null) return;

    final callback = _callback;
    close();
    callback();
  }

  @override
  void close() {
    _handles.forEach((h) => h.close());
    _handles.clear();
    _callback = null;
  }
}

class NullRxContext extends RxContext {
  @override
  void close() {}

  @override
  void notify() {}

  @override
  void add(RxHandle handle) {}
}

class ContextObserver<ID, T, U> implements RxObserver<Map<ID, T>> {
  final Mapper<Map<ID, T>, U> mapper;
  final Equality<U> equality;
  final U result;
  final RxContext context;

  ContextObserver({this.context, RxView<ID, T> view, this.equality, this.mapper})
    : result = mapper(view.items);

  @override
  void changed(Map<ID, T> items) {
    final newResult = mapper(items);
    if (!equality.equals(newResult, result)) {
      context.notify();
    }
  }
}

class AssociateObserver<K, ID, T> extends RxViewBase<K, T> implements RxObserver<Map<ID, T>> {
  final _equal = MapEquality<K, T>().equals;

  Map<K, T> _items = {};
  RxHandle _handle;

  final Mapper<T, K> mapper;

  AssociateObserver(RxDatabase db, this.mapper, Map<ID, T> items, Equality<T> equality) : super(db, equality) {
    _rebuild(items);
  }

  @override
  Map<K, T> get items => _items;

  @override
  void close() {
    _handle.close();
  }

  @override
  void changed(Map<ID, T> t) {
    _rebuild(t);
  }

  void _rebuild(Map<ID, T> items) {
    final Map<K, T> newItems = {};
    items.forEach((_, item) => newItems[mapper(item)] = item);
    if (!_equal(newItems, _items)) {
      _items = newItems;
      notifyListeners();
    }
  }
}

class GroupObserver<K, ID, T> extends RxViewBase<K, List<T>> implements RxObserver<Map<ID, T>> {
  final _equal = MapEquality<K, List<T>>().equals;

  Map<K, List<T>> _items = {};
  RxHandle _handle;

  final Mapper<T, K> mapper;

  GroupObserver(RxDatabase db, this.mapper, Map<ID, T> items, Equality<T> equality)
    : super(db, ListEquality(equality)) {
    _rebuild(items);
  }

  @override
  Map<K, List<T>> get items => _items;

  @override
  void close() {
    _handle.close();
  }

  @override
  void changed(Map<ID, T> t) {
    _rebuild(t);
  }

  void _rebuild(Map<ID, T> items) {
    final Map<K, List<T>> newItems = {};
    items.forEach((_, item) {
      final key = mapper(item);
      final list = newItems.putIfAbsent(key, () => List<T>());
      list.add(item);
    });
    if (!_equal(newItems, _items)) {
      _items = newItems;
      notifyListeners();
    }
  }
}

abstract class RxView<ID, T> extends RxHandle {
  final RxDatabase db;
  final Equality<T> equality;
  RxContext get context => db.context;

  Map<ID, T> get items;

  RxView(this.db, Equality<T> equality) : equality = equality ?? DefaultEquality();

  RxHandle subscribe(RxObserver<Map<ID, T>> observer);

  bool get isEmpty {
    final observer = _observer(
      mapper: (items) => items.values.isEmpty
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  bool get isNotEmpty => !isEmpty;

  int get count {
    final observer = _observer(
      mapper: (items) => items.values.length
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  bool contains(ID id) {
    final observer = _observer(
      mapper: (items) => items[id] != null
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  T get(ID id) {
    final observer = _observer(
      equality: equality,
      mapper: (items) => items[id]
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  T operator [](ID id) => get(id);

  List<T> get values {
    final observer = _observer(
      equality: ListEquality(equality),
      mapper: (items) => items.values.toList()
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  List<ID> get ids {
    final observer = _observer(
      equality: ListEquality(),
      mapper: (items) => items.keys.toList()
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  Iterable<T> filter(Mapper<T, bool> f) {
    final observer = _observer(
      equality: ListEquality(equality),
      mapper: (items) => items.values.where(f).toList()
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  Iterable<U> map<U>(Mapper<T, U> f) {
    final observer = _observer(
      equality: ListEquality<U>(),
      mapper: (items) => items.values.map(f).toList()
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  RxView<K, T> associate<K>(Mapper<T, K> f) {
    final observer = AssociateObserver<K, ID, T>(db, f, items, equality);
    observer._handle = subscribe(observer);
    return observer;
  }

  RxView<K, List<T>> group<K>(Mapper<T, K> f) {
    final observer = GroupObserver<K, ID, T>(db, f, items, equality);
    observer._handle = subscribe(observer);
    return observer;
  }

  ContextObserver<ID, T, U> _observer<U>({
    Equality<U> equality,
    Mapper<Map<ID, T>, U> mapper,
  }) => ContextObserver(
    context: context,
    view: this,
    equality: equality ?? DefaultEquality(),
    mapper: mapper,
  );
}

class RxViewBaseHandler<T, ID> implements RxHandle {
  final Set<RxObserver<Map<ID, T>>> observers;
  final RxObserver<Map<ID, T>> observer;

  RxViewBaseHandler(this.observers, this.observer);

  @override
  void close() {
    observers.remove(observer);
  }
}

abstract class RxViewBase<ID, T> extends RxView<ID, T> {
  final Set<RxObserver<Map<ID, T>>> _observers = Set();

  RxViewBase(RxDatabase db, Equality<T> equality) : super(db, equality);

  @override
  RxHandle subscribe(RxObserver<Map<ID, T>> observer) {
    _observers.add(observer);
    return RxViewBaseHandler(_observers, observer);
  }

  @protected
  void notifyListeners() {
    _observers.toList().forEach((o) => o.changed(items));
  }
}

class RxTable<ID, T> extends RxViewBase<ID, T> {
  final Map<ID, T> _items = {};
  final Mapper<T, ID> _mapper;

  @override
  Map<ID, T> get items => _items;

  RxTable(RxDatabase db, this._mapper, {Equality<T> equality}) : super(db, equality ?? DefaultEquality());

  @override
  void close() {}

  void save(T row) {
    final id = _mapper(row);
    final oldRow = _items[id];
    if (oldRow != row) {
      _items[id] = row;
      notifyListeners();
    }
  }

  void saveAll(Iterable<T> rows) {
    var changed = false;

    for (final row in rows) {
      final id = _mapper(row);
      final oldRow = _items[id];
      if (oldRow != row) {
        _items[id] = row;
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  void deleteById(ID id) {
    final oldRow = _items.remove(id);
    if (oldRow != null) {
      notifyListeners();
    }
  }

  void delete(T row) {
    deleteById(_mapper(row));
  }

  void deleteAll([Iterable<T> rows]) {
    if (rows != null) {
      for (final row in rows) {
        final id = _mapper(row);
        _items.remove(id);
      }
    } else {
      _items.clear();
    }
    notifyListeners();
  }

  void deleteAllById(Iterable<ID> ids) {
    for (final id in ids) {
      _items.remove(id);
    }
    notifyListeners();
  }

  void update(ID id, T updater(T row)) {
    var row = get(id);
    row = updater(row);
    save(row);
  }

  void reset(Iterable<T> rows) {
    var changed = false;

    if (_items.isNotEmpty) {
      _items.clear();
      changed = true;
    }

    for (final row in rows) {
      final id = _mapper(row);
      _items[id] = row;
      changed = true;
    }

    if (changed) notifyListeners();
  }
}

class RxSingle<T> {
  final RxTable<bool, T> _table;

  RxSingle(RxDatabase db) : _table = RxTable(db, (_) => true);

  T get() => _table.get(true);

  void put(T row) => _table.save(row);

  void delete() => _table.deleteById(true);
}

class RxSet<T> extends RxTable<T, T> {
  RxSet(RxDatabase db) : super(db, (t) => t);
}

class Provider {
  final Map<Type, Object> _modules = {};

  T provide<T>(T impl) {
    _modules[T] = impl;
    return impl;
  }

  T inject<T>() {
    final impl = _modules[T];
    assert(impl != null, "Implementation of type $T is not provided");
    return impl;
  }
}

class Injector extends InheritedWidget {
  final Provider provider;

  Injector({this.provider, Widget child, Key key}) : super(child: child, key: key);

  static Provider of(BuildContext context) {
    final injector = context.inheritFromWidgetOfExactType(Injector) as Injector;
    return injector.provider;
  }

  static T inject<T>(BuildContext context) {
    return of(context).inject<T>();
  }

  @override
  bool updateShouldNotify(Injector oldWidget) => oldWidget.provider != provider;
}

abstract class RxDatabase {
  RxContext context = NullRxContext();

  static RxDatabase of<DB extends RxDatabase>(BuildContext context) {
    final db = Injector.inject<DB>(context);
    final element = context as Element;
    final dbContext = CallbackRxContext(() {
      try {
        element.markNeedsBuild();
      } on AssertionError {
        // fixme assert(_debugLifecycleState != _ElementLifecycle.defunct) failed sometimes
      }
    });
    db.context = dbContext;
    scheduleMicrotask(() => db.context = NullRxContext());
    return db;
  }
}