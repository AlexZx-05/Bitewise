import 'dart:typed_data';

import 'ocr_service_stub.dart'
    if (dart.library.js_interop) 'ocr_service_web.dart' as platform;

Future<String> recognizeLabelText(Uint8List bytes, String mimeType) {
  return platform.recognizeLabelText(bytes, mimeType);
}
