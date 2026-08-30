import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/auth_repository.dart';
import '../../data/auth_local_source.dart';
import '../../domain/auth_state.dart';
import '../../domain/user_model.dart';
import '../../../../core/network/api_exceptions.dart';

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(authRepositoryProvider),
    ref.read(authLocalSourceProvider),
  );
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final AuthLocalSource _authLocalSource;

  AuthNotifier(this._authRepository, this._authLocalSource)
      : super(const AuthLoading());

  Future<void> checkAuth() async {
    state = const AuthLoading();
    try {
      final token = await _authLocalSource.getAccessToken();
      if (token == null || token.isEmpty) {
        state = const AuthUnauthenticated();
        return;
      }

      final refreshToken = await _authLocalSource.getRefreshToken();
      if (refreshToken != null) {
        try {
          final response =
              await _authRepository.refreshToken(refreshToken);
          final newAccessToken = response['access_token'] as String;
          final newRefreshToken = response['refresh_token'] as String;
          final userData = response['user'] as Map<String, dynamic>;

          await _authLocalSource.saveTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
          );

          state = AuthAuthenticated(
            user: UserModel.fromJson(userData),
            token: newAccessToken,
          );
        } catch (_) {
          await _authLocalSource.clearTokens();
          state = const AuthUnauthenticated();
        }
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (e) {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final response = await _authRepository.login(
        email: email,
        password: password,
      );

      final accessToken = response['access_token'] as String;
      final refreshToken = response['refresh_token'] as String;
      final userData = response['user'] as Map<String, dynamic>;

      await _authLocalSource.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      state = AuthAuthenticated(
        user: UserModel.fromJson(userData),
        token: accessToken,
      );
    } on ApiException catch (e) {
      state = AuthError(message: e.message);
    } catch (e) {
      state = AuthError(message: e.toString());
    }
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final response = await _authRepository.register(
        username: username,
        email: email,
        password: password,
      );

      final accessToken = response['access_token'] as String;
      final refreshToken = response['refresh_token'] as String;
      final userData = response['user'] as Map<String, dynamic>;

      await _authLocalSource.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      state = AuthAuthenticated(
        user: UserModel.fromJson(userData),
        token: accessToken,
      );
    } on ApiException catch (e) {
      state = AuthError(message: e.message);
    } catch (e) {
      state = AuthError(message: e.toString());
    }
  }

  Future<void> logout() async {
    await _authLocalSource.clearTokens();
    state = const AuthUnauthenticated();
  }

  /// Supprime le compte sur le serveur puis ferme la session locale. Si le
  /// serveur refuse, la session reste ouverte et l'erreur remonte a
  /// l'appelant, qui l'affiche.
  Future<void> deleteAccount() async {
    try {
      await _authRepository.deleteAccount();
    } on ApiException catch (e) {
      // 404 : le compte a deja ete supprime (par un admin, ou depuis un
      // autre appareil). 401 : la session ne peut plus etre prolongee, le
      // refresh token est parti avec le compte. Dans les deux cas il n'y a
      // plus rien a garder localement.
      if (e.statusCode != 404 && e.statusCode != 401) rethrow;
    }
    await _authLocalSource.clearTokens();
    state = const AuthUnauthenticated();
  }
}
