"""Agent ADK を用いたチャットエンドポイント。"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import Settings, get_settings
from app.schemas.chat import ChatRequest, ChatResponse
from app.services.agent import AgentError, AgentService, get_agent_service

router = APIRouter(prefix="/chat", tags=["chat"])


@router.post("", response_model=ChatResponse)
async def chat(
    payload: ChatRequest,
    service: Annotated[AgentService, Depends(get_agent_service)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ChatResponse:
    try:
        reply = await service.generate_reply(payload.message, payload.history, payload.attachments)
    except AgentError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"エージェントの実行に失敗しました: {exc}",
        ) from exc

    return ChatResponse(reply=reply, model=settings.gemini_model)
