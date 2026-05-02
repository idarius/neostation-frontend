import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/config_model.dart';
import 'package:neostation/utils/app_config.dart';

void main() {
  group('AppConfig', () {
    test('should have default auth base URL', () {
      expect(AppConfig.authBaseUrl, 'https://auth.neogamelab.com');
    });

    test('should have default neoSync base URL', () {
      expect(AppConfig.neoSyncBaseUrl, 'https://neosync.neogamelab.com');
    });

    test('should have default billing base URL', () {
      expect(AppConfig.billingBaseUrl, 'https://billing.neogamelab.com');
    });

    test('should have default notify base URL', () {
      expect(AppConfig.notifyBaseUrl, 'ws://notify.neogamelab.com/ws');
    });
  });

  group('hideRecentSystem field', () {
    test('defaults to false when missing from JSON', () {
      final model = ConfigModel.fromJson(<String, dynamic>{});
      expect(model.hideRecentSystem, isFalse);
    });

    test('roundtrips through toJson with camelCase key', () {
      const original = ConfigModel(hideRecentSystem: true);
      final restored = ConfigModel.fromJson(original.toJson());
      expect(restored.hideRecentSystem, isTrue);
    });

    test('reads snake_case key (SQLite column form)', () {
      final model = ConfigModel.fromJson(<String, dynamic>{
        'hide_recent_system': 1,
      });
      expect(model.hideRecentSystem, isTrue);
    });

    test('copyWith updates only hideRecentSystem when specified', () {
      const base = ConfigModel(hideRecentCard: true, hideRecentSystem: false);
      final updated = base.copyWith(hideRecentSystem: true);
      expect(updated.hideRecentSystem, isTrue);
      expect(updated.hideRecentCard, isTrue);
    });
  });
}
