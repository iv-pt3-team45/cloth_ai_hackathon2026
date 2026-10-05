"""アプリケーション設定。環境変数 / .env から読み込む。"""

import os
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

# backend/ ディレクトリ。保存先を実行時のカレントに依存させないための基準にする。
BACKEND_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- アプリ基本設定 ---
    app_name: str = "tx_hackathon_gc-backend"
    environment: Literal["local", "dev", "prod"] = "local"
    log_level: str = "INFO"

    # CORS: Flutter Web の開発サーバなど
    cors_origins: list[str] = [
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:3000",
    ]

    # --- Google Cloud / Gemini 設定 ---
    # Vertex AI (Google Cloud) 経由で Gemini を呼ぶ場合は True
    google_genai_use_vertexai: bool = True
    google_cloud_project: str = ""
    # 新しい Gemini モデルは global でのみ提供される。リージョン指定が必要な場合のみ変更する
    google_cloud_location: str = "global"
    # Vertex AI を使わない場合(AI Studio の API キー利用時)のみ設定
    google_api_key: str = ""

    # --- ADK (Agent Development Kit) 設定 ---
    adk_app_name: str = "tx-hackathon-gc"
    agent_name: str = "chat_agent"
    agent_description: str = "ユーザーとの対話を担当するエージェント"

    gemini_model: str = "gemini-3.5-flash-lite"
    gemini_temperature: float = 0.7
    gemini_max_output_tokens: int = 2048
    # --- メディア生成 ---
    image_model: str = "gemini-3.1-flash-lite-image"
    video_model: str = "gemini-omni-1.1-flash-preview"
    created_images_dir: str = "app/created_images"
    created_videos_dir: str = "app/created_videos"
    media_generation_timeout: int = 300
    # 画像生成モデルに送るプロンプトと応答の全文をログ(ターミナル)に出す。一時的なデバッグ用
    # (画像のバイト列は形式と大きさだけ出す)。不要になったら false にする
    image_debug_log: bool = True

    # --- エージェントループ ---
    # 検証用モデル。生成モデルとクォータを分けたいときは別のモデルを指定する
    verifier_model: str = "gemini-3.5-flash-lite"
    loop_max_iterations: int = 3

    # --- 服インデックス / 手持ちの服の登録(spec 005 / 006 / 010) ---
    cloth_index_model: str = "gemini-3.5-flash-lite"
    # 登録した服のインデックス(backend/ からの相対パス)。エージェントもここを参照する。
    # 写真は同じフォルダの images/ に保存する。サンプルを参照したいときは
    # tests/sample_cloth_indexs/index.json を指定する(CLI なら --index)
    cloth_index_path: str = "data/wardrobe/index.json"
    # 登録する写真 1 枚の上限(バイト)
    wardrobe_max_image_bytes: int = 10 * 1024 * 1024

    # --- YouTube Data API ---
    # 【例外】API キーを使う。YouTube Data API は ADC の既定スコープ(cloud-platform)では呼べないため
    youtube_data_api_key: str = ""
    # MV 名で検索したときの候補数(検索は 1 回 100 ユニット消費する)
    youtube_search_max_results: int = 5
    # 検索結果の地域(ISO 3166-1 alpha-2)。空なら指定しない
    youtube_region_code: str = "JP"
    youtube_request_timeout: float = 10.0

    # --- アーティストのカルチャー情報(spec 008) ---
    # Google 検索(グラウンディング)と YouTube の動画入力に対応したモデルを指定する
    culture_model: str = "gemini-3.5-flash-lite"
    # 調査・整理・MV の映像の解析を合わせた待ち時間の上限(秒)
    culture_timeout: float = 180.0

    # --- ライブ情報の検索(spec 009) ---
    # Google 検索(グラウンディング)に対応したモデルを指定する
    live_search_model: str = "gemini-3.5-flash-lite"
    # 調査・整理を合わせた待ち時間の上限(秒)
    live_search_timeout: float = 120.0

    # --- 会場情報取得(F14) ---
    venue_info_model: str = "gemini-2.5-flash"
    # コーデ提案(spec 011)の前に会場の形態を調べるときの待ち時間の上限(秒)。
    # 超えたら形態不明として提案を続ける
    venue_info_timeout: float = 30.0

    # --- 手持ちの服からのコーデ提案(spec 011) ---
    # 提案(文字)に使うモデル。画像の生成は IMAGE_MODEL を使う
    outfit_model: str = "gemini-3.5-flash-lite"
    # 提案の待ち時間の上限(秒)。画像の生成は MEDIA_GENERATION_TIMEOUT
    outfit_timeout: float = 120.0
    # 提案の服を着せるマネキン画像(backend/ からの相対パス)
    outfit_mannequin_path: str = "app/assets/white_manekin.jpeg"

    gemini_system_instruction: str = "あなたは日本語で簡潔かつ正確に回答するアシスタントです。"

    @property
    def is_local(self) -> bool:
        return self.environment == "local"

    @property
    def created_images_path(self) -> Path:
        """生成画像の保存先(絶対パス)。"""
        return (BACKEND_ROOT / self.created_images_dir).resolve()

    @property
    def created_videos_path(self) -> Path:
        """生成動画の保存先(絶対パス)。"""
        return (BACKEND_ROOT / self.created_videos_dir).resolve()

    @property
    def outfit_mannequin_file(self) -> Path:
        """コーデ提案で服を着せるマネキン画像の絶対パス。"""
        return (BACKEND_ROOT / self.outfit_mannequin_path).resolve()

    @property
    def cloth_index_file(self) -> Path:
        """エージェントが参照する服インデックスの絶対パス。"""
        return (BACKEND_ROOT / self.cloth_index_path).resolve()

    def export_google_env(self) -> None:
        """GCP 関連の設定を os.environ に反映する。

        ADK は接続先と認証方式を環境変数からしか読まないため、
        `.env` から読んだ値を明示的に環境変数へ移す必要がある。
        既に環境変数が設定されている場合(コンテナ等)はそちらを優先する。
        """
        os.environ.setdefault(
            "GOOGLE_GENAI_USE_VERTEXAI",
            "TRUE" if self.google_genai_use_vertexai else "FALSE",
        )
        if self.google_cloud_project:
            os.environ.setdefault("GOOGLE_CLOUD_PROJECT", self.google_cloud_project)
        if self.google_cloud_location:
            os.environ.setdefault("GOOGLE_CLOUD_LOCATION", self.google_cloud_location)
        if self.google_api_key:
            os.environ.setdefault("GOOGLE_API_KEY", self.google_api_key)


@lru_cache
def get_settings() -> Settings:
    """設定のシングルトン。DI (Depends) からも利用する。"""
    return Settings()
