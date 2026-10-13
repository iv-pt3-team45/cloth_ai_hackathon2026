import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/features/auth/register_rules.dart';

void main() {
  group('ユーザー ID(spec 040 AC-8)', () {
    test('英小文字・数字・_・- の 3〜32 文字なら OK', () {
      expect(userIdProblem('abc'), isNull);
      expect(userIdProblem('a' * 32), isNull);
      expect(userIdProblem('demo_01-x'), isNull);
    });

    test('2 文字・33 文字は NG', () {
      expect(userIdProblem('ab'), isNotNull);
      expect(userIdProblem('a' * 33), isNotNull);
      expect(userIdProblem(''), isNotNull);
    });

    test('大文字・記号・全角・途中の空白は NG', () {
      for (final id in [
        'Demo01',
        'demo.01',
        'demo@01',
        'でも01',
        'ｄｅｍｏ',
        'de mo',
      ]) {
        expect(userIdProblem(id), isNotNull, reason: id);
      }
    });

    test('前後の空白は除いてからチェックする', () {
      expect(userIdProblem('  demo01 '), isNull);
    });

    test('文言はバックエンドのユーザーの追加と同じ', () {
      expect(userIdProblem('A'), 'ユーザー ID は英小文字・数字・_・- の 3〜32 文字にしてください。');
    });
  });

  group('パスワード(AC-8)', () {
    test('8 文字以上なら OK、7 文字は NG', () {
      expect(passwordProblem('12345678'), isNull);
      expect(passwordProblem('1234567'), 'パスワードは 8 文字以上にしてください。');
      expect(passwordProblem(''), isNotNull);
    });

    test('空白も文字として数える', () {
      expect(passwordProblem('        '), isNull);
    });
  });

  group('確認のパスワード(AC-8)', () {
    test('一致すれば OK、違えば NG', () {
      expect(confirmProblem('password1', 'password1'), isNull);
      expect(confirmProblem('password1', 'password2'), '確認のパスワードが一致しません。');
      expect(confirmProblem('password1', ''), isNotNull);
    });
  });
}
