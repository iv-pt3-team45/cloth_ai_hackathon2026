"""チャット API のリクエスト / レスポンススキーマ。"""

from typing import Literal

from pydantic import BaseModel, Field, model_validator


class ChatMessage(BaseModel):
    role: Literal["user", "model"] = Field(..., description="発話者")
    content: str = Field(..., min_length=1, description="発話内容")


class Attachment(BaseModel):
    """エージェントに渡す添付(画像・動画など)。

    `data`(base64)と `uri` はどちらか一方だけを指定する。
    大きいファイルは Cloud Storage に置いて `uri`(gs://...)で渡す。
    """

    mime_type: str = Field(..., description="MIME タイプ(例: image/png, video/mp4)")
    data: str | None = Field(default=None, description="base64 エンコードしたバイト列")
    uri: str | None = Field(default=None, description="gs:// または https:// の URI")

    @model_validator(mode="after")
    def check_exclusive_source(self) -> "Attachment":
        if bool(self.data) == bool(self.uri):
            raise ValueError("data と uri はどちらか一方だけを指定してください")
        return self


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=8000, description="ユーザーの入力")
    history: list[ChatMessage] = Field(default_factory=list, description="直近の会話履歴(古い順)")
    attachments: list[Attachment] = Field(
        default_factory=list, description="今回のメッセージに添付する画像・動画"
    )


class ChatResponse(BaseModel):
    reply: str = Field(..., description="Gemini からの応答テキスト")
    model: str = Field(..., description="使用したモデル名")


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    app: str
    environment: str
    version: str
