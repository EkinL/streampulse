import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/feedback_type.dart';

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepository(ref.read(dioProvider));
});

class FeedbackRepository {
  final Dio _dio;

  FeedbackRepository(this._dio);

  /// Reports a bug or a suggestion (`POST /feedback`). `appVersion` and
  /// `platform` default to the running build so a report can be tied to the
  /// exact version it was filed against (Ce3.4.3).
  Future<void> submitFeedback({
    required FeedbackType type,
    required String message,
    String? appVersion,
    String? platform,
  }) async {
    try {
      await _dio.post(
        ApiEndpoints.feedback,
        data: {
          'type': type.apiValue,
          'message': message,
          if ((appVersion ?? _cachedAppVersion) != null)
            'app_version': appVersion ?? _cachedAppVersion,
          'platform': platform ?? _platformName(),
        },
      );
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}

String? _cachedAppVersion;

/// Reads the running build's version once and caches it: `PackageInfo`
/// touches platform channels, no need to pay that cost on every submission.
Future<String?> loadAppVersion() async {
  if (_cachedAppVersion != null) return _cachedAppVersion;
  try {
    final info = await PackageInfo.fromPlatform();
    // On web, an unreachable `version.json` resolves to an empty string
    // rather than throwing - treat that the same as "unknown".
    _cachedAppVersion = info.version.isEmpty ? null : info.version;
  } catch (_) {
    // Best-effort: a missing version shouldn't block sending feedback.
  }
  return _cachedAppVersion;
}

String _platformName() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return Platform.operatingSystem;
}
