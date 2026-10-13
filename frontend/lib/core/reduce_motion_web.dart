import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// ブラウザの `prefers-reduced-motion: reduce` が有効か(Web 用)。
bool browserPrefersReducedMotion() {
  try {
    final query = globalContext.callMethod<JSObject>(
      'matchMedia'.toJS,
      '(prefers-reduced-motion: reduce)'.toJS,
    );
    return (query['matches'] as JSBoolean?)?.toDart ?? false;
  } on Object {
    // matchMedia が使えないブラウザでは、動きを減らさない
    return false;
  }
}
