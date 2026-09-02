import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

final socialAuthServiceProvider = Provider<SocialAuthService>((ref) {
  return SocialAuthService();
});

/// La personne a ferme la fenetre du fournisseur : ce n'est pas une erreur,
/// on revient simplement a l'ecran de connexion sans message.
class SocialAuthCancelledException implements Exception {
  const SocialAuthCancelledException();
}

class SocialAuthException implements Exception {
  final String message;
  const SocialAuthException(this.message);
}

/// Obtient un ID token aupres du SDK Google Sign-In ou Sign in with Apple.
/// Le token part ensuite vers POST /auth/oauth, qui le verifie et ouvre la
/// session. Isole dans sa propre classe pour etre remplacable en test.
class SocialAuthService {
  /// Client IDs OAuth passes a la compilation, zero hardcoding :
  /// flutter run --dart-define=GOOGLE_CLIENT_ID=... (client iOS)
  ///             --dart-define=GOOGLE_SERVER_CLIENT_ID=... (client web).
  /// Ils viennent de la console Google Cloud et doivent aussi figurer dans
  /// GOOGLE_OAUTH_CLIENT_IDS cote backend (voir backend/.env.example).
  static const _googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const _googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  bool _googleInitialized = false;

  Future<String> getGoogleIdToken() async {
    if (_googleClientId.isEmpty && _googleServerClientId.isEmpty) {
      throw const SocialAuthException(
        'Connexion Google non configuree : compiler avec '
        '--dart-define=GOOGLE_CLIENT_ID=... et GOOGLE_SERVER_CLIENT_ID=...',
      );
    }
    final signIn = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await signIn.initialize(
        clientId: _googleClientId.isEmpty ? null : _googleClientId,
        serverClientId:
            _googleServerClientId.isEmpty ? null : _googleServerClientId,
      );
      _googleInitialized = true;
    }
    try {
      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const SocialAuthException(
            "Google n'a pas fourni d'ID token, reessayez.");
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialAuthCancelledException();
      }
      throw SocialAuthException(
          'Connexion Google impossible : ${e.description ?? e.code.name}');
    }
  }

  Future<String> getAppleIdToken() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const SocialAuthException(
            "Apple n'a pas fourni d'identity token, reessayez.");
      }
      return idToken;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SocialAuthCancelledException();
      }
      throw SocialAuthException('Connexion Apple impossible : ${e.message}');
    } on SignInWithAppleNotSupportedException {
      throw const SocialAuthException(
          'Sign in with Apple non disponible sur cet appareil.');
    }
  }
}
