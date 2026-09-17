"""エージェントループのテスト(外部 API は呼ばない)。"""

from pathlib import Path

from app.core.config import Settings
from app.schemas.chat import ChatMessage
from app.services.agent import AgentError, AgentService
from app.services.agent_loop import (
    LoopStep,
    build_retry_prompt,
    detect_new_artifact,
    run_agent_loop,
)
from app.services.verification import Verdict


class StubAgentService(AgentService):
    """呼ばれた回数と履歴を記録するだけのフェイク。"""

    def __init__(self, replies: list[str]) -> None:
        super().__init__(Settings())
        self._replies = replies
        self.prompts: list[str] = []
        self.history_sizes: list[int] = []

    async def generate_reply(self, message, history, attachments=None):  # type: ignore[no-untyped-def]
        self.prompts.append(message)
        self.history_sizes.append(len(history))
        return self._replies[min(len(self.prompts) - 1, len(self._replies) - 1)]


class FailingAgentService(AgentService):
    async def generate_reply(self, message, history, attachments=None):  # type: ignore[no-untyped-def]
        raise AgentError("クォータ超過")


def verdicts(*results: bool):
    """satisfied を順に返す検証関数を作る。"""
    calls = iter(results)

    async def verify(requirement: str, reply: str, artifact: Path | None) -> Verdict:
        satisfied = next(calls, results[-1])
        return Verdict(
            satisfied=satisfied,
            reason="十分です" if satisfied else "要素が足りません",
            improvements="" if satisfied else "犬を大きく写すこと",
        )

    return verify


async def test_loop_stops_when_satisfied() -> None:
    service = StubAgentService(["作りました"])

    result = await run_agent_loop(
        "柴犬の画像", max_iterations=3, service=service, verify=verdicts(True)
    )

    assert result.satisfied is True
    assert len(result.steps) == 1
    assert service.prompts == ["柴犬の画像"]


async def test_loop_stops_at_max_iterations() -> None:
    service = StubAgentService(["作りました"])

    result = await run_agent_loop(
        "柴犬の画像", max_iterations=3, service=service, verify=verdicts(False, False, False)
    )

    assert result.satisfied is False
    assert len(result.steps) == 3
    assert len(service.prompts) == 3


async def test_retry_prompt_contains_feedback() -> None:
    service = StubAgentService(["作りました"])

    await run_agent_loop(
        "柴犬の画像", max_iterations=2, service=service, verify=verdicts(False, True)
    )

    assert "犬を大きく写すこと" in service.prompts[1]
    assert "柴犬の画像" in service.prompts[1]
    # 2 周目には 1 周目のやり取りが履歴として渡る
    assert service.history_sizes == [0, 2]


async def test_loop_breaks_on_generation_error() -> None:
    result = await run_agent_loop(
        "柴犬の画像", max_iterations=3, service=FailingAgentService(), verify=verdicts(True)
    )

    assert result.satisfied is False
    assert len(result.steps) == 1
    assert result.steps[0].error == "クォータ超過"


async def test_on_step_is_called_for_each_iteration() -> None:
    seen: list[LoopStep] = []

    await run_agent_loop(
        "柴犬の画像",
        max_iterations=2,
        service=StubAgentService(["作りました"]),
        verify=verdicts(False, True),
        on_step=seen.append,
    )

    assert [s.iteration for s in seen] == [1, 2]


def test_build_retry_prompt_includes_reason_and_improvements() -> None:
    verdict = Verdict(satisfied=False, reason="犬が小さい", improvements="犬を中央に配置する")

    prompt = build_retry_prompt("柴犬の画像", verdict)

    assert "犬が小さい" in prompt
    assert "犬を中央に配置する" in prompt
    assert "柴犬の画像" in prompt


def test_detect_new_artifact_returns_created_file(tmp_path: Path) -> None:
    old = tmp_path / "old.png"
    old.write_bytes(b"old")
    before = {old}

    new = tmp_path / "new.png"
    new.write_bytes(b"new")

    assert detect_new_artifact(before, {old, new}) == new


def test_detect_new_artifact_returns_none_when_nothing_created(tmp_path: Path) -> None:
    existing = tmp_path / "a.png"
    existing.write_bytes(b"a")

    assert detect_new_artifact({existing}, {existing}) is None


async def test_final_artifact_returns_latest(tmp_path: Path) -> None:
    result = await run_agent_loop(
        "柴犬の画像",
        max_iterations=1,
        service=StubAgentService(["作りました"]),
        verify=verdicts(True),
    )
    # 生成物が無い場合は None
    assert result.final_artifact is None
    assert isinstance(result.steps[0].reply, str)
    assert isinstance(ChatMessage(role="user", content="x").content, str)


async def test_loop_reports_failure_reason_in_step() -> None:
    result = await run_agent_loop(
        "柴犬の画像",
        max_iterations=1,
        service=StubAgentService(["作りました"]),
        verify=verdicts(False),
    )

    assert result.steps[0].verdict is not None
    assert result.steps[0].verdict.satisfied is False
    assert "足りません" in result.steps[0].verdict.reason
