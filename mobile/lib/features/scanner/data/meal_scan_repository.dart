import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/profile_repository.dart';

String todayMealDiaryKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

final mealScanRepositoryProvider = Provider<MealScanRepository>(
  (ref) => MealScanRepository(ref.watch(apiClientProvider)),
);

class UsdaFood {
  const UsdaFood({
    required this.fdcId,
    required this.description,
    this.dataType,
  });

  final int fdcId;
  final String description;
  final String? dataType;

  factory UsdaFood.fromJson(Map<String, dynamic> json) => UsdaFood(
    fdcId: json['fdc_id'] as int,
    description: json['description'] as String,
    dataType: json['data_type'] as String?,
  );
}

class MealScanResult {
  const MealScanResult({
    required this.scanId,
    required this.mealName,
    required this.mealType,
    required this.createdAt,
    required this.components,
    required this.nutritionTotals,
    required this.goalExplanation,
    required this.alternativeGuidance,
  });

  final String scanId;
  final String mealName;
  final String mealType;
  final DateTime createdAt;
  final List<Map<String, dynamic>> components;
  final Map<String, dynamic> nutritionTotals;
  final String goalExplanation;
  final String alternativeGuidance;

  factory MealScanResult.fromJson(Map<String, dynamic> json) => MealScanResult(
    scanId: json['scan_id'] as String,
    mealName: json['meal_name'] as String,
    mealType: json['meal_type'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    components: (json['components'] as List<dynamic>)
        .cast<Map<String, dynamic>>(),
    nutritionTotals: (json['nutrition_totals'] as Map<String, dynamic>),
    goalExplanation: json['goal_explanation'] as String,
    alternativeGuidance: json['alternative_guidance'] as String,
  );
}

final mealDiaryProvider = FutureProvider.family<List<MealScanResult>, String>((
  ref,
  date,
) {
  return ref.watch(mealScanRepositoryProvider).getDiary(date);
});

class MealScanRepository {
  const MealScanRepository(this._client);

  final Dio _client;

  Future<Map<String, dynamic>> extractMeal({
    required List<int> bytes,
    required String name,
    required String mimeType,
  }) async {
    try {
      final form = FormData()
        ..files.add(
          MapEntry(
            'image',
            MultipartFile.fromBytes(
              bytes,
              filename: name,
              contentType: DioMediaType.parse(mimeType),
            ),
          ),
        );
      final response = await _client.post<Map<String, dynamic>>(
        '/api/v1/scans/meals/extract',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      final extracted = response.data?['extracted'];
      if (extracted is! Map<String, dynamic>) {
        throw const FoodScanApiException(
          'The server returned invalid meal details.',
        );
      }
      return extracted;
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }

  Future<List<UsdaFood>> searchFoods(String query) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/v1/scans/meals/usda-search',
        queryParameters: {'query': query},
      );
      return (response.data?['foods'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(UsdaFood.fromJson)
          .toList();
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }

  Future<List<MealScanResult>> getDiary(String date) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/v1/scans/meals',
        queryParameters: {
          'date': date,
          'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        },
      );
      return (response.data?['meals'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MealScanResult.fromJson)
          .toList();
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }

  Future<MealScanResult> confirmMeal(Map<String, dynamic> confirmedMeal) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/api/v1/scans/meals/confirm',
        data: confirmedMeal,
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final data = response.data;
      if (data == null) {
        throw const FoodScanApiException(
          'The server returned an empty meal analysis.',
        );
      }
      return MealScanResult.fromJson(data);
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }
}
