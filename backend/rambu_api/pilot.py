import hashlib
import json
import secrets
import sqlite3
import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

from .models import (
    PilotAlert,
    PilotAlertInput,
    PilotDecision,
    PilotPerson,
    PilotProfile,
    PilotSession,
)


class PilotError(RuntimeError):
    pass


class AuthenticationError(PilotError):
    pass


class AuthorizationError(PilotError):
    pass


class InviteError(PilotError):
    pass


class MissingAlertError(PilotError):
    pass


class DecisionConflict(PilotError):
    def __init__(self, decision: PilotDecision) -> None:
        super().__init__("Peringatan sudah dijawab.")
        self.decision = decision


def _now() -> datetime:
    return datetime.now(UTC)


def _iso(value: datetime) -> str:
    return value.astimezone(UTC).isoformat()


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


class PilotStore:
    """Small persistent store for a controlled two-phone pilot.

    Device tokens are random bearer credentials and only their hashes are stored.
    SQLite's immediate transaction provides the first-decision-wins guarantee.
    """

    def __init__(self, path: str | Path) -> None:
        self.path = str(path)
        if self.path != ":memory:":
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(self.path, check_same_thread=False)
        self._connection.row_factory = sqlite3.Row
        self._lock = threading.RLock()
        with self._connection:
            self._connection.execute("PRAGMA foreign_keys = ON")
            self._connection.execute("PRAGMA journal_mode = WAL")
            self._connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS families (
                    id TEXT PRIMARY KEY,
                    invite_code TEXT UNIQUE NOT NULL,
                    invite_expires_at TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS members (
                    id TEXT PRIMARY KEY,
                    family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
                    role TEXT NOT NULL CHECK(role IN ('parent', 'guardian')),
                    name TEXT NOT NULL,
                    relation TEXT NOT NULL,
                    token_hash TEXT UNIQUE NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS alerts (
                    id TEXT PRIMARY KEY,
                    family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
                    caller_detail TEXT NOT NULL,
                    channel TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    raised_at TEXT NOT NULL,
                    level TEXT NOT NULL,
                    signals_json TEXT NOT NULL,
                    evidence_json TEXT NOT NULL,
                    decision_member_id TEXT REFERENCES members(id),
                    decision_verdict TEXT,
                    decision_at TEXT,
                    call_ended INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS alerts_family_updated
                ON alerts(family_id, updated_at DESC);

                CREATE TABLE IF NOT EXISTS push_tokens (
                    token TEXT PRIMARY KEY,
                    member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    environment TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )

    def close(self) -> None:
        with self._lock:
            self._connection.close()

    def create_family(self, parent_name: str) -> PilotSession:
        name = self._required(parent_name, "Nama orang tua")
        family_id = uuid4().hex
        member_id = uuid4().hex
        token = secrets.token_urlsafe(32)
        code = self._new_code()
        now = _now()
        expires = now + timedelta(minutes=10)
        with self._lock, self._connection:
            self._connection.execute(
                "INSERT INTO families VALUES (?, ?, ?, ?)",
                (family_id, code, _iso(expires), _iso(now)),
            )
            self._connection.execute(
                "INSERT INTO members VALUES (?, ?, 'parent', ?, 'Orang tua', ?, ?)",
                (member_id, family_id, name, _token_hash(token), _iso(now)),
            )
        return PilotSession(
            family_id=family_id,
            member=PilotPerson(id=member_id, name=name, relation="Orang tua", role="parent"),
            access_token=token,
            invite_code=code,
            invite_expires_at=expires,
        )

    def join_family(self, code: str, name: str, relation: str) -> PilotSession:
        normalized_code = "".join(character for character in code if character.isdigit())
        if len(normalized_code) != 6:
            raise InviteError("Kode undangan harus 6 angka.")
        name = self._required(name, "Nama pengawas")
        relation = self._required(relation, "Hubungan")
        with self._lock:
            family = self._connection.execute(
                "SELECT * FROM families WHERE invite_code = ?", (normalized_code,)
            ).fetchone()
            if family is None:
                raise InviteError("Kode undangan tidak ditemukan.")
            if datetime.fromisoformat(family["invite_expires_at"]) <= _now():
                raise InviteError("Kode undangan sudah kedaluwarsa.")
            guardian_count = self._connection.execute(
                "SELECT COUNT(*) FROM members WHERE family_id = ? AND role = 'guardian'",
                (family["id"],),
            ).fetchone()[0]
            if guardian_count >= 5:
                raise InviteError("Keluarga ini sudah memiliki terlalu banyak pengawas.")

            member_id = uuid4().hex
            token = secrets.token_urlsafe(32)
            now = _now()
            with self._connection:
                self._connection.execute(
                    "INSERT INTO members VALUES (?, ?, 'guardian', ?, ?, ?, ?)",
                    (member_id, family["id"], name, relation, _token_hash(token), _iso(now)),
                )
        return PilotSession(
            family_id=family["id"],
            member=PilotPerson(id=member_id, name=name, relation=relation, role="guardian"),
            access_token=token,
        )

    def renew_invite(self, token: str) -> tuple[str, datetime]:
        member = self.authenticate(token)
        if member["role"] != "parent":
            raise AuthorizationError("Hanya orang tua yang dapat membuat undangan.")
        code = self._new_code()
        expires = _now() + timedelta(minutes=10)
        with self._lock, self._connection:
            self._connection.execute(
                "UPDATE families SET invite_code = ?, invite_expires_at = ? WHERE id = ?",
                (code, _iso(expires), member["family_id"]),
            )
        return code, expires

    def authenticate(self, token: str) -> sqlite3.Row:
        if not token:
            raise AuthenticationError("Token perangkat diperlukan.")
        with self._lock:
            member = self._connection.execute(
                "SELECT * FROM members WHERE token_hash = ?", (_token_hash(token),)
            ).fetchone()
        if member is None:
            raise AuthenticationError("Token perangkat tidak valid.")
        return member

    def profile(self, token: str) -> PilotProfile:
        member = self.authenticate(token)
        people = self._family_members(member["family_id"])
        parent = next(person for person in people if person.role == "parent")
        return PilotProfile(
            family_id=member["family_id"],
            member=self._person(member),
            parent=parent,
            guardians=[person for person in people if person.role == "guardian"],
        )

    def register_push_token(self, access_token: str, push_token: str, environment: str) -> None:
        member = self.authenticate(access_token)
        cleaned = push_token.strip().lower()
        if not cleaned or any(character not in "0123456789abcdef" for character in cleaned):
            raise ValueError("Token APNs tidak valid.")
        if environment not in {"sandbox", "production"}:
            raise ValueError("Lingkungan APNs tidak valid.")
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO push_tokens (token, member_id, environment, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(token) DO UPDATE SET
                    member_id = excluded.member_id,
                    environment = excluded.environment,
                    updated_at = excluded.updated_at
                """,
                (cleaned, member["id"], environment, _iso(_now())),
            )

    def notification_tokens(
        self, access_token: str, target_role: str, environment: str
    ) -> list[str]:
        member = self.authenticate(access_token)
        with self._lock:
            rows = self._connection.execute(
                """
                SELECT push_tokens.token
                FROM push_tokens
                JOIN members ON members.id = push_tokens.member_id
                WHERE members.family_id = ? AND members.role = ?
                  AND push_tokens.environment = ?
                """,
                (member["family_id"], target_role, environment),
            ).fetchall()
        return [row["token"] for row in rows]

    def publish_alert(self, token: str, value: PilotAlertInput) -> PilotAlert:
        alert, _ = self.publish_alert_result(token, value)
        return alert

    def publish_alert_result(self, token: str, value: PilotAlertInput) -> tuple[PilotAlert, bool]:
        member = self.authenticate(token)
        if member["role"] != "parent":
            raise AuthorizationError("Hanya perangkat orang tua yang dapat membuat peringatan.")
        now = _iso(_now())
        signals = json.dumps(value.signals, ensure_ascii=False)
        evidence = json.dumps([line.model_dump(mode="json") for line in value.evidence], ensure_ascii=False)
        with self._lock, self._connection:
            existing = self._connection.execute(
                "SELECT * FROM alerts WHERE id = ?", (str(value.id),)
            ).fetchone()
            if existing is not None and existing["family_id"] != member["family_id"]:
                raise AuthorizationError("Peringatan berasal dari keluarga lain.")
            if existing is not None:
                old_evidence = json.loads(existing["evidence_json"])
                if len(old_evidence) > len(value.evidence):
                    return self._alert(str(value.id), member["family_id"]), False
                if existing["level"] == "danger":
                    value.level = "danger"
            should_notify = existing is None or (existing["level"] != value.level and value.level == "danger")
            self._connection.execute(
                """
                INSERT INTO alerts (
                    id, family_id, caller_detail, channel, started_at, raised_at,
                    level, signals_json, evidence_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    caller_detail = excluded.caller_detail,
                    level = excluded.level,
                    signals_json = excluded.signals_json,
                    evidence_json = excluded.evidence_json,
                    updated_at = excluded.updated_at
                """,
                (
                    str(value.id), member["family_id"], value.caller_detail, value.channel,
                    _iso(value.started_at), _iso(value.raised_at), value.level,
                    signals, evidence, now,
                ),
            )
        return self._alert(str(value.id), member["family_id"]), should_notify

    def alerts(self, token: str) -> list[PilotAlert]:
        member = self.authenticate(token)
        with self._lock:
            rows = self._connection.execute(
                "SELECT id FROM alerts WHERE family_id = ? ORDER BY updated_at DESC LIMIT 100",
                (member["family_id"],),
            ).fetchall()
        return [self._alert(row["id"], member["family_id"]) for row in rows]

    def decide(self, token: str, alert_id: str, verdict: str) -> PilotDecision:
        member = self.authenticate(token)
        if member["role"] != "guardian":
            raise AuthorizationError("Hanya pengawas yang dapat memberi keputusan.")
        if verdict not in {"scam", "safe"}:
            raise ValueError("Keputusan tidak valid.")
        decided_at = _now()
        with self._lock:
            self._connection.execute("BEGIN IMMEDIATE")
            try:
                alert = self._connection.execute(
                    "SELECT * FROM alerts WHERE id = ? AND family_id = ?",
                    (alert_id, member["family_id"]),
                ).fetchone()
                if alert is None:
                    raise MissingAlertError("Peringatan tidak ditemukan.")
                if alert["decision_member_id"] is not None:
                    decision = self._decision(alert)
                    self._connection.rollback()
                    raise DecisionConflict(decision)
                self._connection.execute(
                    """
                    UPDATE alerts
                    SET decision_member_id = ?, decision_verdict = ?, decision_at = ?, updated_at = ?
                    WHERE id = ? AND decision_member_id IS NULL
                    """,
                    (member["id"], verdict, _iso(decided_at), _iso(decided_at), alert_id),
                )
                self._connection.commit()
            except Exception:
                if self._connection.in_transaction:
                    self._connection.rollback()
                raise
        return PilotDecision(by=self._person(member), verdict=verdict, at=decided_at)

    def end_alert(self, token: str, alert_id: str) -> PilotAlert:
        member = self.authenticate(token)
        if member["role"] != "parent":
            raise AuthorizationError("Hanya perangkat orang tua yang dapat mengakhiri panggilan.")
        with self._lock, self._connection:
            cursor = self._connection.execute(
                "UPDATE alerts SET call_ended = 1, updated_at = ? WHERE id = ? AND family_id = ?",
                (_iso(_now()), alert_id, member["family_id"]),
            )
            if cursor.rowcount == 0:
                raise MissingAlertError("Peringatan tidak ditemukan.")
        return self._alert(alert_id, member["family_id"])

    def _alert(self, alert_id: str, family_id: str) -> PilotAlert:
        with self._lock:
            row = self._connection.execute(
                "SELECT * FROM alerts WHERE id = ? AND family_id = ?", (alert_id, family_id)
            ).fetchone()
        if row is None:
            raise MissingAlertError("Peringatan tidak ditemukan.")
        people = self._family_members(family_id)
        parent = next(person for person in people if person.role == "parent")
        return PilotAlert(
            id=row["id"],
            parent=parent,
            caller_detail=row["caller_detail"],
            channel=row["channel"],
            started_at=row["started_at"],
            raised_at=row["raised_at"],
            level=row["level"],
            signals=json.loads(row["signals_json"]),
            evidence=json.loads(row["evidence_json"]),
            recipients=[person for person in people if person.role == "guardian"],
            decision=self._decision(row) if row["decision_member_id"] else None,
            call_ended=bool(row["call_ended"]),
        )

    def _decision(self, alert: sqlite3.Row) -> PilotDecision:
        with self._lock:
            member = self._connection.execute(
                "SELECT * FROM members WHERE id = ?", (alert["decision_member_id"],)
            ).fetchone()
        return PilotDecision(
            by=self._person(member), verdict=alert["decision_verdict"], at=alert["decision_at"]
        )

    def _family_members(self, family_id: str) -> list[PilotPerson]:
        with self._lock:
            members = self._connection.execute(
                "SELECT * FROM members WHERE family_id = ? ORDER BY created_at", (family_id,)
            ).fetchall()
        return [self._person(member) for member in members]

    @staticmethod
    def _person(member: sqlite3.Row) -> PilotPerson:
        return PilotPerson(
            id=member["id"], name=member["name"], relation=member["relation"], role=member["role"]
        )

    def _new_code(self) -> str:
        with self._lock:
            for _ in range(20):
                code = f"{secrets.randbelow(1_000_000):06d}"
                exists = self._connection.execute(
                    "SELECT 1 FROM families WHERE invite_code = ?", (code,)
                ).fetchone()
                if exists is None:
                    return code
        raise PilotError("Tidak dapat membuat kode undangan.")

    @staticmethod
    def _required(value: str, label: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError(f"{label} diperlukan.")
        if len(cleaned) > 80:
            raise ValueError(f"{label} terlalu panjang.")
        return cleaned
