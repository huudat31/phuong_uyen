import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Quản lý database SQLite local để lưu text log.
/// Toàn bộ dữ liệu chỉ nằm trên máy, không upload ra ngoài.
class DbHelper {
  DbHelper._internal();
  static final DbHelper instance = DbHelper._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'self_monitor.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE text_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            package_name TEXT,
            content TEXT,
            timestamp TEXT
          )
        ''');
      },
    );
  }

  Future<void> insertTextLog(String packageName, String content) async {
    final db = await database;
    await db.insert('text_logs', {
      'package_name': packageName,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getTextLogs() async {
    final db = await database;
    return db.query('text_logs', orderBy: 'id DESC', limit: 500);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('text_logs');
  }
}
