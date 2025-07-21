import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:newton/models/ussd_data_plan.dart';
import 'package:newton/models/transaction.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'ussd_app.db');

    return await openDatabase(
      path,
      version: 5, // Incremented version
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> clearTransactions() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('transactions');
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create all tables
    await db.execute('''
      CREATE TABLE messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT,
        body TEXT,
        timestamp INTEGER,
        extractedName TEXT,
        extractedAmount REAL,
        extractedPhoneNumber TEXT,
        purchasedOffer TEXT,
        status TEXT DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE ussd_data_plans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        planName TEXT,
        ussdCodeTemplate TEXT,
        amount REAL,
        placeholder TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        amount REAL,
        phoneNumber TEXT,
        isSuccess INTEGER,
        timestamp INTEGER
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      // Create transactions table if not exists
      await db.execute('''
        CREATE TABLE IF NOT EXISTS transactions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          amount REAL,
          phoneNumber TEXT,
          isSuccess INTEGER,
          timestamp INTEGER
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE messages 
        ADD COLUMN extractedName TEXT
      ''');

      await db.execute('''
        ALTER TABLE messages 
        ADD COLUMN extractedAmount REAL
      ''');

      await db.execute('''
        ALTER TABLE messages 
        ADD COLUMN extractedPhoneNumber TEXT
      ''');

      await db.execute('''
        ALTER TABLE messages 
        ADD COLUMN purchasedOffer TEXT
      ''');

      await db.execute('''
        ALTER TABLE messages 
        ADD COLUMN status TEXT DEFAULT 'pending'
      ''');
    }
  }

  // Message operations
  Future<int> insertMessage(Map<String, dynamic> message) async {
    Database db = await database;
    return await db.insert('messages', message);
  }

  Future<List<Map<String, dynamic>>> getMessages() async {
    Database db = await database;
    return await db.query('messages', orderBy: 'timestamp DESC');
  }

  Future<int> updateMessage(int id, Map<String, dynamic> data) async {
    Database db = await database;
    return await db.update('messages', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateMessageStatus(int timestamp, String status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status},
      where: 'timestamp = ?',
      whereArgs: [timestamp],
    );
  }

  Future<int> deleteMessage(int id) async {
    Database db = await database;
    return await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteMessagesBefore(int timestamp) async {
    final db = await database;
    return await db.delete(
      'messages',
      where: 'timestamp < ?',
      whereArgs: [timestamp],
    );
  }

  // USSD Data Plan operations
  Future<int> insertUssdDataPlan(UssdDataPlan plan) async {
    Database db = await database;
    return await db.insert('ussd_data_plans', plan.toMap());
  }

  Future<List<UssdDataPlan>> getUssdDataPlans() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query('ussd_data_plans');
    return List.generate(maps.length, (i) {
      return UssdDataPlan.fromMap(maps[i]);
    });
  }

  Future<UssdDataPlan?> getUssdDataPlanByAmount(double amount) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'ussd_data_plans',
      where: 'amount = ?',
      whereArgs: [amount],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return UssdDataPlan.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateUssdDataPlan(UssdDataPlan plan) async {
    Database db = await database;
    return await db.update(
      'ussd_data_plans',
      plan.toMap(),
      where: 'id = ?',
      whereArgs: [plan.id],
    );
  }

  Future<int> deleteUssdDataPlan(int id) async {
    Database db = await database;
    return await db.delete('ussd_data_plans', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertTransaction(Transactions transaction) async {
    final db = await database;
    return await db.insert(
      'transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // New: getTransactionById
  Future<Transactions?> getTransactionById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Transactions.fromMap(maps.first);
    }
    return null;
  }

  // New: updateTransaction
  Future<int> updateTransaction(Transactions transaction) async {
    final db = await database;
    return await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // In DatabaseHelper
  Future<List<Transactions>> getAllTransactions() async {
    final db = await database;
    final maps = await db.query('transactions', orderBy: 'timestamp DESC');
    return List.generate(maps.length, (i) => Transactions.fromMap(maps[i]));
  }

  Future<List<Transactions>> getSuccessfulTransactions() async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: 'isSuccess = ?',
      whereArgs: [1],
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) => Transactions.fromMap(maps[i]));
  }

  Future<List<Transactions>> getFailedTransactions() async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: 'isSuccess = ?',
      whereArgs: [0],
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) => Transactions.fromMap(maps[i]));
  }

  Future<bool> tableExists(String tableName) async {
    final db = await database;
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return res.isNotEmpty;
  }
}
