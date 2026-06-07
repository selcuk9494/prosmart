import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/config.dart';
import 'auth_models.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  static const _tokenKey = 'auth.token';
  static const _userIdKey = 'auth.userId';
  static const _displayNameKey = 'auth.displayName';
  static const _roleKey = 'auth.role';
  static const _branchIdKey = 'auth.branchId';

  @override
  Future<AuthSession?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      return null;
    }

    final role = _parseRole(prefs.getString(_roleKey));
    final userId = prefs.getString(_userIdKey) ?? 'unknown';
    final displayName = prefs.getString(_displayNameKey) ?? 'Kullanıcı';
    final branchId = prefs.getString(_branchIdKey);

    return AuthSession(
      accessToken: token,
      userId: userId,
      displayName: displayName,
      role: role,
      branchId: branchId,
    );
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (AppConfig.hasApi) {
        try {
          final dio = Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl.trim(),
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
            ),
          );

          final res = await dio.post<Map<String, dynamic>>(
            '/auth/login',
            data: {
              'username': username,
              'password': password,
            },
          );

          final data = res.data;
          if (data == null) {
            throw StateError('Boş yanıt');
          }

          final token = (data['accessToken'] ?? data['token'])?.toString();
          if (token == null || token.isEmpty) {
            throw StateError('Token alınamadı');
          }

          final role = _parseRole(data['role']?.toString());
          final session = AuthSession(
            accessToken: token,
            userId: (data['userId'] ?? data['id'] ?? username).toString(),
            displayName:
                (data['displayName'] ?? data['name'] ?? username).toString(),
            role: role,
            branchId: data['branchId']?.toString(),
          );

          await _persistSession(session);
          return session;
        } on DioException catch (e) {
          final base = AppConfig.apiBaseUrl.trim();
          throw StateError(
            'API bağlantı hatası: $base\n'
            'Detay: ${e.message ?? e.type.name}\n'
            'Demo girişi kullanabilir veya API_BASE_URL ayarını kontrol edebilirsiniz.',
          );
        }
      }

      final session = _buildDemoSession(username);
      await _persistSession(session);
      return session;
    });
  }

  Future<void> loginDemo({
    required String username,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = _buildDemoSession(username);
      await _persistSession(session);
      return session;
    });
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_branchIdKey);
    state = const AsyncData(null);
  }

  UserRole _parseRole(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    return switch (normalized) {
      'manager' || 'admin' || 'yonetici' => UserRole.manager,
      'accounting' || 'muhasebe' => UserRole.accounting,
      'branchuser' || 'branch' || 'sube' => UserRole.branchUser,
      _ => UserRole.branchUser,
    };
  }

  AuthSession _buildDemoSession(String username) {
    final trimmed = username.trim();
    final role = switch (trimmed.toLowerCase()) {
      'admin' => UserRole.manager,
      'yonetici' => UserRole.manager,
      'muhasebe' => UserRole.accounting,
      _ => UserRole.branchUser,
    };

    return AuthSession(
      accessToken: 'dev-token-${DateTime.now().millisecondsSinceEpoch}',
      userId: trimmed.isEmpty ? 'user' : trimmed,
      displayName: trimmed.isEmpty ? 'Kullanıcı' : trimmed,
      role: role,
      branchId: role == UserRole.branchUser ? 'branch-1' : null,
    );
  }

  Future<void> _persistSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.accessToken);
    await prefs.setString(_userIdKey, session.userId);
    await prefs.setString(_displayNameKey, session.displayName);
    await prefs.setString(_roleKey, session.role.name);
    if (session.branchId != null) {
      await prefs.setString(_branchIdKey, session.branchId!);
    } else {
      await prefs.remove(_branchIdKey);
    }
  }
}
