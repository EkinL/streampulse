import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/constants.dart';
import '../storage/secure_storage.dart';
import 'api_endpoints.dart';

final sessionRefresherProvider = Provider<SessionRefresher>((ref) {
  return SessionRefresher(
      AppConstants.apiBaseUrl, ref.read(secureStorageProvider));
});

/// Renouvelle la session (access + refresh token) et la sauvegarde.
///
/// Un seul chemin de renouvellement pour toute l'app : l'intercepteur Dio
/// (sur un 401) et le chat de live, dont la poignée de main WebSocket ne
/// passe pas par Dio. Un seul renouvellement à la fois : le serveur révoque
/// l'ancien refresh token à chaque appel, deux renouvellements concurrents
/// feraient échouer le second et déconnecteraient l'utilisateur.
class SessionRefresher {
  /// Marge avant l'expiration : le temps d'ouvrir la connexion, sans compter
  /// sur des horloges parfaitement alignées entre le téléphone et le serveur.
  static const Duration expiryMargin = Duration(seconds: 30);

  final String _baseUrl;
  final SecureStorageService _secureStorage;
  Future<String?>? _inFlight;

  SessionRefresher(this._baseUrl, this._secureStorage);

  /// L'access token courant, renouvelé d'abord s'il est expiré ou sur le
  /// point de l'être. Null sans session.
  Future<String?> validAccessToken() async {
    final token = await _secureStorage.getAccessToken();
    if (token == null) return null;
    final expiresAt = jwtExpiry(token);
    if (expiresAt == null ||
        expiresAt.isAfter(DateTime.now().add(expiryMargin))) {
      return token;
    }
    return refresh();
  }

  /// Échange le refresh token stocké contre une nouvelle paire de jetons et
  /// retourne le nouvel access token. Null si la session est perdue : les
  /// jetons sont alors effacés, il faut se reconnecter.
  Future<String?> refresh() {
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  Future<String?> _refresh() async {
    final refreshToken = await _secureStorage.getRefreshToken();
    if (refreshToken == null) return null;
    try {
      // Client nu, sans intercepteur : celui du client principal
      // relancerait ce renouvellement sur un 401 de /auth/refresh.
      final response = await Dio(BaseOptions(baseUrl: _baseUrl)).post(
        ApiEndpoints.authRefresh,
        data: {'refresh_token': refreshToken},
      );
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;
      final accessToken = data['access_token'] as String;
      await _secureStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: data['refresh_token'] as String,
      );
      return accessToken;
    } on DioException catch (e) {
      debugPrint('Session refresh failed: $e');
      await _secureStorage.clearTokens();
      return null;
    }
  }

  /// Date d'expiration d'un JWT (claim `exp`), null si le jeton est illisible.
  static DateTime? jwtExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000,
          isUtc: true);
    } catch (_) {
      return null;
    }
  }
}
