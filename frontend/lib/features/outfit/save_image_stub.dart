import 'dart:typed_data';

/// Web 以外では保存できない(結果の画面に「画像を保存」を出さない)。
const canSaveImage = false;

/// Web 以外では何もしない。
Future<void> saveImage(
  Uint8List bytes,
  String mimeType,
  String fileName,
) async {}
