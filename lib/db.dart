import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_rxtable/core.dart';
import 'package:flutter_rxtable/stream.dart';
import 'package:meta/meta.dart';

typedef void ContextCallback();

class CallbackRxContext extends RxContext {
  final List<RxHandle> _handles = [];
  ContextCallback _callback;

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
  const NullRxContext();

  @override
  void close() {}

  @override
  void notify() {}

  @override
  void add(RxHandle handle) {
    handle.close();
  }
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

abstract class RxView<ID, T> extends RxStream<T> {
  final RxDatabase db;
  RxContext get context => db.context;

  Map<ID, T> get items;

  RxView(this.db, Equality<T> equality) : super(equality ?? DefaultEquality());

  T defaultValue() => null;

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
      mapper: (items) => items[id] ?? defaultValue()
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

class ContextObserver<ID, T, U> implements StreamObserver<T> {
  final Mapper<Map<ID, T>, U> mapper;
  final Equality<U> equality;
  final U result;
  final RxContext context;
  final RxView<ID, T> view;

  ContextObserver({this.context, this.view, this.equality, this.mapper})
    : result = mapper(view.items);

  @override
  void onInit(Iterable<T> items) {}

  @override
  void onAdd(T newItem) => changed();

  @override
  void onRemove(T oldItem) => changed();

  @override
  void onChange(T oldItem, T newItem) => changed();

  void changed() {
    final newResult = mapper(view.items);
    if (!equality.equals(newResult, result)) {
      context.notify();
    }
  }
}

class RxViewBaseHandler<T, ID> implements RxHandle {
  final Set<StreamObserver<T>> observers;
  final StreamObserver<T> observer;

  RxViewBaseHandler(this.observers, this.observer);

  @override
  void close() {
    observers.remove(observer);
  }
}

abstract class RxViewBase<ID, T> extends RxView<ID, T> {
  final Set<StreamObserver<T>> _observers = Set();

  RxViewBase(RxDatabase db, Equality<T> equality) : super(db, equality);

  @override
  RxHandle subscribe(StreamObserver<T> observer) {
    _observers.add(observer);
    observer.onInit(items.values);
    return RxViewBaseHandler(_observers, observer);
  }

  void _notifyListeners(void action(StreamObserver<T> observer)) {
    _observers.toList().forEach((o) => action(o));
  }

  @protected
  void notify(T oldItem, T newItem) {
    if (equality.equals(oldItem, newItem)) return;

    if (oldItem == null && newItem != null) {
      _notifyListeners((observer) => observer.onAdd(newItem));
    } else if (oldItem != null && newItem == null) {
      _notifyListeners((observer) => observer.onRemove(oldItem));
    } else if (oldItem != null && newItem != null) {
      _notifyListeners((observer) => observer.onChange(oldItem, newItem));
    }
  }
}

class RxTable<ID, T> extends RxViewBase<ID, T> {
  final Map<ID, T> _items = {};
  final Mapper<T, ID> _mapper;

  @override
  Map<ID, T> get items => _items;

  RxTable(RxDatabase db, this._mapper, {Equality<T> equality}) : super(db, equality ?? DefaultEquality());

  void save(T row) {
    final id = _mapper(row);
    final oldRow = _items[id];
    _items[id] = row;
    notify(oldRow, row);
  }

  void saveAll(Iterable<T> rows) {
    for (final row in rows) {
      save(row);
    }
  }

  void deleteById(ID id) {
    final oldRow = _items.remove(id);
    if (oldRow != null) {
      notify(oldRow, null);
    }
  }

  void delete(T row) {
    deleteById(_mapper(row));
  }

  void deleteAll([Iterable<T> rows]) {
    if (rows != null) {
      for (final row in rows) {
        delete(row);
      }
    } else {
      final ids = _items.keys.toList();
      deleteAllById(ids);
    }
  }

  void deleteAllById(Iterable<ID> ids) {
    for (final id in ids) {
      deleteById(id);
    }
  }

  void update(ID id, T updater(T row)) {
    var row = get(id);
    row = updater(row);
    save(row);
  }

  void reset(Iterable<T> rows) {
    deleteAll();
    saveAll(rows);
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

class RxMaterializedView<ID, T> extends RxViewBase<ID, T> implements StreamObserver<T> {
  final Map<ID, T> _items = {};
  final Mapper<T, ID> _mapper;

  @override
  Map<ID, T> get items => _items;

  RxMaterializedView(RxDatabase db, this._mapper, Equality<T> equality)
    : super(db, equality ?? DefaultEquality());

  @override
  void onChange(T oldItem, T newItem) {
    final id = _mapper(oldItem);
    assert(_mapper(newItem) == id);
    _items[id] = newItem;
    notify(oldItem, newItem);
  }

  @override
  void onRemove(T oldItem) {
    final id = _mapper(oldItem);
    _items.remove(id);
    notify(oldItem, null);
  }

  @override
  void onAdd(T newItem) {
    final id = _mapper(newItem);
    _items[id] = newItem;
    notify(null, newItem);
  }

  @override
  void onInit(Iterable<T> items) {
    for (final row in items) {
      final id = _mapper(row);
      _items[id] = row;
    }
  }
}