import 'package:flutter/material.dart';
import 'package:flutter_rxtable/flutter_rxtable.dart';

void main() => runApp(new MyApp());

class Task {
  String id;
  String title;
  bool completed;

  Task(this.id, this.title, this.completed);

  Task copy({String title, bool completed}) => Task(id, title ?? this.title, completed ?? this.completed);

  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
      other is Task &&
        runtimeType == other.runtimeType &&
        id == other.id &&
        title == other.title &&
        completed == other.completed;

  @override
  int get hashCode =>
    id.hashCode ^
    title.hashCode ^
    completed.hashCode;
}

class TaskDatabase extends RxDatabase {
  RxTable<String, Task> tasks;
  RxView<bool, List<Task>> tasksByCompletion;

  TaskDatabase() {
    tasks = RxTable(this, (t) => t.id);
    tasksByCompletion = tasks.group((t) => t.completed);

    tasks.save(Task("1", "One", true));
    tasks.save(Task("2", "Two", true));
    tasks.save(Task("3", "Three", false));
  }

  static TaskDatabase of(BuildContext context) => RxDatabase.of<TaskDatabase>(context);
}

class TasksModule {
  final Provider _provider;
  TaskDatabase get _db => _provider.inject<TaskDatabase>();

  TasksModule(this._provider);

  static TasksModule of(BuildContext context) => Injector.inject<TasksModule>(context);

  void add(String title) {
    final id = (_db.tasks.count + 1).toString();
    _db.tasks.save(Task(id, title, false));
  }

  void toggleCompleted(String id) {
    _db.tasks.update(id, (t) => t.copy(completed: !t.completed));
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  TaskDatabase _db;
  TasksModule _tasks;
  Provider _provider;

  @override
  void initState() {
    super.initState();

    _provider = Provider();
    _db = TaskDatabase();
    _tasks = TasksModule(_provider);

    _provider.provide<TaskDatabase>(_db);
    _provider.provide<TasksModule>(_tasks);
  }

  @override
  Widget build(BuildContext context) {
    return Injector(
      provider: _provider,
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final db = TaskDatabase.of(context);
    print("build home page, context = ${context.hashCode}, db.context = ${db.context.hashCode}");

    return Scaffold(
      appBar: AppBar(
        title: Title(),
      ),
      body: TaskList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTask(context),
        child: Icon(Icons.add),
      ),
    );
  }

  void _addTask(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();

        return AlertDialog(
          title: Text("Add task"),
          content: TextField(controller: controller),
          actions: <Widget>[
            FlatButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("CANCEL"),
            ),
            FlatButton(
              onPressed: () {
                TasksModule.of(context).add(controller.text);
                Navigator.of(context).pop();
              },
              child: Text("OK"),
            ),
          ],
        );
      }
    );
  }
}

class TaskList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final db = TaskDatabase.of(context);
    print("build list, context = ${context.hashCode}, db.context = ${db.context.hashCode}");
    return ListView(
      children: db.tasks.ids.map((id) => TaskView(id)).toList(),
    );
  }
}

class Title extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final db = TaskDatabase.of(context);
    print("build title, context = ${context.hashCode}, db.context = ${db.context.hashCode}");
    return Text(
      "Tasks App (${db.tasksByCompletion[true]?.length ?? 0})"
      //"Tasks App"
    );
  }
}

class TaskView extends StatelessWidget {
  final String id;

  TaskView(this.id);

  @override
  Widget build(BuildContext context) {
    final db = TaskDatabase.of(context);
    print("build task $id, context = ${context.hashCode}, db.context = ${db.context.hashCode}");
    final task = db.tasks[id];

    return ListTile(
      leading: Icon(
        Icons.check,
        color: task.completed ? Colors.blue : Colors.grey,
      ),
      title: Text(task.title),
      onTap: () => TasksModule.of(context).toggleCompleted(id),
    );
  }
}