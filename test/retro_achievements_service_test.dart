import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/retro_achievements_service.dart';

void main() {
  group('RetroAchievementsService', () {
    test('should return correct console ID for NES', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('nes'), 7);
    });

    test('should return correct console ID for SNES', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('snes'), 3);
    });

    test('should return correct console ID for Genesis', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('genesis'), 1);
    });

    test('should return correct console ID for PSX', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('psx'), 12);
    });

    test('should be case-insensitive', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('PSX'), 12);
      expect(RetroAchievementsService.getConsoleIdForSystem('Psx'), 12);
    });

    test('should return null for unknown system', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('unknown'), null);
    });

    test('should return null for empty string', () {
      expect(RetroAchievementsService.getConsoleIdForSystem(''), null);
    });
  });
}
