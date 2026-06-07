import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'config.dart';

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = AppConfig.apiBaseUrl.trim();
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final session = ref.read(authControllerProvider).asData?.value;
        final token = session?.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) {
        final status = e.response?.statusCode;
        final path = e.requestOptions.path;
        if (status == 401 &&
            !path.startsWith('/auth/login') &&
            !path.startsWith('/api/TokenAuth/Authenticate')) {
          final session = ref.read(authControllerProvider).asData?.value;
          if (session != null) {
            unawaited(ref.read(authControllerProvider.notifier).logout());
          }
        }
        handler.next(e);
      },
    ),
  );

  return dio;
});
