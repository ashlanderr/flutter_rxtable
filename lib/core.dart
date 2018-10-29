import 'package:flutter/widgets.dart';

abstract class RxHandle {
  const RxHandle();

  void close();
}

abstract class RxContext extends RxHandle {
  const RxContext();

  void add(RxHandle handle);
  void notify();
}

typedef U Mapper<T, U>(T t);

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