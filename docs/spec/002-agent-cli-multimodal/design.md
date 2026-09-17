# 設計: エージェント単体実行 CLI とマルチモーダル入力

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-17

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | CLI は `AgentService` を直接呼ぶ。添付は共通スキーマ `Attachment` で表現 | 採用 | CLI と API で同じ経路を通るため、CLI で確認した挙動がそのまま API でも再現する |
| B | CLI から HTTP でサーバを叩く | 却下 | サーバ起動が必要になり「py ファイル単体で動く」という目的を満たさない |
| C | CLI 専用にプロンプト処理を書く | 却下 | 実装が二重化し、挙動がずれる |

## 2. 全体フロー

```
scripts/run_agent.py (CLI)          POST /api/v1/chat (HTTP)
        │                                   │
        └────────────┬──────────────────────┘
                     ▼
        AgentService.generate_reply(message, history, attachments)
                     │
                     ├─ to_parts(): テキスト + 添付 → list[types.Part]
                     │     ├─ data(base64) → Part.from_bytes()
                     │     └─ uri(gs://)   → Part.from_uri()
                     └─ Runner.run_async() → LlmAgent → Gemini
```

## 3. API 設計

`POST /api/v1/chat` に**任意項目を追加**(後方互換)。

```json
{
  "message": "この画像を説明して",
  "history": [],
  "attachments": [
    {"mime_type": "image/png", "data": "<base64>"},
    {"mime_type": "video/mp4", "uri": "gs://bucket/movie.mp4"}
  ]
}
```

- `data` と `uri` は**どちらか一方のみ**指定する(両方 / どちらも無しは 422)。
- レスポンス形式は変更しない。

## 4. データモデル

`app/schemas/chat.py` に追加:

| クラス | 内容 |
| --- | --- |
| `Attachment` | `mime_type` / `data`(base64) / `uri`。`model_validator` で排他チェック |
| `ChatRequest.attachments` | `list[Attachment]`(既定は空リスト) |

## 5. バックエンド設計

### `app/services/attachments.py`(新規)

ローカルパス / URI から `Attachment` を組み立てるヘルパー。CLI が使う。

| 関数 | 役割 |
| --- | --- |
| `guess_mime_type(path)` | 拡張子から MIME を判定。判定できなければ `AttachmentError` |
| `load_attachment(path_or_uri)` | `gs://` / `https://` は URI のまま、ローカルパスは読み込んで base64 化 |

対応拡張子は画像(png/jpg/gif/webp)と動画(mp4/mov/webm/avi/mpeg)を明示的に持つ
(`mimetypes` は環境差があるため、判定を環境に依存させない)。

### `app/services/agent.py`(変更)

- `to_parts(message, attachments) -> list[types.Part]` を追加(純粋関数・テスト対象)。
- `AgentService.generate_reply(message, history, attachments=None)` に引数追加(既定 `None` で後方互換)。

### `scripts/run_agent.py`(新規)

`uv run python scripts/run_agent.py` で起動する CLI。

| モード | 起動方法 | 動作 |
| --- | --- | --- |
| 対話 | 引数なし | プロンプトを出し、履歴を保持して会話を続ける |
| 単発 | `-m "質問"` | 1 回実行して終了する |

| コマンド(対話中) | 動作 |
| --- | --- |
| `/file <パス or gs://...>` | 次のメッセージに添付する |
| `/files` | 添付予定の一覧 |
| `/clear` | 添付予定を取り消す |
| `/reset` | 会話履歴を消す |
| `/help` / `/exit` | ヘルプ / 終了 |

オプション: `-m/--message`, `-f/--file`(複数可), `--model`(モデル上書き), `--quiet`(ログ抑制)。

## 6. エラーハンドリング / 非機能

- 添付の失敗(存在しない / 未対応拡張子)は `AttachmentError`。CLI は**メッセージを出して対話を継続**する。
- API 側は Pydantic の検証で 422、エージェント実行時の失敗は従来どおり 502。
- Windows コンソールの文字化けを避けるため、CLI は標準出力を UTF-8 に再設定する。
- 既定ではログを抑制し(`--quiet` の逆で `-v` を用意)、応答だけが見えるようにする。

## 7. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| unit | `guess_mime_type` / `load_attachment` | 一時ファイルを使い、外部通信なし |
| unit | `to_parts` | Part の種類と順序を検証 |
| unit | `Attachment` の排他検証 | Pydantic の ValidationError |
| api | `/chat` に `attachments` | フェイクサービスで契約のみ検証 |
