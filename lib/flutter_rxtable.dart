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

  AssociateObserver(RxDatabase db, this.mapper, Map<ID, T> items) : super(db) {
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

  GroupObserver(RxDatabase db, this.mapper, Map<ID, T> items) : super(db) {
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
  RxContext get context => db.context;

  Map<ID, T> get items;

  RxView(this.db);

  RxHandle subscribe(RxObserver<Map<ID, T>> observer);

  T get(ID id) {
    final observer = ContextObserver<ID, T, T>(
      context: context,
      view: this,
      equality: DefaultEquality<T>(),
      mapper: (items) => items[id]
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  T operator [](ID id) => get(id);

  List<T> all() {
    final observer = ContextObserver<ID, T, List<T>>(
      context: context,
      view: this,
      equality: ListEquality<T>(),
      mapper: (items) => items.values.toList()
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  Iterable<T> filter(Mapper<T, bool> f) {
    final observer = ContextObserver<ID, T, List<T>>(
      context: context,
      view: this,
      equality: ListEquality<T>(),
      mapper: (items) => items.values.where(f).toList()
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  Iterable<U> map<U>(Mapper<T, U> f) {
    final observer = ContextObserver<ID, T, List<U>>(
      context: context,
      view: this,
      equality: ListEquality<U>(),
      mapper: (items) => items.values.map(f).toList()
    );
    context.add(subscribe(observer));
    return observer.result;
  }

  RxView<K, T> associate<K>(Mapper<T, K> f) {
    final observer = AssociateObserver<K, ID, T>(db, f, items);
    observer._handle = subscribe(observer);
    return observer;
  }

  RxView<K, List<T>> group<K>(Mapper<T, K> f) {
    final observer = GroupObserver<K, ID, T>(db, f, items);
    observer._handle = subscribe(observer);
    return observer;
  }
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

  RxViewBase(RxDatabase db) : super(db);

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

  RxTable(RxDatabase db, this._mapper) : super(db);

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

  void deleteById(ID id) {
    final oldRow = _items.remove(id);
    if (oldRow != null) {
      notifyListeners();
    }
  }

  void delete(T row) {
    deleteById(_mapper(row));
  }
}

class RxSingle<T> {
  final RxTable<bool, T> _table;

  RxSingle(RxDatabase db) : _table = RxTable(db, (_) => true);

  T get() => _table.get(true);

  void put(T row) => _table.save(row);
}

class RxSet<T> extends RxTable<T, T> {
  RxSet(RxDatabase db) : super(db, (t) => t);

  bool contains(T t) => get(t) != null;
}

enum RxDatabaseState {
  normal,
  query,
  mutate
}

abstract class RxAction<DB extends RxDatabase<DB>> {
  Future<void> execute(DB db);
}

class ResultAndHandle<T> {
  final T result;
  final RxHandle handle;

  ResultAndHandle(this.result, this.handle);
}

abstract class RxDatabase<DB extends RxDatabase<DB>> {
  var _state = RxDatabaseState.normal;

  RxContext _context = NullRxContext();
  RxContext get context => _context;

  ResultAndHandle<T> query<T>(VoidCallback onChange, T block()) {
    assert(_state == RxDatabaseState.normal);
    try {
      _state = RxDatabaseState.query;
      _context = CallbackRxContext(onChange);
      final result = block();
      return ResultAndHandle(result, _context);
    } finally {
      _state = RxDatabaseState.normal;
      _context = NullRxContext();
    }
  }

  void mutate(void block()) {
    assert(_state == RxDatabaseState.normal);
    try {
      _state = RxDatabaseState.mutate;
      block();
    } finally {
      _state = RxDatabaseState.normal;
    }
  }
}

class RxStore<DB extends RxDatabase<DB>> extends InheritedWidget {
  final DB database;

  RxStore({
    this.database,
    Key key,
    Widget child
  }) : super(
    key: key,
    child: child
  );

  @override
  bool updateShouldNotify(RxStore oldWidget) {
    return oldWidget.database != database;
  }

  static DB of<DB extends RxDatabase<DB>>(BuildContext context) {
    final widget = context.inheritFromWidgetOfExactType(_type<RxStore<DB>>()) as RxStore<DB>;
    return widget.database;
  }

  static Type _type<T>() => T;
}

typedef Widget RxBuilder<DB extends RxDatabase<DB>>(BuildContext context, DB db);

class RxConnector<DB extends RxDatabase<DB>> extends StatefulWidget {
  final RxBuilder<DB> builder;

  RxConnector({this.builder});

  @override
  State createState() => _RxConnectorState<DB>();
}

class _RxConnectorState<DB extends RxDatabase<DB>> extends State<RxConnector<DB>> {
  RxHandle _handle;

  @override
  Widget build(BuildContext context) {
    final db = RxStore.of<DB>(context);
    final result = db.query(_changed, () => widget.builder(context, db));
    _handle = result.handle;
    return result.result;
  }

  void _changed() {
    _handle = null;
    setState(() {});
  }

  @override
  void dispose() {
    _handle?.close();
    _handle = null;
    super.dispose();
  }
}