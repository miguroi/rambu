from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


RiskLevel = Literal["low", "needs_review", "high_risk"]
Signal = Literal["impersonation", "urgency", "secret_code", "transfer", "remote_app"]


class Evidence(BaseModel):
    model_config = ConfigDict(extra="forbid")

    quote: str = Field(min_length=1)
    signals: list[Signal] = Field(min_length=1)


class RiskAssessment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    risk_level: RiskLevel
    signals: list[Signal]
    evidence: list[Evidence]
    explanation: str = Field(min_length=1)
    recommended_action: str = Field(min_length=1)


def validate_assessment(assessment: RiskAssessment, transcript: str) -> RiskAssessment:
    if assessment.risk_level == "low":
        if assessment.signals or assessment.evidence:
            raise ValueError("Low risk cannot contain signals or evidence.")
        return assessment

    if not assessment.signals or not assessment.evidence:
        raise ValueError("Risky assessments require signals and evidence.")

    top_level = set(assessment.signals)
    for item in assessment.evidence:
        if item.quote not in transcript:
            raise ValueError("Evidence must be an exact transcript substring.")
        if not set(item.signals).issubset(top_level):
            raise ValueError("Evidence signals must appear at the top level.")
    return assessment


class DemoFailure(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str
    message: str


class DemoSnapshot(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    scenario: str
    title: str
    status: Literal["running", "completed", "error"]
    progress: int
    transcript: str
    assessment: RiskAssessment | None
    error: DemoFailure | None


class ChunkAnalysisResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    transcript: str
    assessment: RiskAssessment | None


PilotRole = Literal["parent", "guardian"]
PilotRiskLevel = Literal["review", "danger"]
PilotSignal = Literal["impersonation", "urgency", "secretCode", "transfer", "remoteApp"]


class CreateFamilyRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    parent_name: str


class JoinFamilyRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    code: str
    name: str
    relation: str


class PilotPerson(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    relation: str
    role: PilotRole


class PilotSession(BaseModel):
    model_config = ConfigDict(extra="forbid")

    family_id: str
    member: PilotPerson
    access_token: str
    invite_code: str | None = None
    invite_expires_at: datetime | None = None


class PilotProfile(BaseModel):
    model_config = ConfigDict(extra="forbid")

    family_id: str
    member: PilotPerson
    parent: PilotPerson
    guardians: list[PilotPerson]


class PilotInvite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str
    expires_at: datetime


class PilotTranscriptLine(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: int
    offset: float
    speaker: Literal["caller", "parent", "unknown"]
    text: str
    flagged: list[str]
    signals: list[PilotSignal]


class PilotAlertInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    caller_detail: str
    channel: Literal["cellular", "whatsapp"]
    started_at: datetime
    raised_at: datetime
    level: PilotRiskLevel
    signals: list[PilotSignal]
    evidence: list[PilotTranscriptLine]


class PilotDecisionInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    verdict: Literal["scam", "safe"]


class PilotDecision(BaseModel):
    model_config = ConfigDict(extra="forbid")

    by: PilotPerson
    verdict: Literal["scam", "safe"]
    at: datetime


class PilotAlert(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    parent: PilotPerson
    caller_detail: str
    channel: Literal["cellular", "whatsapp"]
    started_at: datetime
    raised_at: datetime
    level: PilotRiskLevel
    signals: list[PilotSignal]
    evidence: list[PilotTranscriptLine]
    recipients: list[PilotPerson]
    decision: PilotDecision | None
    call_ended: bool


class PilotDecisionResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    accepted: bool
    decision: PilotDecision


class PushTokenRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    token: str
    environment: Literal["sandbox", "production"] = "sandbox"
