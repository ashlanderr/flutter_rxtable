import 'package:flutter/material.dart';
import 'package:flutter_rxtable/flutter_rxtable.dart';

void main() => runApp(new MyApp());

// database

class Task {
  final String id;
  final String title;

  Task(this.id, this.title);

  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
      other is Task &&
        runtimeType == other.runtimeType &&
        id == other.id &&
        title == other.title;

  @override
  int get hashCode =>
    id.hashCode ^
    title.hashCode;
}

class MyDatabase extends RxDatabase<MyDatabase> {
  RxSingle<int> counter;
  RxTable<String, Task> tasks;
  RxSet<String> selection;

  MyDatabase() {
    counter = RxSingle(this);
    tasks = RxTable(this, (t) => t.id);
    selection = RxSet(this);
  }

  void init() => mutate(() {
    counter.put(0);
    tasks.save(Task("1", "Create RxTable library"));
    tasks.save(Task("2", "Write example code"));
    tasks.save(Task("3", "Test that it works"));
    selection.save("1");
  });

  void increment() => mutate(() {
    final count = counter.get();
    counter.put(count + 1);
  });

  void toggleSelection(String taskId) => mutate(() {
    final selected = selection.contains(taskId);
    if (selected)
      selection.delete(taskId);
    else
      selection.save(taskId);
  });
}

// view

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RxStore<MyDatabase>(
      database: initDb(),
      child: new MaterialApp(
        title: 'Flutter Demo',
        theme: new ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: new HomePage(),
      ),
    );
  }

  MyDatabase initDb() {
    final db = MyDatabase();
    db.init();
    return db;
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return RxConnector<MyDatabase>(
      builder: (_, db) {
        final tasks = db.tasks.all();
        print(tasks);

        return Scaffold(
          body: Column(
            children: <Widget>[
              CounterAppBar(),
              Expanded(
                child: ListView(
                  children: tasks.map((t) => TaskView(t)).toList(),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => db.increment(),
            child: Icon(Icons.add),
          ),
        );
      },
    );
  }
}

class CounterAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RxConnector<MyDatabase>(
      builder: (_, db) {
        print("COUNTER");
        return AppBar(
          title: Text(db.counter.get().toString()),
        );
      }
    );
  }
}

class TaskViewModel {
  String title;
  bool selected;

  TaskViewModel(MyDatabase db, Task task) {
    title = task.title;
    selected = db.selection.contains(task.id);
  }
}

class TaskView extends StatelessWidget {
  final Task task;

  TaskView(this.task);

  @override
  Widget build(BuildContext context) {
    return RxConnector<MyDatabase>(
      builder: (_, db) {
        final model = TaskViewModel(db, task);
        print("${task.id} selection = ${model.selected}");

        return GestureDetector(
          child: Container(
            color: model.selected ? Colors.orange : null,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(task.title, style: Theme.of(context).textTheme.subhead),
            ),
          ),
          onTap: () => db.toggleSelection(task.id),
        );
      },
    );
  }
}
