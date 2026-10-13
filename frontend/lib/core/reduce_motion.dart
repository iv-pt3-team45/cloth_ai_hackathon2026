// 端末の「動きを減らす」設定(spec 039)。
// Flutter Web は OS の設定(prefers-reduced-motion)を MediaQuery.disableAnimations に反映しないため、
// Web ではブラウザの設定を直接読む。
import 'package:flutter/widgets.dart';

import 'reduce_motion_stub.dart'
    if (dart.library.js_interop) 'reduce_motion_web.dart';

/// 動きを減らす設定が有効か(Flutter の設定、または Web のブラウザの設定)。
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) || browserPrefersReducedMotion();
