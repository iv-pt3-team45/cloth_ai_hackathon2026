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

/// タップで外部のページを開くリンク(出典など。spec 015)。
class ExternalLink extends StatelessWidget {
  const ExternalLink({super.key, required this.label, required this.url});

  final String label;
  final String url;

  Future<void> _open(BuildContext context) async {
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

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () => _open(context),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.accent2,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.accent2,
          ),
        ),
      ),
    );
  }
}
