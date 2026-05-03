import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/smb_credentials_model.dart';

/// Repository for SMB credentials.
///
/// Splits storage between SQLite (non-secret config) and flutter_secure_storage
/// (password, encrypted via Android Keystore).
class SmbCredentialsRepository {
  static const _passwordKey = 'smb_password';

  final FlutterSecureStorage _secureStorage;

  SmbCredentialsRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Loads the non-secret config from SQLite. Returns null if not configured.
  Future<SmbCredentialsModel?> loadConfig() async {
    final row = await SqliteService.getSmbCredentials();
    return SmbCredentialsModel.fromRow(row);
  }

  /// Loads the password from secure storage. Returns null if absent.
  Future<String?> loadPassword() async {
    return _secureStorage.read(key: _passwordKey);
  }

  /// Saves both the non-secret config (SQLite) and the password (secure storage).
  /// Atomic from the user's perspective: both are written before returning.
  Future<void> save({
    required SmbCredentialsModel config,
    required String password,
  }) async {
    await SqliteService.saveSmbCredentials(
      host: config.host,
      share: config.share,
      subdirectory: config.subdirectory,
      username: config.username,
      domain: config.domain,
      enabled: config.enabled,
    );
    await _secureStorage.write(key: _passwordKey, value: password);
  }

  /// Clears both the non-secret config and the password.
  Future<void> clear() async {
    await SqliteService.clearSmbCredentials();
    await _secureStorage.delete(key: _passwordKey);
  }
}
