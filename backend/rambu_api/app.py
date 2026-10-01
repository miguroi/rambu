import os
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Protocol

from fastapi import BackgroundTasks, Body, FastAPI, Header, HTTPException, Response
from fastapi.responses import JSONResponse
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .demo import DemoService, default_scenarios, delay_from_environment
from .langflow_client import LangflowClient, LangflowFailure
from .apns import PushSender, push_sender_from_environment
from .models import (
    CreateFamilyRequest,
    ChunkAnalysisResponse,
    DemoFailure,
    DemoSnapshot,
    JoinFamilyRequest,
    PilotAlert,
    PilotAlertInput,
    PilotDecisionInput,
    PilotDecisionResult,
    PilotInvite,
    PilotProfile,
    PilotSession,
    PushTokenRequest,
)
from .pilot import (
    AuthenticationError,
    AuthorizationError,
    DecisionConflict,
    InviteError,
    MissingAlertError,
    PilotStore,
)
from .transcription import FasterWhisperTranscriber


class DemoServiceContract(Protocol):
    def start(self, scenario: str) -> DemoSnapshot: ...
    def get(self, session_id: str) -> DemoSnapshot: ...
    def delete(self, session_id: str) -> None: ...
    def close(self) -> None: ...
    def analyze_chunk(self, audio: bytes, final: bool) -> ChunkAnalysisResponse: ...


def _default_service() -> DemoService:
    return DemoService(
        scenarios=default_scenarios(),
        transcriber=FasterWhisperTranscriber(os.getenv("RAMBU_WHISPER_MODEL", "small")),
        analyzer=LangflowClient(
            os.getenv("LANGFLOW_URL", "http://127.0.0.1:7861"),
            os.getenv("LANGFLOW_FLOW_ID", "rambu"),
            os.getenv("LANGFLOW_API_KEY"),
        ),
        delay_seconds=delay_from_environment(),
    )


def _default_pilot_store() -> PilotStore:
    default_path = Path(__file__).resolve().parents[1] / "data" / "rambu.sqlite3"
    return PilotStore(os.getenv("RAMBU_DATABASE_PATH", str(default_path)))


def create_app(
    service: DemoServiceContract | None = None,
    pilot_store: PilotStore | None = None,
    push_sender: PushSender | None = None,
) -> FastAPI:
    demo_service = service or _default_service()
    pilots = pilot_store or (PilotStore(":memory:") if service is not None else _default_pilot_store())
    pushes = push_sender or push_sender_from_environment()
    push_environment = os.getenv("APNS_ENVIRONMENT", "sandbox")

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        demo_service.close()
        pilots.close()
        pushes.close()

    app = FastAPI(title="Rambu Digital Prototype", version="0.2.0", lifespan=lifespan)
    web_root = Path(__file__).resolve().parents[1] / "web"
    project_root = Path(__file__).resolve().parents[2]

    app.mount("/static", StaticFiles(directory=web_root), name="static")
    samples_root = project_root / "samples" / "audio"
    if samples_root.exists():
        app.mount("/samples", StaticFiles(directory=samples_root), name="samples")

    @app.get("/", include_in_schema=False)
    def dashboard() -> FileResponse:
        return FileResponse(web_root / "index.html")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ready"}

    @app.post("/api/demo/{scenario}", response_model=DemoSnapshot, status_code=201)
    def start_demo(scenario: str) -> DemoSnapshot:
        try:
            return demo_service.start(scenario)
        except KeyError as error:
            raise HTTPException(status_code=404, detail="Skenario tidak ditemukan.") from error
        except FileNotFoundError as error:
            raise HTTPException(status_code=503, detail="Audio skenario belum tersedia.") from error

    @app.get("/api/demo/{session_id}", response_model=DemoSnapshot)
    def demo_status(session_id: str) -> DemoSnapshot:
        try:
            return demo_service.get(session_id)
        except KeyError as error:
            raise HTTPException(status_code=404, detail="Sesi demo tidak ditemukan.") from error

    @app.delete("/api/demo/{session_id}", status_code=204)
    def delete_demo(session_id: str) -> Response:
        try:
            demo_service.delete(session_id)
        except KeyError as error:
            raise HTTPException(status_code=404, detail="Sesi demo tidak ditemukan.") from error
        return Response(status_code=204)

    @app.post("/api/analyze-chunk", response_model=ChunkAnalysisResponse)
    def analyze_chunk(
        audio: bytes = Body(media_type="audio/wav"),
        x_rambu_consent: str | None = Header(default=None),
        x_rambu_final: str | None = Header(default=None),
    ) -> ChunkAnalysisResponse:
        if x_rambu_consent != "true":
            raise HTTPException(status_code=403, detail="Persetujuan pemrosesan audio belum dikonfirmasi.")
        if len(audio) > 1_000_000:
            raise HTTPException(status_code=413, detail="Potongan audio terlalu besar.")
        try:
            return demo_service.analyze_chunk(audio, final=x_rambu_final == "true")
        except ValueError as error:
            raise HTTPException(status_code=422, detail=str(error)) from error
        except LangflowFailure as error:
            failure = DemoFailure(
                code=f"analysis_{error.code}",
                message=error.safe_message,
            )
            raise HTTPException(status_code=503, detail=failure.model_dump()) from error
        except Exception as error:
            failure = DemoFailure(
                code="transcription_failed",
                message="Transkripsi audio gagal.",
            )
            raise HTTPException(status_code=503, detail=failure.model_dump()) from error

    def token_from(authorization: str | None) -> str:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Token perangkat diperlukan.")
        return authorization.removeprefix("Bearer ").strip()

    def pilot_error(error: Exception) -> HTTPException:
        if isinstance(error, AuthenticationError):
            return HTTPException(status_code=401, detail=str(error))
        if isinstance(error, AuthorizationError):
            return HTTPException(status_code=403, detail=str(error))
        if isinstance(error, (InviteError, ValueError)):
            return HTTPException(status_code=422, detail=str(error))
        if isinstance(error, MissingAlertError):
            return HTTPException(status_code=404, detail=str(error))
        return HTTPException(status_code=500, detail="Layanan pilot gagal.")

    @app.post("/api/pilot/families", response_model=PilotSession, status_code=201)
    def create_family(value: CreateFamilyRequest) -> PilotSession:
        try:
            return pilots.create_family(value.parent_name)
        except Exception as error:
            raise pilot_error(error) from error

    @app.post("/api/pilot/families/join", response_model=PilotSession, status_code=201)
    def join_family(value: JoinFamilyRequest) -> PilotSession:
        try:
            return pilots.join_family(value.code, value.name, value.relation)
        except Exception as error:
            raise pilot_error(error) from error

    @app.get("/api/pilot/profile", response_model=PilotProfile)
    def pilot_profile(authorization: str | None = Header(default=None)) -> PilotProfile:
        try:
            return pilots.profile(token_from(authorization))
        except HTTPException:
            raise
        except Exception as error:
            raise pilot_error(error) from error

    @app.post("/api/pilot/invites", response_model=PilotInvite, status_code=201)
    def renew_invite(authorization: str | None = Header(default=None)) -> PilotInvite:
        try:
            code, expires = pilots.renew_invite(token_from(authorization))
            return PilotInvite(code=code, expires_at=expires)
        except HTTPException:
            raise
        except Exception as error:
            raise pilot_error(error) from error

    @app.put("/api/pilot/push-token", status_code=204)
    def register_push_token(
        value: PushTokenRequest,
        authorization: str | None = Header(default=None),
    ) -> Response:
        try:
            pilots.register_push_token(token_from(authorization), value.token, value.environment)
            return Response(status_code=204)
        except HTTPException:
            raise
        except Exception as error:
            raise pilot_error(error) from error

    @app.post("/api/pilot/alerts", response_model=PilotAlert, status_code=201)
    def publish_alert(
        value: PilotAlertInput,
        background_tasks: BackgroundTasks,
        authorization: str | None = Header(default=None),
    ) -> PilotAlert:
        try:
            token = token_from(authorization)
            alert, should_notify = pilots.publish_alert_result(token, value)
            if should_notify:
                targets = pilots.notification_tokens(token, "guardian", push_environment)
                background_tasks.add_task(
                    pushes.send, targets, f"{alert.level.title()}: {alert.parent.name} mungkin sedang ditipu",
                    "Ketuk untuk melihat kalimat pemicu dan memutuskan.", str(alert.id),
                )
            return alert
        except HTTPException:
            raise
        except Exception as error:
            raise pilot_error(error) from error

    @app.get("/api/pilot/alerts", response_model=list[PilotAlert])
    def list_alerts(authorization: str | None = Header(default=None)) -> list[PilotAlert]:
        try:
            return pilots.alerts(token_from(authorization))
        except HTTPException:
            raise
        except Exception as error:
            raise pilot_error(error) from error

    @app.post("/api/pilot/alerts/{alert_id}/decision", response_model=PilotDecisionResult)
    def decide_alert(
        alert_id: str,
        value: PilotDecisionInput,
        background_tasks: BackgroundTasks,
        authorization: str | None = Header(default=None),
    ) -> PilotDecisionResult | JSONResponse:
        try:
            token = token_from(authorization)
            decision = pilots.decide(token, alert_id, value.verdict)
            targets = pilots.notification_tokens(token, "parent", push_environment)
            title = f"{decision.by.name}: {'ini penipuan' if decision.verdict == 'scam' else 'telepon aman'}"
            body = "Tutup telepon sekarang." if decision.verdict == "scam" else "Tetap jangan beri kode atau transfer."
            background_tasks.add_task(pushes.send, targets, title, body, alert_id)
            return PilotDecisionResult(accepted=True, decision=decision)
        except DecisionConflict as error:
            body = PilotDecisionResult(accepted=False, decision=error.decision)
            return JSONResponse(status_code=409, content=body.model_dump(mode="json"))
        except HTTPException:
            raise
        except Exception as error:
            raise pilot_error(error) from error

    @app.post("/api/pilot/alerts/{alert_id}/end", response_model=PilotAlert)
    def end_alert(alert_id: str, authorization: str | None = Header(default=None)) -> PilotAlert:
        try:
            return pilots.end_alert(token_from(authorization), alert_id)
        except HTTPException:
            raise
        except Exception as error:
            raise pilot_error(error) from error

    return app


app = create_app()
