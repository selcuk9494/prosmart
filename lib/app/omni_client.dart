import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';

final omniClientProvider = Provider<OmniClient>((ref) {
  return OmniClient(
    Dio(
      BaseOptions(
        baseUrl: AppConfig.omniApiBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 30),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    ),
  );
});

class OmniClient {
  const OmniClient(this._dio);

  final Dio _dio;

  Future<OmniAuthSession> authenticate({
    required String username,
    required String password,
    String? tenancyName,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/TokenAuth/Authenticate',
      data: {
        'usernameOrEmailAddress': username,
        'userNameOrEmailAddress': username,
        'password': password,
        'rememberClient': true,
        if (tenancyName != null && tenancyName.trim().isNotEmpty)
          'tenancyName': tenancyName.trim(),
      },
    );
    final data = _unwrap(res.data);
    return OmniAuthSession(
      accessToken: (data['accessToken'] ?? '').toString(),
      encryptedAccessToken: data['encryptedAccessToken']?.toString(),
      expireInSeconds: (data['expireInSeconds'] as num?)?.toInt(),
      userId: (data['userId'] as num?)?.toInt(),
    );
  }

  Future<dynamic> getAppService({
    required String service,
    required String method,
    Map<String, dynamic>? query,
    String? accessToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/services/app/$service/$method',
      queryParameters: query,
      options: _authOptions(accessToken),
    );
    return _unwrap(res.data);
  }

  Future<dynamic> postAppService({
    required String service,
    required String method,
    Object? data,
    String? accessToken,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/services/app/$service/$method',
      data: data,
      options: _authOptions(accessToken),
    );
    return _unwrap(res.data);
  }

  Options? _authOptions(String? accessToken) {
    final token = accessToken?.trim();
    if (token == null || token.isEmpty) return null;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic>? response) {
    final body = response ?? const {};
    final success = body['success'];
    if (success == false) {
      final error = body['error'];
      if (error is Map && error['message'] != null) {
        throw StateError(error['message'].toString());
      }
      throw StateError('Omni API yanıtı başarısız.');
    }
    final result = body['result'];
    if (result is Map<String, dynamic>) return result;
    return {'value': result};
  }
}

class OmniAuthSession {
  const OmniAuthSession({
    required this.accessToken,
    this.encryptedAccessToken,
    this.expireInSeconds,
    this.userId,
  });

  final String accessToken;
  final String? encryptedAccessToken;
  final int? expireInSeconds;
  final int? userId;
}
