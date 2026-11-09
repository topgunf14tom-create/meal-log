import 'data/app_db.dart';
import 'data/app_settings.dart';
import 'services/activity_sync.dart';
import 'services/backup_service.dart';
import 'services/claude_client.dart';
import 'services/device_service.dart';
import 'services/health_service.dart';
import 'services/image_service.dart';
import 'services/key_store.dart';
import 'services/nutrition_service.dart';
import 'services/reminder_service.dart';

/// アプリ全体で共有するサービス
class AppServices {
  AppServices._({
    required this.db,
    required this.settings,
    required this.keys,
    required this.images,
    required this.nutrition,
    required this.health,
    required this.activity,
    required this.device,
    required this.backup,
    required this.reminders,
  });

  final AppDb db;
  final AppSettings settings;
  final KeyStore keys;
  final ImageService images;
  final NutritionService nutrition;
  final HealthService health;
  final ActivitySync activity;
  final DeviceService device;
  final BackupService backup;
  final ReminderService reminders;

  static late AppServices I;

  static Future<void> init() async {
    final db = AppDb();
    await db.open();
    final settings = await AppSettings.load(db);
    final keys = KeyStore();
    final claude = ClaudeClient();
    final health = HealthService();
    final device = DeviceService();
    I = AppServices._(
      db: db,
      settings: settings,
      keys: keys,
      images: ImageService(),
      nutrition: NutritionService(claude: claude, db: db, settings: settings, keys: keys),
      health: health,
      activity: ActivitySync(health: health, db: db, settings: settings),
      device: device,
      backup: BackupService(db: db, settings: settings, device: device),
      reminders: ReminderService(db: db, settings: settings, device: device),
    );
  }
}
