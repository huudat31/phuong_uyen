import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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
      version: 2,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createTables(db);
      },
      onOpen: (db) async {
        await _createTables(db);
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS text_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name TEXT,
        content TEXT,
        timestamp TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS screenshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT,
        timestamp TEXT
      )
    ''');
  }

  Future<void> insertTextLog(String packageName, String content) async {
    try {
      final db = await database;
      await db.insert('text_logs', {
        'package_name': packageName,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> insertScreenshot(String filePath) async {
    try {
      final db = await database;
      await db.insert('screenshots', {
        'file_path': filePath,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getTextLogs({int limit = 500}) async {
    try {
      final db = await database;
      return await db.query('text_logs', orderBy: 'id DESC', limit: limit);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getScreenshots({int limit = 500}) async {
    try {
      final db = await database;
      return await db.query('screenshots', orderBy: 'id DESC', limit: limit);
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteScreenshot(int id) async {
    try {
      final db = await database;
      await db.delete('screenshots', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  Future<void> deleteScreenshots(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final db = await database;
      final placeholders = List.filled(ids.length, '?').join(',');
      await db.delete(
        'screenshots',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
    } catch (_) {}
  }

  Future<void> deleteTextLog(int id) async {
    try {
      final db = await database;
      await db.delete('text_logs', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  Future<void> deleteTextLogs(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final db = await database;
      final placeholders = List.filled(ids.length, '?').join(',');
      await db.delete(
        'text_logs',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
    } catch (_) {}
  }

  Future<int> getScreenshotsCount() async {
    try {
      final db = await database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM screenshots'),
      );
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> getTextLogsCount() async {
    try {
      final db = await database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM text_logs'),
      );
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearAll() async {
    try {
      final db = await database;
      await db.delete('text_logs');
      await db.delete('screenshots');
    } catch (_) {}
  }
}
