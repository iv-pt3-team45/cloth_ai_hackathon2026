import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 選んだ写真 1 枚。
class PickedPhoto {
  const PickedPhoto({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;

  /// jpeg / png / webp のいずれか。それ以外の形式なら null
  final String? mimeType;

  bool get isSupported => mimeType != null;
}

const _supportedTypes = {'image/jpeg', 'image/png', 'image/webp'};

/// 写真の形式を判定する。報告された MIME タイプを優先し、無ければ拡張子で判定する。
///
/// jpeg / png / webp 以外(HEIC など)は null。
String? detectMimeType(String name, String? reported) {
  if (reported != null && reported.isNotEmpty) {
    return _supportedTypes.contains(reported) ? reported : null;
  }
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}

/// 写真を選ぶ仕組み。テストではフェイクに差し替える。
abstract class PhotoPicker {
  /// 写真を最大 [limit] 枚選ぶ(環境によっては上限を守らないため、呼び出し側でも切り詰める)。
  Future<List<PickedPhoto>> pick({required int limit});
}

/// `image_picker` で写真を選ぶ(Web ではファイル選択、スマホでは写真・カメラ)。
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async {
    // 送る量を減らすため、長辺 1600px・品質 85 に縮小して受け取る
    final files = await _picker.pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
      limit: limit,
    );
    return [
      for (final file in files)
        PickedPhoto(
          name: file.name,
          bytes: await file.readAsBytes(),
          mimeType: detectMimeType(file.name, file.mimeType),
        ),
    ];
  }
}
