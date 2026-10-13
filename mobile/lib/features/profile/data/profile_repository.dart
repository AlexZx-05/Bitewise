import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        throw const FoodScanApiException('The server returned an empty profile.');
      }
      return Profile.fromJson(data);
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }

  Future<Profile> saveGoal(String goal) async {
    try {
      final response = await _client.put<Map<String, dynamic>>(
        '/api/v1/me/profile',
        data: {'goal': goal},
      );
      final data = response.data;
      if (data == null) {
        throw const FoodScanApiException('The server returned an empty profile.');
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
        return const FoodScanApiException(
          'The FoodScan API took too long to respond. The AI provider may be busy; please retry in a moment.',
        );
      }
      if (error.type == DioExceptionType.sendTimeout) {
        return const FoodScanApiException(
          'Uploading the photos took too long. Try fewer or smaller images.',
        );
      }
      return const FoodScanApiException(
        'Could not connect to the FoodScan API. Check that the backend is running, then retry.',
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
    return FoodScanApiException('The FoodScan API returned an error ($status).');
  }

  @override
  String toString() => message;
}
