import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/save_discovery_service.dart';

void main() {
  test('SaveDiscoveryService is a singleton', () {
    final a = SaveDiscoveryService.instance;
    final b = SaveDiscoveryService.instance;
    expect(identical(a, b), isTrue);
  });
}
