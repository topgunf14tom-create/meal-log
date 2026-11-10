import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/meal_type.dart';
import '../core/nutrition.dart';
import '../core/strava_archive.dart';
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
    'inbody_results',
    'activity_days',
    'user_foods',
    'food_usage',
    'favorites',
  ];

  /// 個人DB（自分で登録した食品・ラベル読み取り・JAN）
  static const _userFoodsTable = '''CREATE TABLE user_foods(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      jan TEXT,
      kcal REAL NOT NULL,
      protein_g REAL,
      fat_g REAL,
      carbs_g REAL,
      salt_g REAL,
      unit_label TEXT NOT NULL,
      grams REAL,
      per100g INTEGER NOT NULL DEFAULT 0,
      estimated INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL)''';

  /// 食品ごとの利用履歴（候補の並び替えと、量感クラスの前回値）
  static const _foodUsageTable = '''CREATE TABLE food_usage(
      food_ref TEXT PRIMARY KEY,
      count INTEGER NOT NULL,
      last_size_class INTEGER,
      last_used TEXT NOT NULL)''';

  static const _favoritesTable = '''CREATE TABLE favorites(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      items_json TEXT NOT NULL,
      use_count INTEGER NOT NULL DEFAULT 0,
      meal_type TEXT,
      created_at TEXT NOT NULL)''';

  /// 写真の再利用（写真のハッシュ → 確定した内容）
  static const _photoHashTable = '''CREATE TABLE photo_hashes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      hash TEXT NOT NULL,
      items_json TEXT NOT NULL,
      created_at TEXT NOT NULL)''';

  static const _v5Tables = [
    _userFoodsTable,
    'CREATE INDEX idx_user_foods_jan ON user_foods(jan)',
    _foodUsageTable,
    _favoritesTable,
    _photoHashTable,
  ];

  static const _activityTable = '''CREATE TABLE activity_days(
      date TEXT PRIMARY KEY,
      steps INTEGER NOT NULL,
      walk_steps INTEGER NOT NULL,
      walk_kcal REAL NOT NULL,
      exercise_kcal REAL NOT NULL,
      exercises_json TEXT NOT NULL,
      synced_at TEXT NOT NULL)''';

  /// Strava の書き出しから取り込んだ運動（バックアップの JSON には含めない。zip から取り込み直せるため）
  static const _stravaTable = '''CREATE TABLE strava_activities(
      id TEXT PRIMARY KEY,
      start_ms INTEGER NOT NULL,
      kind TEXT NOT NULL,
      type_label TEXT NOT NULL,
      name TEXT NOT NULL,
      elapsed_s REAL NOT NULL,
      moving_s REAL NOT NULL,
      distance_m REAL NOT NULL,
      elev_gain_m REAL,
      avg_hr REAL,
      max_hr INTEGER,
      kcal REAL,
      max_speed REAL,
      has_route INTEGER NOT NULL,
      bests_json TEXT NOT NULL,
      detail_json TEXT NOT NULL)''';

  static const _inbodyTable = '''CREATE TABLE inbody_results(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      measured_at TEXT,
      raw TEXT NOT NULL UNIQUE,
      weight_kg REAL NOT NULL,
      smm_kg REAL NOT NULL,
      bfm_kg REAL NOT NULL,
      pbf REAL NOT NULL,
      score INTEGER NOT NULL,
      created_at TEXT NOT NULL)''';

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
      source_url TEXT,
      food_ref TEXT,
      size_class INTEGER,
      ratio REAL NOT NULL DEFAULT 1,
      detail TEXT,
      pfc_unknown INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE weights(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL UNIQUE,
      weight_kg REAL NOT NULL,
      source TEXT NOT NULL DEFAULT 'manual',
      body_fat_pct REAL)''',
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
    _inbodyTable,
    'CREATE INDEX idx_inbody_date ON inbody_results(date)',
    _activityTable,
    _stravaTable,
    'CREATE INDEX idx_strava_start ON strava_activities(start_ms)',
    ..._v5Tables,
  ];

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'meal_log.db'),
      version: 5,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(_inbodyTable);
          await db.execute('CREATE INDEX idx_inbody_date ON inbody_results(date)');
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE weights ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'");
          await db.execute('ALTER TABLE weights ADD COLUMN body_fat_pct REAL');
          await db.execute(_activityTable);
        }
        if (oldVersion < 4) {
          await db.execute(_stravaTable);
          await db.execute('CREATE INDEX idx_strava_start ON strava_activities(start_ms)');
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE meal_items ADD COLUMN food_ref TEXT');
          await db.execute('ALTER TABLE meal_items ADD COLUMN size_class INTEGER');
          await db.execute('ALTER TABLE meal_items ADD COLUMN ratio REAL NOT NULL DEFAULT 1');
          await db.execute('ALTER TABLE meal_items ADD COLUMN detail TEXT');
          await db.execute('ALTER TABLE meal_items ADD COLUMN pfc_unknown INTEGER NOT NULL DEFAULT 0');
          for (final sql in _v5Tables) {
            await db.execute(sql);
          }
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

  /// よく食べるもの：[since] 以降に記録した料理を名前ごとにまとめ、回数の多い順。値は一番新しい記録のもの
  Future<List<FrequentItem>> frequentItems({required String since, int limit = 40}) async {
    final rows = await _db.rawQuery('''
      SELECT i.*, c.cnt AS cnt, c.last_date AS last_date FROM meal_items i
      JOIN (
        SELECT i2.name AS name, COUNT(*) AS cnt, MAX(i2.id) AS last_id, MAX(m2.date) AS last_date
        FROM meal_items i2 JOIN meals m2 ON m2.id = i2.meal_id
        WHERE m2.date >= ? AND TRIM(i2.name) != ''
        GROUP BY i2.name
      ) c ON c.last_id = i.id
      ORDER BY c.cnt DESC, c.last_date DESC
      LIMIT ?''', [since, limit]);
    return rows
        .map((r) => FrequentItem(
              item: MealItem.fromDbMap(r),
              count: (r['cnt'] as num).toInt(),
              lastDate: r['last_date'] as String? ?? '',
            ))
        .toList();
  }

  /// [type] の食事のうち、[onOrBefore] 以前で一番新しいもの（[excludeId] は除く）
  Future<Meal?> lastMealOfType(MealType type, String onOrBefore, {int? excludeId}) async {
    final rows = await _db.query(
      'meals',
      where: excludeId == null ? 'meal_type = ? AND date <= ?' : 'meal_type = ? AND date <= ? AND id != ?',
      whereArgs: [type.name, onOrBefore, if (excludeId != null) excludeId],
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final items = await _db.query('meal_items', where: 'meal_id = ?', whereArgs: [rows.first['id']], orderBy: 'id');
    return Meal.fromDbMap(rows.first, items.map(MealItem.fromDbMap).toList());
  }

  /// 日ごとの摂取合計（記録のある日だけ）
  Future<Map<String, Pfc>> dailyTotals(String from, String to) async {
    final rows = await _db.rawQuery('''
      SELECT m.date AS date, SUM(i.kcal) AS kcal, SUM(i.protein_g) AS p, SUM(i.fat_g) AS f, SUM(i.carbs_g) AS c
      FROM meals m JOIN meal_items i ON i.meal_id = m.id
      WHERE m.date >= ? AND m.date <= ?
      GROUP BY m.date''', [from, to]);
    return {
      for (final r in rows)
        r['date'] as String: Pfc(
          (r['kcal'] as num?)?.toDouble() ?? 0,
          (r['p'] as num?)?.toDouble() ?? 0,
          (r['f'] as num?)?.toDouble() ?? 0,
          (r['c'] as num?)?.toDouble() ?? 0,
        ),
    };
  }

  /// その日に記録した食事区分
  Future<Set<MealType>> mealTypesOn(String date) async {
    final rows = await _db.query('meals', columns: ['meal_type'], where: 'date = ?', whereArgs: [date]);
    return rows.map((r) => mealTypeFromName(r['meal_type'] as String? ?? '')).toSet();
  }

  Future<List<ActivityDay>> activitiesBetween(String from, String to) async {
    final rows = await _db.query('activity_days',
        where: 'date >= ? AND date <= ?', whereArgs: [from, to], orderBy: 'date ASC');
    return rows.map(ActivityDay.fromDbMap).toList();
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
    await _db.insert(
        'weights', {'date': w.date, 'weight_kg': w.kg, 'source': w.source, 'body_fat_pct': w.bodyFatPct},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// ヘルスコネクトの値を取り込む。手入力・InBody QR の記録がある日は上書きしない。保存したら true
  Future<bool> importHealthWeight(WeightEntry w) async {
    final r = await _db.query('weights', where: 'date = ?', whereArgs: [w.date], limit: 1);
    if (r.isNotEmpty) {
      final cur = WeightEntry.fromDbMap(r.first);
      if (!cur.isAuto) return false;
      if (cur.kg == w.kg && cur.bodyFatPct == w.bodyFatPct) return false;
    }
    await saveWeight(w);
    return true;
  }

  /// その日以前で最も新しい体重
  Future<WeightEntry?> weightOnOrBefore(String date) async {
    final r = await _db.query('weights', where: 'date <= ?', whereArgs: [date], orderBy: 'date DESC', limit: 1);
    return r.isEmpty ? null : WeightEntry.fromDbMap(r.first);
  }

  Future<void> deleteWeight(String date) async {
    await _db.delete('weights', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<WeightEntry>> weightsSince(String date) async {
    final rows = await _db.query('weights', where: 'date >= ?', whereArgs: [date], orderBy: 'date ASC');
    return rows.map(WeightEntry.fromDbMap).toList();
  }

  // ---------- InBody ----------

  /// 同じ QR は1件だけ（再度読み取ったら日付などを上書き）。保存した id を返す
  Future<int> saveInBody(InBodyRecord rec) async {
    return _db.transaction((txn) async {
      final existing = await txn.query('inbody_results', columns: ['id'], where: 'raw = ?', whereArgs: [rec.raw]);
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        await txn.update('inbody_results', rec.toDbMap(), where: 'id = ?', whereArgs: [id]);
        return id;
      }
      return txn.insert('inbody_results', rec.toDbMap());
    });
  }

  Future<InBodyRecord?> findInBodyByRaw(String raw) async {
    final r = await _db.query('inbody_results', where: 'raw = ?', whereArgs: [raw], limit: 1);
    return r.isEmpty ? null : InBodyRecord.fromDbMap(r.first);
  }

  /// 新しい順
  Future<List<InBodyRecord>> inbodyResults() async {
    final rows = await _db.query('inbody_results', orderBy: 'date DESC, measured_at DESC, id DESC');
    return rows.map(InBodyRecord.fromDbMap).toList();
  }

  Future<void> deleteInBody(int id) async {
    await _db.delete('inbody_results', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 活動（ヘルスコネクト） ----------

  Future<void> saveActivity(ActivityDay a) async {
    await _db.insert('activity_days', a.toDbMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ActivityDay?> activityOn(String date) async {
    final r = await _db.query('activity_days', where: 'date = ?', whereArgs: [date], limit: 1);
    return r.isEmpty ? null : ActivityDay.fromDbMap(r.first);
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

  // ---------- 個人DB・利用履歴・いつもの・写真の再利用 ----------

  Future<List<UserFood>> userFoods() async {
    final rows = await _db.query('user_foods', orderBy: 'id DESC');
    return rows.map(UserFood.fromDbMap).toList();
  }

  /// 同じ JAN があれば上書き。保存した id を返す
  Future<int> saveUserFood(UserFood f) async {
    final row = {...f.toDbMap(), 'created_at': DateTime.now().toIso8601String()};
    if (f.id != null) {
      await _db.update('user_foods', row, where: 'id = ?', whereArgs: [f.id]);
      return f.id!;
    }
    if (f.jan != null && f.jan!.isNotEmpty) {
      final ex = await _db.query('user_foods', columns: ['id'], where: 'jan = ?', whereArgs: [f.jan], limit: 1);
      if (ex.isNotEmpty) {
        final id = ex.first['id'] as int;
        await _db.update('user_foods', row, where: 'id = ?', whereArgs: [id]);
        return id;
      }
    }
    return _db.insert('user_foods', row);
  }

  Future<void> deleteUserFood(int id) async {
    await _db.delete('user_foods', where: 'id = ?', whereArgs: [id]);
  }

  /// food_ref → (回数, 前回の量感クラス)
  Future<Map<String, ({int count, int? lastClass})>> foodUsage() async {
    final rows = await _db.query('food_usage');
    return {
      for (final r in rows)
        r['food_ref'] as String: (
          count: (r['count'] as num?)?.toInt() ?? 0,
          lastClass: (r['last_size_class'] as num?)?.toInt(),
        ),
    };
  }

  /// 記録した食品の利用回数を1増やし、量感クラスを覚える
  Future<void> bumpFoodUsage(String ref, int? sizeClass) async {
    final now = DateTime.now().toIso8601String();
    final n = await _db.rawUpdate(
      'UPDATE food_usage SET count = count + 1, last_size_class = COALESCE(?, last_size_class), last_used = ? WHERE food_ref = ?',
      [sizeClass, now, ref],
    );
    if (n == 0) {
      await _db.insert('food_usage', {'food_ref': ref, 'count': 1, 'last_size_class': sizeClass, 'last_used': now});
    }
  }

  Future<List<Favorite>> favorites() async {
    final rows = await _db.query('favorites', orderBy: 'use_count DESC, id DESC');
    return rows.map(Favorite.fromDbMap).toList();
  }

  Future<int> saveFavorite(Favorite f) =>
      _db.insert('favorites', {...f.toDbMap(), 'created_at': DateTime.now().toIso8601String()});

  Future<void> bumpFavorite(int id) async {
    await _db.rawUpdate('UPDATE favorites SET use_count = use_count + 1 WHERE id = ?', [id]);
  }

  Future<void> deleteFavorite(int id) async {
    await _db.delete('favorites', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> savePhotoHash(String hash, List<MealItem> items) async {
    await _db.insert('photo_hashes', {
      'hash': hash,
      'items_json': jsonEncode(items.map((e) => e.toJson()).toList()),
      'created_at': DateTime.now().toIso8601String(),
    });
    // 古いものは300件を超えたら消す
    await _db.rawDelete(
        'DELETE FROM photo_hashes WHERE id NOT IN (SELECT id FROM photo_hashes ORDER BY id DESC LIMIT 300)');
  }

  /// 新しい順に (hash, items)
  Future<List<(String, List<MealItem>)>> photoHashes() async {
    final rows = await _db.query('photo_hashes', orderBy: 'id DESC', limit: 300);
    final out = <(String, List<MealItem>)>[];
    for (final r in rows) {
      try {
        final list = jsonDecode(r['items_json'] as String) as List;
        out.add((
          r['hash'] as String,
          list.whereType<Map>().map((e) => MealItem.fromJson(e.cast<String, dynamic>())).toList(),
        ));
      } catch (_) {}
    }
    return out;
  }

  // ---------- Strava ----------

  /// 同じ ID は上書き。件数を返す
  Future<int> saveStravaActivities(List<Map<String, Object?>> rows) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        batch.insert('strava_activities', r, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    return rows.length;
  }

  /// 一覧用（点・スプリットは読まない）。新しい順
  Future<List<StravaActivity>> stravaActivities({DateTime? from}) async {
    final rows = await _db.query(
      'strava_activities',
      columns: [
        'id', 'start_ms', 'kind', 'type_label', 'name', 'elapsed_s', 'moving_s', 'distance_m',
        'elev_gain_m', 'avg_hr', 'max_hr', 'kcal', 'max_speed', 'has_route',
      ],
      where: from == null ? null : 'start_ms >= ?',
      whereArgs: from == null ? null : [from.millisecondsSinceEpoch],
      orderBy: 'start_ms DESC',
    );
    return rows.map((r) => StravaActivity.fromDbMap(r, withDetail: false)).toList();
  }

  Future<StravaActivity?> stravaActivity(String id) async {
    final r = await _db.query('strava_activities', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : StravaActivity.fromDbMap(r.first);
  }

  /// ベスト記録の一覧用（ランニングのベストだけ読む）
  Future<List<StravaActivity>> stravaRunsWithBests() async {
    final rows = await _db.query(
      'strava_activities',
      columns: ['id', 'start_ms', 'kind', 'type_label', 'name', 'elapsed_s', 'moving_s', 'distance_m', 'bests_json'],
      where: "kind = 'running'",
      orderBy: 'start_ms DESC',
    );
    return rows.map((r) => StravaActivity.fromDbMap(r, withDetail: false)).toList();
  }

  /// 直近1年で記録された最大心拍（心拍ゾーンの基準）
  Future<int?> stravaMaxHr() async {
    final since = DateTime.now().subtract(const Duration(days: 365)).millisecondsSinceEpoch;
    final r = await _db.rawQuery('SELECT MAX(max_hr) AS m FROM strava_activities WHERE start_ms >= ?', [since]);
    return (r.first['m'] as num?)?.toInt();
  }

  Future<int> stravaCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM strava_activities');
    return (r.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<void> deleteAllStrava() async {
    await _db.delete('strava_activities');
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
