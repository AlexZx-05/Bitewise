import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import 'profile.dart';

final apiClientProvider = Provider<Dio>((ref) => createApiClient());

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);

final profileProvider = FutureProvider<Profile>(
  (ref) => ref.watch(profileRepositoryProvider).getProfile(),
);

class ProfileRepository {
  const ProfileRepository(this._client);

  final Dio _client;

  Future<Profile> getProfile() async {
    try {
      final response = await _client.get<Map<String, dynamic>>('/api/v1/me');
      final data = response.data;
      if (data == null) {
        throw const FoodScanApiException(
          'The server returned an empty profile.',
        );
      }
      return Profile.fromJson(data);
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }

  Future<Profile> saveGoal(String goal) async {
    return saveDetails({'goal': goal});
  }

  Future<Profile> saveDetails(Map<String, dynamic> details) async {
    try {
      final response = await _client.put<Map<String, dynamic>>(
        '/api/v1/me/profile',
        data: details,
      );
      final data = response.data;
      if (data == null) {
        throw const FoodScanApiException(
          'The server returned an empty profile.',
        );
      }
      return Profile.fromJson(data);
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }
}

class FoodScanApiException implements Exception {
  const FoodScanApiException(this.message, {this.isQuotaExceeded = false});

  final String message;
  final bool isQuotaExceeded;

  factory FoodScanApiException.fromDio(DioException error) {
    if (error.response == null) {
      if (error.type == DioExceptionType.receiveTimeout) {
        if (error.requestOptions.path == '/api/v1/me') {
          return const FoodScanApiException(
            'The FoodScan backend did not return your profile in time. '
            'Check that the backend and PostgreSQL are running, then retry.',
          );
        }
        return const FoodScanApiException(
          'The FoodScan API took too long to respond. The AI provider may be busy; please retry in a moment.',
        );
      }
      if (error.type == DioExceptionType.sendTimeout) {
        return const FoodScanApiException(
          'Uploading the photos took too long. Try fewer or smaller images.',
        );
      }
      if (error.type == DioExceptionType.connectionTimeout) {
        return FoodScanApiException(
          'FoodScan could not reach the backend at ${AppConfig.apiBaseUrl}. '
          'Make sure the backend is running, then try again.',
        );
      }
      if (error.type == DioExceptionType.connectionError) {
        return FoodScanApiException(
          'Could not reach the FoodScan backend at ${AppConfig.apiBaseUrl}. '
          'Check that it is running. If it is, check for a browser CORS or '
          'network error.',
        );
      }
      return FoodScanApiException(
        'FoodScan did not receive a response from the backend at '
        '${AppConfig.apiBaseUrl}. Check that it is running, then retry.',
      );
    }
    final status = error.response?.statusCode;
    final detail = error.response?.data;
    if (detail is Map<String, dynamic> && detail['detail'] is String) {
      final message = detail['detail'] as String;
      return FoodScanApiException(
        message,
        isQuotaExceeded:
            message.toLowerCase().contains('quota') ||
            message.toLowerCase().contains('usage limit'),
      );
    }
    return FoodScanApiException(
      'The FoodScan API returned an error ($status).',
    );
  }

  @override
  String toString() => message;
}
