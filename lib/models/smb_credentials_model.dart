/// Non-secret SMB credentials.
///
/// Password is stored separately in flutter_secure_storage (Android Keystore)
/// and accessed via SmbCredentialsRepository — never put it in this model.
class SmbCredentialsModel {
  final String host;
  final String share;
  final String subdirectory;
  final String username;
  final String domain;
  final bool enabled;

  const SmbCredentialsModel({
    required this.host,
    required this.share,
    this.subdirectory = 'idastation_saves',
    required this.username,
    this.domain = 'WORKGROUP',
    this.enabled = true,
  });

  /// Builds from a SQLite row (Map). Returns null if any required field is missing.
  static SmbCredentialsModel? fromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final host = row['host']?.toString();
    final share = row['share']?.toString();
    final username = row['username']?.toString();
    if (host == null || host.isEmpty) return null;
    if (share == null || share.isEmpty) return null;
    if (username == null || username.isEmpty) return null;
    return SmbCredentialsModel(
      host: host,
      share: share,
      subdirectory:
          (row['subdirectory']?.toString().isNotEmpty == true)
              ? row['subdirectory'].toString()
              : 'idastation_saves',
      username: username,
      domain:
          (row['domain']?.toString().isNotEmpty == true)
              ? row['domain'].toString()
              : 'WORKGROUP',
      enabled: (row['enabled'] as int? ?? 1) == 1,
    );
  }

  SmbCredentialsModel copyWith({
    String? host,
    String? share,
    String? subdirectory,
    String? username,
    String? domain,
    bool? enabled,
  }) =>
      SmbCredentialsModel(
        host: host ?? this.host,
        share: share ?? this.share,
        subdirectory: subdirectory ?? this.subdirectory,
        username: username ?? this.username,
        domain: domain ?? this.domain,
        enabled: enabled ?? this.enabled,
      );
}
