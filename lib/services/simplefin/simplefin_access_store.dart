import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Resolves the SimpleFIN Access URL.
///
/// Prefer [SIMPLEFIN_ACCESS_URL] in `.env` (survives reinstall if you keep the
/// project file). Fall back to keychain for a just-claimed session.
///
/// Note: Setup Tokens are one-time; store the claimed Access URL, not the
/// Setup Token.
class SimpleFinAccessStore({FlutterSecureStorage? storage}) {
  static const envAccessUrlKey = 'SIMPLEFIN_ACCESS_URL';
  static const _keychainAccessUrlKey = 'simplefin_access_url';

  final FlutterSecureStorage _storage =
      storage ??
      const FlutterSecureStorage(
        // Legacy macOS keychain — avoids Data Protection Keychain
        // entitlement / provisioning issues during local debug runs.
        mOptions: MacOsOptions(usesDataProtectionKeychain: false),
      );

  Future<void> save(Uri accessUrl) async {
    await _storage.write(
      key: _keychainAccessUrlKey,
      value: accessUrl.toString(),
    );
  }

  Future<Uri?> read() async {
    final fromEnv = _uriFromEnv();
    if (fromEnv != null) return fromEnv;

    final value = await _storage.read(key: _keychainAccessUrlKey);
    if (value == null || value.isEmpty) return null;
    return Uri.tryParse(value);
  }

  /// True when `.env` supplies the Access URL (reinstall-safe for this project).
  bool get isConfiguredInEnv => _uriFromEnv() != null;

  Future<void> clear() => _storage.delete(key: _keychainAccessUrlKey);

  Future<bool> get isConnected async => await read() != null;

  Uri? _uriFromEnv() {
    final value = dotenv.env[envAccessUrlKey]?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return null;
    return uri;
  }
}
