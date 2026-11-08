import 'data/app_db.dart';
import 'data/app_settings.dart';
import 'services/claude_client.dart';
import 'services/image_service.dart';
import 'services/key_store.dart';
import 'services/nutrition_service.dart';

/// アプリ全体で共有するサービス
class AppServices {
  AppServices._({
    required this.db,
    required this.settings,
    required this.keys,
    required this.images,
    required this.nutrition,
  });

  final AppDb db;
  final AppSettings settings;
  final KeyStore keys;
  final ImageService images;
  final NutritionService nutrition;

  static late AppServices I;

  static Future<void> init() async {
    final db = AppDb();
    await db.open();
    final settings = await AppSettings.load(db);
    final keys = KeyStore();
    final claude = ClaudeClient();
    I = AppServices._(
      db: db,
      settings: settings,
      keys: keys,
      images: ImageService(),
      nutrition: NutritionService(claude: claude, db: db, settings: settings, keys: keys),
    );
  }
}
