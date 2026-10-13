import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/themed_route.dart';
import '../../core/widgets.dart';
import 'privacy_policy.dart';

const privacyPolicyLinkKey = Key('privacy-policy-link');

/// 初期ページの一番下に置く、小さな灰色のリンク(spec 042)。押すとポリシーの画面を開く。
///
/// カードの外(背景の上)に置くため、文字は背景用の薄い色(暗い背景では明るい色。spec 041)にする。
class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        key: privacyPolicyLinkKey,
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.of(context).onBackgroundMuted,
          minimumSize: const Size(48, 40),
          textStyle: const TextStyle(
            fontSize: 12,
            decoration: TextDecoration.underline,
          ),
        ),
        // 入力の画面の配色(MV に合わせた配色)を引き継いで開く
        onPressed: () =>
            pushThemed<void>(context, (_) => const PrivacyPolicyScreen()),
        child: const Text('プライバシーポリシー'),
      ),
    );
  }
}

/// プライバシーポリシーの画面(spec 042)。← またはブラウザの戻るで初期ページに戻る。
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PaletteBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: palette.onBackground,
          title: Text(
            'プライバシーポリシー',
            style: TextStyle(color: palette.onBackground),
          ),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                // 全文を 1 つの白い枠にまとめる(節ごとに枠を分けない)
                child: SectionCard(
                  children: [
                    const Text(policyIntro),
                    const SizedBox(height: 4),
                    const Hint('制定日: $policyEstablished'),
                    for (final (index, section) in policySections.indexed)
                      _SectionView(number: index + 1, section: section),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1 つの節(番号つきの見出しと本文)。
class _SectionView extends StatelessWidget {
  const _SectionView({required this.number, required this.section});

  final int number;
  final PolicySection section;

  @override
  Widget build(BuildContext context) {
    final lead = section.lead;
    final note = section.note;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. ${section.title}',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          if (lead != null) Text(lead),
          if (lead != null && section.bullets.isNotEmpty)
            const SizedBox(height: 6),
          if (section.bullets.isNotEmpty) Bullets(section.bullets),
          if (note != null) ...[const SizedBox(height: 6), Text(note)],
        ],
      ),
    );
  }
}
