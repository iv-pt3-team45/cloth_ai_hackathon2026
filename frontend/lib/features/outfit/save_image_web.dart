import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Web ではブラウザのダウンロードで保存できる。
const canSaveImage = true;

/// 生成したコーデ画像をブラウザでダウンロードする。
///
/// `package:web` を足さずに済むよう、SDK の `dart:js_interop` で Blob と `<a download>` を使う。
Future<void> saveImage(
  Uint8List bytes,
  String mimeType,
  String fileName,
) async {
  final blobClass = globalContext['Blob']! as JSFunction;
  final options = JSObject()..['type'] = mimeType.toJS;
  final blob = blobClass.callAsConstructor<JSObject>(
    [bytes.toJS].toJS,
    options,
  );
  final urlClass = globalContext['URL']! as JSObject;
  final url = urlClass.callMethod<JSString>('createObjectURL'.toJS, blob);

  final document = globalContext['document']! as JSObject;
  final anchor = document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS)
    ..['href'] = url
    ..['download'] = fileName.toJS;
  anchor.callMethod<JSAny?>('click'.toJS);

  // すぐに解放するとダウンロードが始まらないブラウザがあるため少し待つ
  await Future<void>.delayed(const Duration(seconds: 1));
  urlClass.callMethod<JSAny?>('revokeObjectURL'.toJS, url);
}
