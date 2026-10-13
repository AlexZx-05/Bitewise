import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('foodScanRecognizeText')
external JSPromise<JSString> _foodScanRecognizeText(JSString imageDataUrl);

Future<String> recognizeLabelText(Uint8List bytes, String mimeType) async {
  final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
  final recognized = await _foodScanRecognizeText(dataUrl.toJS).toDart;
  return recognized.toDart;
}
