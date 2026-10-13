import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// URL を開く関数(テストで差し替える)。開けなければ false。
typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> _launch(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// 外部のページを開く処理。テストでは差し替える。
@visibleForTesting
UrlOpener openUrl = _launch;

/// 外部のページを開く。開けなければ「リンクを開けませんでした」と SnackBar で知らせる。
Future<void> openExternalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri.tryParse(url);
  var opened = false;
  if (uri != null) {
    try {
      opened = await openUrl(uri);
    } on Exception {
      opened = false;
    }
  }
  if (!opened) {
    messenger?.showSnackBar(const SnackBar(content: Text('リンクを開けませんでした')));
  }
}

/// タップで外部のページを開くリンク(出典など。spec 015)。
class ExternalLink extends StatelessWidget {
  const ExternalLink({super.key, required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final color = AppPalette.of(context).accent2;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () => openExternalUrl(context, url),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}
