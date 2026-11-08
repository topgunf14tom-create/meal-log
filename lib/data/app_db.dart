import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'entities.dart';

/// 端末内 SQLite。データはすべてここに保存し、外部には送らない。
class AppDb {
  late Database _db;

  /// 削除は子テーブルから、挿入は逆順で行う
  static const _tables = [
    'meal_items',
    'meals',
    'weights',
    'goals',
    'chain_menu_cache',
    'api_usage',
    'settings',
  ];

  static const _schema = [
    '''CREATE TABLE meals(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      meal_type TEXT NOT NULL,
      created_at TEXT NOT NULL,
      photo_path TEXT,
      model_used TEXT,
      note TEXT)''',
    'CREATE INDEX idx_meals_date ON meals(date)',
    '''CREATE TABLE meal_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      meal_id INTEGER NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      amount REAL NOT NULL,
      unit TEXT NOT NULL,
      grams REAL,
      kcal REAL NOT NULL,
      protein_g REAL NOT NULL,
      fat_g REAL NOT NULL,
      carbs_g REAL NOT NULL,
      confidence TEXT NOT NULL,
      source_type TEXT NOT NULL,
      source_url TEXT)''',
    '''CREATE TABLE weights(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL UNIQUE,
      weight_kg REAL NOT NULL)''',
    '''CREATE TABLE goals(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      start_date TEXT NOT NULL UNIQUE,
      target_kcal INTEGER NOT NULL,
      p_ratio INTEGER NOT NULL,
      f_ratio INTEGER NOT NULL,
      c_ratio INTEGER NOT NULL)''',
    '''CREATE TABLE chain_menu_cache(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      store_key TEXT NOT NULL,
      menu_key TEXT NOT NULL,
      display_name TEXT NOT NULL,
      items_json TEXT NOT NULL,
      source_url TEXT,
      fetched_at TEXT NOT NULL,
      UNIQUE(store_key, menu_key))''',
    '''CREATE TABLE api_usage(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT NOT NULL,
      model TEXT NOT NULL,
      purpose TEXT NOT NULL,
      input_tokens INTEGER NOT NULL,
      output_tokens INTEGER NOT NULL,
      web_search_requests INTEGER NOT NULL,
      cost_usd REAL NOT NULL)''',
    '''CREATE TABLE settings(
      key TEXT PRIMARY KEY,
      value TEXT)''',
  ];

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'meal_log.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
    );
  }

  // ---------- 食事 ----------

  /// 新規は INSERT、id があれば料理を入れ替えて UPDATE
  Future<int> saveMeal(Meal meal) {
    return _db.transaction((txn) async {
      int id;
      if (meal.id != null) {
        id = meal.id!;
        await txn.update('meals', meal.toDbMap(), where: 'id = ?', whereArgs: [id]);
        await txn.delete('meal_items', where: 'meal_id = ?', whereArgs: [id]);
      } else {
        id = await txn.insert('meals', meal.toDbMap());
      }
      for (final item in meal.items) {
        await txn.insert('meal_items', item.toDbMap(id));
      }
      return id;
    });
  }

  Future<List<Meal>> mealsOn(String date) async {
    final rows = await _db.query('meals', where: 'date = ?', whereArgs: [date], orderBy: 'created_at');
    final result = <Meal>[];
    for (final r in rows) {
      final items = await _db.query('meal_items', where: 'meal_id = ?', whereArgs: [r['id']], orderBy: 'id');
      result.add(Meal.fromDbMap(r, items.map(MealItem.fromDbMap).toList()));
    }
    return result;
  }

  Future<void> deleteMeal(int id) async {
    await _db.delete('meal_items', where: 'meal_id = ?', whereArgs: [id]);
    await _db.delete('meals', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 目標 ----------

  /// その日に有効な目標（無ければ最初の目標、それも無ければ初期値）
  Future<Goal> goalOn(String date) async {
    final r = await _db.query('goals',
        where: 'start_date <= ?', whereArgs: [date], orderBy: 'start_date DESC', limit: 1);
    if (r.isNotEmpty) return Goal.fromDbMap(r.first);
    final first = await _db.query('goals', orderBy: 'start_date ASC', limit: 1);
    if (first.isNotEmpty) return Goal.fromDbMap(first.first);
    return Goal.defaults(date);
  }

  Future<void> saveGoal(Goal g) async {
    await _db.insert('goals', g.toDbMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- 体重 ----------

  Future<void> saveWeight(WeightEntry w) async {
    await _db.insert('weights', {'date': w.date, 'weight_kg': w.kg},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWeight(String date) async {
    await _db.delete('weights', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<WeightEntry>> weightsSince(String date) async {
    final rows = await _db.query('weights', where: 'date >= ?', whereArgs: [date], orderBy: 'date ASC');
    return rows.map(WeightEntry.fromDbMap).toList();
  }

  // ---------- チェーン店キャッシュ ----------

  Future<List<MealItem>?> findChain(String storeKey, String menuKey) async {
    final r = await _db.query('chain_menu_cache',
        where: 'store_key = ? AND menu_key = ?', whereArgs: [storeKey, menuKey], limit: 1);
    if (r.isEmpty) return null;
    try {
      final list = jsonDecode(r.first['items_json'] as String) as List;
      return list.whereType<Map>().map((e) => MealItem.fromJson(e.cast<String, dynamic>())).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveChain(String storeKey, String menuKey, String displayName, List<MealItem> items) async {
    await _db.insert(
      'chain_menu_cache',
      {
        'store_key': storeKey,
        'menu_key': menuKey,
        'display_name': displayName,
        'items_json': jsonEncode(items.map((e) => e.toJson()).toList()),
        'source_url': items.isEmpty ? null : items.first.sourceUrl,
        'fetched_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> chainCacheCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM chain_menu_cache');
    return (r.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<void> clearChainCache() async {
    await _db.delete('chain_menu_cache');
  }

  // ---------- API 利用量 ----------

  Future<void> addUsage({
    required String model,
    required String purpose,
    required int inputTokens,
    required int outputTokens,
    required int webSearches,
    required double costUsd,
  }) async {
    await _db.insert('api_usage', {
      'timestamp': DateTime.now().toIso8601String(),
      'model': model,
      'purpose': purpose,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'web_search_requests': webSearches,
      'cost_usd': costUsd,
    });
  }

  /// yyyy-MM の合計
  Future<UsageSummary> usageForMonth(String yearMonth) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(input_tokens),0) AS i, COALESCE(SUM(output_tokens),0) AS o, '
      'COALESCE(SUM(web_search_requests),0) AS w, COALESCE(SUM(cost_usd),0) AS c '
      'FROM api_usage WHERE timestamp LIKE ?',
      ['$yearMonth%'],
    );
    final m = r.first;
    return UsageSummary(
      requests: (m['n'] as num?)?.toInt() ?? 0,
      inputTokens: (m['i'] as num?)?.toInt() ?? 0,
      outputTokens: (m['o'] as num?)?.toInt() ?? 0,
      webSearches: (m['w'] as num?)?.toInt() ?? 0,
      usd: (m['c'] as num?)?.toDouble() ?? 0,
    );
  }

  // ---------- 設定 ----------

  Future<Map<String, String>> allSettings() async {
    final rows = await _db.query('settings');
    return {
      for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
    };
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- エクスポート / インポート ----------

  Future<Map<String, dynamic>> exportAll() async {
    final tables = <String, dynamic>{};
    for (final t in _tables) {
      tables[t] = await _db.query(t);
    }
    return {
      'app': 'meal_log',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': tables,
    };
  }

  /// 既存データをすべて置き換える
  Future<void> importAll(Map<String, dynamic> data) async {
    final tables = data['tables'];
    if (data['app'] != 'meal_log' || tables is! Map) {
      throw const FormatException('このアプリのバックアップデータではありません');
    }
    final Map tableMap = tables;
    await _db.transaction((txn) async {
      for (final t in _tables) {
        await txn.delete(t);
      }
      for (final t in _tables.reversed) {
        final rows = tableMap[t];
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is Map) {
            await txn.insert(t, row.cast<String, Object?>());
          }
        }
      }
    });
  }
}
