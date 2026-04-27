// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/expense_model.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final user = FirebaseAuth.instance.currentUser;
    final dbPath = await getDatabasesPath();
    final dbPathFile = p.join(dbPath, 'expenses_${user?.uid}.db');

    return await openDatabase(
      dbPathFile,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, icon TEXT)');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT, amount TEXT, imagePath TEXT, category_id INTEGER,
            FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
          )
        ''');
      },
    );
  }

  // --- CRUD CATEGORIES ---
  Future<List<CategoryModel>> getCategories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('categories');
    return maps.map((e) => CategoryModel.fromMap(e)).toList();
  }

  Future<int> insertCategory(CategoryModel category) async {
    final db = await database;
    return await db.insert('categories', category.toMap());
  }

  Future<int> updateCategory(CategoryModel category) async {
    final db = await database;
    return await db.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // --- CRUD TRANSACTIONS ---
  Future<List<TransactionModel>> getTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT transactions.*, categories.name as categoryName 
      FROM transactions 
      LEFT JOIN categories ON transactions.category_id = categories.id
      ORDER BY transactions.id DESC
    ''');
    return maps.map((e) => TransactionModel.fromMap(e)).toList();
  }

  Future<int> insertTransaction(TransactionModel tx) async {
    final db = await database;
    return await db.insert('transactions', tx.toMap());
  }

  Future<int> updateTransaction(TransactionModel tx) async {
    final db = await database;
    return await db.update('transactions', tx.toMap(), where: 'id = ?', whereArgs: [tx.id]);
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }
}