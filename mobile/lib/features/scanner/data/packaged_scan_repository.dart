import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../../profile/data/profile_repository.dart';
import 'packaged_scan.dart';

final packagedScanRepositoryProvider = Provider<PackagedScanRepository>(
  (ref) => PackagedScanRepository(ref.watch(apiClientProvider)),
);

class PackagedScanRepository {
  const PackagedScanRepository(this._client);

  final Dio _client;

  Future<Map<String, dynamic>> extractLabel(
    List<({Uint8List bytes, String name, String mimeType})> photos,
  ) async {
    try {
      final form = FormData();
      for (final photo in photos) {
        form.files.add(
          MapEntry(
            'files',
            MultipartFile.fromBytes(
              photo.bytes,
              filename: photo.name,
              contentType: DioMediaType.parse(photo.mimeType),
            ),
          ),
        );
      }
      final response = await _client.post<Map<String, dynamic>>(
        '/api/v1/scans/packaged/extract',
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 75),
        ),
      );
      final data = response.data?['extracted'];
      if (data is! Map<String, dynamic>) {
        throw const FoodScanApiException(
          'The server returned invalid extracted label details.',
        );
      }
      return data;
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }

  Future<PackagedScan> createScan(Map<String, dynamic> confirmedLabel) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/api/v1/scans/packaged',
        data: confirmedLabel,
      );
      final data = response.data;
      if (data == null) {
        throw const FoodScanApiException('The server returned an empty scan.');
      }
      return PackagedScan.fromJson(data);
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }

  Future<PackagedScan> getScan(String scanId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/v1/scans/$scanId',
      );
      final data = response.data;
      if (data == null) {
        throw const FoodScanApiException('The server returned an empty scan.');
      }
      return PackagedScan.fromJson(data);
    } on DioException catch (error) {
      throw FoodScanApiException.fromDio(error);
    }
  }
}
