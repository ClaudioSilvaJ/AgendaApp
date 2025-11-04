import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      print('Notificação tocada: ${details.payload}');
    },
  );

  final notificationService = NotificationService();
  await notificationService.requestPermissions();

  await notificationService.setupNotificationListeners();

  runApp(StudyScheduleApp());
}

class StudyScheduleApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agenda de Estudos',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: HomeScreen(),
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'study_schedule.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE subjects(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            description TEXT,
            color INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE reminders(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subjectId INTEGER,
            title TEXT,
            dateTime TEXT,
            isActive INTEGER,
            FOREIGN KEY (subjectId) REFERENCES subjects (id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<int> insertSubject(Subject subject) async {
    final db = await database;
    return await db.insert('subjects', subject.toMap());
  }

  Future<List<Subject>> getSubjects() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('subjects');
    return List.generate(maps.length, (i) {
      return Subject.fromMap(maps[i]);
    });
  }

  Future<int> updateSubject(Subject subject) async {
    final db = await database;
    return await db.update(
      'subjects',
      subject.toMap(),
      where: 'id = ?',
      whereArgs: [subject.id],
    );
  }

  Future<int> deleteSubject(int id) async {
    final db = await database;
    await db.delete('reminders', where: 'subjectId = ?', whereArgs: [id]);
    return await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertReminder(Reminder reminder) async {
    final db = await database;
    return await db.insert('reminders', reminder.toMap());
  }

  Future<List<Reminder>> getReminders(int subjectId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'reminders',
      where: 'subjectId = ?',
      whereArgs: [subjectId],
    );
    return List.generate(maps.length, (i) {
      return Reminder.fromMap(maps[i]);
    });
  }

  Future<List<Reminder>> getAllReminders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('reminders');
    return List.generate(maps.length, (i) {
      return Reminder.fromMap(maps[i]);
    });
  }

  Future<int> updateReminder(Reminder reminder) async {
    final db = await database;
    return await db.update(
      'reminders',
      reminder.toMap(),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  Future<int> deleteReminder(int id) async {
    final db = await database;
    return await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }
}

class Subject {
  final int? id;
  final String name;
  final String description;
  final int color;

  Subject({
    this.id,
    required this.name,
    required this.description,
    required this.color,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'description': description, 'color': color};
  }

  static Subject fromMap(Map<String, dynamic> map) {
    return Subject(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      color: map['color'],
    );
  }
}

class Reminder {
  final int? id;
  final int subjectId;
  final String title;
  final DateTime dateTime;
  final bool isActive;

  Reminder({
    this.id,
    required this.subjectId,
    required this.title,
    required this.dateTime,
    required this.isActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subjectId': subjectId,
      'title': title,
      'dateTime': dateTime.toIso8601String(),
      'isActive': isActive ? 1 : 0,
    };
  }

  static Reminder fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'],
      subjectId: map['subjectId'],
      title: map['title'],
      dateTime: DateTime.parse(map['dateTime']),
      isActive: map['isActive'] == 1,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> setupNotificationListeners() async {
    final details =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp) {
      if (details.notificationResponse != null) {
        final payload = details.notificationResponse!.payload;
        print('App aberto pela notificação! Payload: $payload');
      }
    }

    await rescheduleReminders();
  }

  Future<void> rescheduleReminders() async {
    try {
      final DatabaseHelper dbHelper = DatabaseHelper();
      final allReminders = await dbHelper.getAllReminders();

      final activeReminders = allReminders.where((r) => r.isActive).toList();

      print('Reagendando ${activeReminders.length} notificações pendentes');

      for (final reminder in activeReminders) {
        final subjectsList = await dbHelper.getSubjects();
        final subject = subjectsList.firstWhere(
          (s) => s.id == reminder.subjectId,
          orElse:
              () => Subject(
                name: 'Lembrete',
                description: '',
                color: Colors.blue.value,
              ),
        );

        if (reminder.dateTime.isAfter(DateTime.now())) {
          await scheduleNotification(
            reminder.id!,
            'Lembrete: ${subject.name}',
            reminder.title,
            reminder.dateTime,
          );
        }
      }
    } catch (e) {
      print('Erro ao reagendar notificações: $e');
    }
  }

  Future<bool> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();

      try {
        await androidPlugin.requestExactAlarmsPermission();
        return true;
      } catch (e) {
        print('Erro ao solicitar permissão para alarmes exatos: $e');
        return false;
      }
    }
    return true;
  }

  Future<void> scheduleNotification(
    int id,
    String title,
    String body,
    DateTime scheduledDate,
  ) async {
    try {
      final now = DateTime.now();
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(Duration(days: 1));
        print('Data ajustada para o futuro: ${scheduledDate.toString()}');
      }
      await requestPermissions();
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'test_channel',
            'Notifications Test',
            channelDescription: 'Channel for testing notifications',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
            enableLights: true,
          );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
      );

      print('Agendando notificação para: ${scheduledDate.toString()}');
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(scheduledDate, tz.local),
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        print('Notificação agendada com sucesso (modo exato) para ID: $id');
      } catch (e) {
        print('Erro ao agendar notificação exata: $e');
        await _scheduleWithoutExactTiming(id, title, body, scheduledDate);
      }
    } catch (e) {
      print('Não foi possível exibir nem mesmo uma notificação de erro');
    }
  }

  Future<void> _scheduleWithoutExactTiming(
    int id,
    String title,
    String body,
    DateTime scheduledDate,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'study_schedule_channel',
          'Study Schedule Notifications',
          channelDescription: 'Canal para lembretes de estudos (não exato)',
          importance: Importance.high,
          priority: Priority.high,
        );
    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    print('Tentando agendar sem precisão exata');
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    print('Notificação inexata agendada');
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

Widget _buildStatItem({
  required IconData icon,
  required String value,
  required String label,
}) {
  return Column(
    children: [
      Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.indigo.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.indigo, size: 24),
      ),
      SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.grey[600])),
    ],
  );
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Subject> _subjects = [];
  bool _isLoading = true;
  int _upcomingRemindersCount = 0;
  int _todayRemindersCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final subjects = await _dbHelper.getSubjects();

    await _loadReminderStatistics();

    setState(() {
      _subjects = subjects;
      _isLoading = false;
    });
  }

  Future<void> _loadReminderStatistics() async {
    final allReminders = await _dbHelper.getAllReminders();

    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(Duration(days: 1));

    final todayReminders =
        allReminders.where((reminder) {
          return reminder.dateTime.isAfter(startOfDay) &&
              reminder.dateTime.isBefore(endOfDay) &&
              reminder.isActive;
        }).toList();

    final upcomingReminders =
        allReminders.where((reminder) {
          return reminder.dateTime.isAfter(DateTime.now()) && reminder.isActive;
        }).toList();

    setState(() {
      _todayRemindersCount = todayReminders.length;
      _upcomingRemindersCount = upcomingReminders.length;
    });
  }

  Future<void> _loadSubjects() async {
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Agenda de Estudos')),
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  _buildStatisticsCard(),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Suas Matérias',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Spacer(),
                        if (_subjects.isNotEmpty)
                          Text(
                            'Total: ${_subjects.length}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child:
                        _subjects.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.book_outlined,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Adicione matérias para começar',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            : GridView.builder(
                              padding: EdgeInsets.all(16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 1.3,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                              itemCount: _subjects.length,
                              itemBuilder: (BuildContext context, index) {
                                return SubjectGridCard(
                                  subject: _subjects[index],
                                  onTap:
                                      () => _navigateToSubjectDetail(
                                        _subjects[index],
                                        context,
                                      ),
                                  onDelete:
                                      () => _deleteSubject(
                                        _subjects[index].id!,
                                        context,
                                      ),
                                );
                              },
                            ),
                  ),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAddSubject(context),
        child: Icon(Icons.add),
        tooltip: 'Adicionar Matéria',
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Resumo de Estudos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  icon: Icons.book,
                  value: _subjects.length.toString(),
                  label: 'Matérias',
                ),
                _buildStatItem(
                  icon: Icons.alarm,
                  value: _upcomingRemindersCount.toString(),
                  label: 'Lembretes',
                ),
                _buildStatItem(
                  icon: Icons.today,
                  value: _todayRemindersCount.toString(),
                  label: 'Hoje',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.indigo, size: 24),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Future<void> _navigateToSubjectDetail(Subject subject, context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (BuildContext context) => SubjectDetailScreen(subject: subject),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _navigateToAddSubject(BuildContext ctx) async {
    final result = await Navigator.push(
      ctx,
      MaterialPageRoute(builder: (BuildContext context) => SubjectFormScreen()),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _deleteSubject(int id, BuildContext ctx) async {
    await _dbHelper.deleteSubject(id);
    _loadSubjects();
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text('Matéria excluída com sucesso')));
  }
}

class SubjectGridCard extends StatelessWidget {
  final Subject subject;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const SubjectGridCard({
    required this.subject,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Color(subject.color).withOpacity(0.2),
              ),
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Color(subject.color),
                        radius: 18,
                        child: Text(
                          subject.name.isNotEmpty
                              ? subject.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          subject.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    subject.description,
                    style: TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                icon: Icon(
                  Icons.delete,
                  size: 20,
                  color: Colors.red.withOpacity(0.7),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder:
                        (BuildContext dialogContext) => AlertDialog(
                          title: Text('Excluir matéria'),
                          content: Text(
                            'Deseja realmente excluir ${subject.name}? Todos os lembretes associados também serão excluídos.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: Text('CANCELAR'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                onDelete();
                              },
                              child: Text('EXCLUIR'),
                            ),
                          ],
                        ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubjectFormScreen extends StatefulWidget {
  final Subject? subject;

  const SubjectFormScreen({this.subject});

  @override
  _SubjectFormScreenState createState() => _SubjectFormScreenState();
}

class _SubjectFormScreenState extends State<SubjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  int _selectedColor = Colors.blue.value;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  final List<Color> _colorOptions = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.brown,
    Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.subject != null) {
      _nameController.text = widget.subject!.name;
      _descriptionController.text = widget.subject!.description;
      _selectedColor = widget.subject!.color;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.subject == null ? 'Adicionar Matéria' : 'Editar Matéria',
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nome da Matéria',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira um nome';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              SizedBox(height: 16),
              Text('Cor:', style: TextStyle(fontSize: 16)),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _colorOptions.map((color) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedColor = color.value;
                          });
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _selectedColor == color.value
                                      ? Colors.black
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
              Spacer(),
              ElevatedButton(
                onPressed: () => _saveSubject(context),
                child: Text('SALVAR'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveSubject(BuildContext ctx) async {
    if (_formKey.currentState!.validate()) {
      if (widget.subject == null) {
        final newSubject = Subject(
          name: _nameController.text,
          description: _descriptionController.text,
          color: _selectedColor,
        );
        await _dbHelper.insertSubject(newSubject);
      } else {
        final updatedSubject = Subject(
          id: widget.subject!.id,
          name: _nameController.text,
          description: _descriptionController.text,
          color: _selectedColor,
        );
        await _dbHelper.updateSubject(updatedSubject);
      }
      Navigator.pop(ctx, true);
    }
  }
}

class SubjectDetailScreen extends StatefulWidget {
  final Subject subject;

  const SubjectDetailScreen({required this.subject});

  @override
  _SubjectDetailScreenState createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NotificationService _notificationService = NotificationService();
  List<Reminder> _reminders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);
    final reminders = await _dbHelper.getReminders(widget.subject.id!);
    setState(() {
      _reminders = reminders;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name),
        actions: [
          IconButton(
            icon: Icon(Icons.edit),
            onPressed: () => _editSubject(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: Color(widget.subject.color).withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Descrição:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 4),
                Text(
                  widget.subject.description.isEmpty
                      ? 'Sem descrição'
                      : widget.subject.description,
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Lembretes:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          Expanded(
            child:
                _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _reminders.isEmpty
                    ? Center(
                      child: Text(
                        'Nenhum lembrete adicionado',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                    : ListView.builder(
                      itemCount: _reminders.length,
                      itemBuilder: (BuildContext context, index) {
                        return ReminderCard(
                          reminder: _reminders[index],
                          subjectColor: Color(widget.subject.color),
                          onDelete:
                              () => _deleteReminder(
                                _reminders[index].id!,
                                context,
                              ),
                          onToggle:
                              (value) =>
                                  _toggleReminder(_reminders[index], value),
                        );
                      },
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addReminder(context),
        child: Icon(Icons.add_alarm),
        tooltip: 'Adicionar Lembrete',
      ),
    );
  }

  Future<void> _editSubject(context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (BuildContext context) =>
                SubjectFormScreen(subject: widget.subject),
      ),
    );

    if (result == true) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _addReminder(BuildContext context) async {
    final DateTime now = DateTime.now();
    DateTime selectedDate = now;

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(Duration(days: 365)),
      lastDate: now.add(Duration(days: 365)),
    );

    if (pickedDate != null) {
      selectedDate = pickedDate;

      final TimeOfDay? timeOfDay = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(Duration(minutes: 30))),
      );

      if (timeOfDay != null) {
        final DateTime selectedDateTime = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          timeOfDay.hour,
          timeOfDay.minute,
        );

        showDialog(
          context: context,
          builder: (BuildContext dialogContext) {
            final titleController = TextEditingController();
            bool isRecurring = false;

            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: Text('Novo Lembrete'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Data: ${_formatDate(selectedDateTime)}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'Título do lembrete',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                        autofocus: true,
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Checkbox(
                            value: isRecurring,
                            onChanged: (value) {
                              setState(() {
                                isRecurring = value ?? false;
                              });
                            },
                          ),
                          Text('Repetir diariamente'),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text('CANCELAR'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (titleController.text.isNotEmpty) {
                          final reminder = Reminder(
                            subjectId: widget.subject.id!,
                            title: titleController.text,
                            dateTime: selectedDateTime,
                            isActive: true,
                          );

                          final id = await _dbHelper.insertReminder(reminder);
                          await _notificationService.scheduleNotification(
                            id,
                            'Lembrete: ${widget.subject.name}',
                            reminder.title,
                            reminder.dateTime,
                          );
                          Navigator.pop(dialogContext);
                          _loadReminders();
                        }
                      },
                      child: Text('SALVAR'),
                    ),
                  ],
                );
              },
            );
          },
        );
      }
    }
  }

  Future<void> _deleteReminder(int id, BuildContext context) async {
    await _dbHelper.deleteReminder(id);
    await _notificationService.cancelNotification(id);
    _loadReminders();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Lembrete excluído com sucesso')));
  }

  Future<void> _toggleReminder(Reminder reminder, bool isActive) async {
    final updatedReminder = Reminder(
      id: reminder.id,
      subjectId: reminder.subjectId,
      title: reminder.title,
      dateTime: reminder.dateTime,
      isActive: isActive,
    );

    await _dbHelper.updateReminder(updatedReminder);

    if (isActive) {
      await _notificationService.scheduleNotification(
        reminder.id!,
        'Lembrete: ${widget.subject.name}',
        reminder.title,
        reminder.dateTime,
      );
    } else {
      await _notificationService.cancelNotification(reminder.id!);
    }

    _loadReminders();
  }
}

class ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final Color subjectColor;
  final VoidCallback onDelete;
  final Function(bool) onToggle;

  const ReminderCard({
    required this.reminder,
    required this.subjectColor,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPast = reminder.dateTime.isBefore(DateTime.now());

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPast ? Colors.red.withOpacity(0.3) : Colors.transparent,
            width: isPast ? 1.5 : 0,
          ),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: subjectColor.withOpacity(0.2),
            ),
            child: Icon(
              isPast ? Icons.event_busy : Icons.event_available,
              color: isPast ? Colors.red : subjectColor,
            ),
          ),
          title: Text(
            reminder.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              decoration:
                  isPast && !reminder.isActive
                      ? TextDecoration.lineThrough
                      : null,
            ),
          ),
          subtitle: Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey),
              SizedBox(width: 4),
              Text(
                '${_formatTime(reminder.dateTime)}',
                style: TextStyle(color: isPast ? Colors.red : Colors.black87),
              ),
              if (isPast)
                Text(
                  ' (Atrasado)',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: reminder.isActive,
                onChanged: onToggle,
                activeColor: subjectColor,
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red.withOpacity(0.7)),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

String _formatDate(DateTime dateTime) {
  final day = dateTime.day.toString().padLeft(2, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$day/$month ${hour}:${minute}';
}
