import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/search_system_helper.dart';

void main() {
  // Required so rootBundle.loadString works in test environment.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'returns a SystemModel with id="search" and folderName="search"',
    () async {
      final sys = await SearchSystemHelper.getSearchSystemModel();
      expect(sys.id, 'search');
      expect(sys.folderName, 'search');
    },
  );

  test('uses indigo accent colors from the JSON', () async {
    final sys = await SearchSystemHelper.getSearchSystemModel();
    expect(sys.color1, '#5C6BC0');
    expect(sys.color2, '#9FA8DA');
  });

  test('caches the SystemModel after first load', () async {
    final a = await SearchSystemHelper.getSearchSystemModel();
    final b = await SearchSystemHelper.getSearchSystemModel();
    // Without a context, the helper returns the cached instance directly.
    expect(identical(a, b), isTrue);
  });

  test('falls back to JSON name when no context is given', () async {
    final sys = await SearchSystemHelper.getSearchSystemModel();
    expect(sys.realName, 'Search');
  });
}
