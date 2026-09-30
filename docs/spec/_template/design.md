# 設計: <機能名>

- 対応する要件: `./requirements.md`
- ステータス: draft | reviewed | approved
- 更新日: YYYY-MM-DD

## 1. 設計方針

<採用するアプローチと、その理由。検討した代替案と却下理由も書く。>

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | | 採用 | |
| B | | 却下 | |

## 2. 全体フロー

```
Flutter(画面) --> ApiClient --> FastAPI(router) --> Service --> Gemini(Vertex AI)
```

<シーケンスや状態遷移を図示する。>

## 3. API 設計

### `POST /api/v1/<path>`

リクエスト:

```json
{ }
```

レスポンス (200):

```json
{ }
```

エラー:

| ステータス | 条件 | ボディ |
| --- | --- | --- |
| 400 | | |
| 502 | 外部 API 失敗 | `{"detail": "..."}` |

## 4. データモデル

<Pydantic スキーマ / Dart モデル / 永続化するなら保存先とスキーマ。>

## 5. フロントエンド設計

- 画面: `frontend/lib/features/<feature>/`
- 状態管理: <保持する状態と更新契機>
- 画面遷移 / 空状態 / ローディング / エラー表示

## 6. バックエンド設計

- ルータ: `backend/app/api/routes/<feature>.py`
- サービス: `backend/app/services/<feature>.py`
- 設定追加: `backend/app/core/config.py` に追加する項目

## 7. Gemini プロンプト設計

- モデル: `gemini-3.5-flash-lite`(テキスト系の標準。変える場合は理由を書く)
- system instruction / 入力の組み立て / 出力フォーマット(JSON スキーマ等)
- 失敗時のフォールバック

## 8. エラーハンドリング / 非機能

- 異常系の扱い、タイムアウト、リトライ
- 性能目標、ログに残す項目、機微情報の扱い

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | サービス | pytest(Gemini はスタブ) |
| backend api | ルータ | TestClient |
| frontend | 画面 | flutter test(Repository はフェイク) |
