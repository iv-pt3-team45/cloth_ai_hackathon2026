# 設計: 画像 / 動画生成ツール

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-17

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | ADK のツール(Function Calling)として実装し、呼ぶ判断はモデルに任せる | 採用 | 要件「ユーザーが望んだ場合に生成する」を自然に満たす。ADK を採用した目的そのもの |
| B | 「画像」等のキーワードをアプリ側で判定して分岐 | 却下 | 判定が脆く、言い回しの揺れに対応できない |
| C | 画像生成用の専用エンドポイントを別に作る | 却下 | 会話の流れから外れ、ユーザーが機能を意識する必要が出る |

## 2. 全体フロー

```
ユーザー「富士山の画像を作って」
  → LlmAgent が generate_image ツールを選択(Function Calling)
      → genai.Client.models.generate_content(image_model, response_modalities=[TEXT, IMAGE])
      → inline_data(バイト列)を app/created_images/ に保存
      → {"status":"ok","file_name":"...","path":"..."} を返す
  → モデルがツール結果を読み、保存先を含めた文章で応答
```

動画は `client.interactions.create()` を使う(`generateContent` は非対応)。
結果の `output_video.data`(base64)をデコードして保存する。

## 3. データモデル / ツールの契約

ツールは ADK に渡す**普通の Python 関数**。docstring がモデルへの説明になるため、
「いつ使うか」を明記する。

| ツール | 引数 | 戻り値 |
| --- | --- | --- |
| `generate_image` | `prompt: str` | `{"status": "ok", "file_name": ..., "path": ..., "mime_type": ...}` |
| `generate_video` | `prompt: str` | 同上 |

失敗時は例外を投げず `{"status": "error", "message": "..."}` を返す(モデルが状況を説明できるようにするため)。

## 4. バックエンド設計

### `app/services/media.py`(新規)

| 要素 | 役割 |
| --- | --- |
| `get_media_client()` | `genai.Client` を `lru_cache` で共有(ADC 認証) |
| `build_file_name(prefix, mime_type)` | `20260917-134501-ab12cd.png` 形式のファイル名を生成 |
| `save_media(data, prefix, mime_type, directory)` | ディレクトリを作成して保存し、パスを返す |
| `generate_image(prompt)` | 画像生成ツール本体 |
| `generate_video(prompt)` | 動画生成ツール本体 |

### `app/services/agent.py`(変更)

`build_agent()` の `tools=[generate_image, generate_video]` を追加する。

### `app/core/config.py`(変更)

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `image_model` | `gemini-3.1-flash-lite-image` | 画像生成モデル |
| `video_model` | `gemini-omni-1.1-flash-preview` | 動画生成モデル |
| `created_images_dir` | `app/created_images` | 画像の保存先(backend/ からの相対) |
| `created_videos_dir` | `app/created_videos` | 動画の保存先 |
| `media_generation_timeout` | `300`(秒) | 動画生成の待ち時間上限 |

パスは `Settings.created_images_path` / `created_videos_path` で
backend ディレクトリ基準の絶対パスに解決する(実行時のカレントに依存させないため)。

## 5. エラーハンドリング / 非機能

- 生成失敗・保存失敗は `MediaGenerationError` として捕捉し、ツールは `status: error` の dict を返す。
  ツールが例外を投げるとエージェント全体が止まるため。
- 動画生成は数十秒かかる。CLI は応答を待つだけだが、タイムアウトを設定で持つ。
- 保存ディレクトリは実行時に作成する(`mkdir(parents=True, exist_ok=True)`)。
- 生成物は Git 管理外にする(`.gitignore`)。

## 6. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| unit | `build_file_name` / `save_media` | 一時ディレクトリに保存して検証。外部通信なし |
| unit | ツールの異常系 | クライアント取得をモンキーパッチして失敗させ、`status: error` を確認 |
| unit | `build_agent` | `tools` に 2 つの関数が登録されていることを確認 |
| 手動 | 実生成 | CLI で画像・動画を生成し、保存先に出力されることを確認 |
