const scenarioSelect = document.querySelector("#scenario-select");
const startButton = document.querySelector("#start-button");
const resetButton = document.querySelector("#reset-button");
const audio = document.querySelector("#call-audio");
const statusLabel = document.querySelector("#processing-status");
const progressBar = document.querySelector("#progress-bar");
const progressValue = document.querySelector("#progress-value");
const transcriptEmpty = document.querySelector("#transcript-empty");
const transcriptText = document.querySelector("#transcript-text");
const errorMessage = document.querySelector("#error-message");
const assessmentEmpty = document.querySelector("#assessment-empty");
const riskBanner = document.querySelector("#risk-banner");
const riskValue = document.querySelector("#risk-value");
const indicatorList = document.querySelector("#indicator-list");
const explanationText = document.querySelector("#explanation-text");
const actionText = document.querySelector("#action-text");

const riskLabels = {
  low: "Risiko rendah",
  needs_review: "Perlu ditinjau",
  high_risk: "Risiko tinggi",
};

let sessionId = null;
let pollTimer = null;

scenarioSelect.addEventListener("change", () => {
  audio.src = scenarioSelect.selectedOptions[0].dataset.audio;
});
startButton.addEventListener("click", startDemo);
resetButton.addEventListener("click", resetDemo);

async function startDemo() {
  setBusy(true);
  clearResult();
  statusLabel.textContent = "Memulai";
  statusLabel.dataset.state = "running";

  try {
    const response = await fetch(`/api/demo/${scenarioSelect.value}`, { method: "POST" });
    if (!response.ok) throw new Error(await responseMessage(response));
    const snapshot = await response.json();
    sessionId = snapshot.id;
    resetButton.disabled = false;
    renderSnapshot(snapshot);
    audio.currentTime = 0;
    await audio.play().catch(() => undefined);
    schedulePoll();
  } catch (error) {
    showError(error.message);
    setBusy(false);
  }
}

function schedulePoll() {
  window.clearTimeout(pollTimer);
  pollTimer = window.setTimeout(pollDemo, 700);
}

async function pollDemo() {
  if (!sessionId) return;
  try {
    const response = await fetch(`/api/demo/${sessionId}`);
    if (!response.ok) throw new Error(await responseMessage(response));
    const snapshot = await response.json();
    renderSnapshot(snapshot);
    if (snapshot.status === "running") schedulePoll();
    else setBusy(false);
  } catch (error) {
    showError(error.message);
    setBusy(false);
  }
}

async function resetDemo() {
  window.clearTimeout(pollTimer);
  const previousSession = sessionId;
  sessionId = null;
  audio.pause();
  audio.currentTime = 0;
  if (previousSession) {
    await fetch(`/api/demo/${previousSession}`, { method: "DELETE" }).catch(() => undefined);
  }
  clearResult();
  setBusy(false);
  resetButton.disabled = true;
}

function renderSnapshot(snapshot) {
  progressBar.style.width = `${snapshot.progress}%`;
  progressValue.textContent = `${snapshot.progress}%`;
  statusLabel.dataset.state = snapshot.status;
  statusLabel.textContent = {
    running: "Memproses",
    completed: "Selesai",
    error: "Gagal",
  }[snapshot.status] || "Siap";

  if (snapshot.transcript) {
    transcriptEmpty.hidden = true;
    transcriptText.hidden = false;
    transcriptText.textContent = snapshot.transcript;
  }
  if (snapshot.assessment) renderAssessment(snapshot.assessment);
  if (snapshot.error) showError(snapshot.error);
}

function renderAssessment(assessment) {
  assessmentEmpty.hidden = true;
  riskBanner.hidden = false;
  riskBanner.dataset.risk = assessment.risk_level;
  riskValue.textContent = riskLabels[assessment.risk_level] || assessment.risk_level;
  indicatorList.replaceChildren();
  const indicators = assessment.indicators.length
    ? assessment.indicators
    : ["Tidak ada indikator kuat yang terdeteksi."];
  indicators.forEach((indicator) => {
    const item = document.createElement("li");
    item.textContent = indicator;
    indicatorList.appendChild(item);
  });
  explanationText.textContent = assessment.explanation;
  actionText.textContent = assessment.recommended_action;
}

function clearResult() {
  window.clearTimeout(pollTimer);
  progressBar.style.width = "0%";
  progressValue.textContent = "0%";
  statusLabel.textContent = "Siap";
  statusLabel.dataset.state = "idle";
  transcriptText.textContent = "";
  transcriptText.hidden = true;
  transcriptEmpty.hidden = false;
  errorMessage.hidden = true;
  errorMessage.textContent = "";
  riskBanner.dataset.risk = "pending";
  riskBanner.hidden = true;
  assessmentEmpty.hidden = false;
  riskValue.textContent = "Menunggu analisis";
  indicatorList.replaceChildren();
  explanationText.textContent = "";
  actionText.textContent = "";
}

function setBusy(busy) {
  startButton.disabled = busy;
  startButton.textContent = busy ? "Memproses…" : "Mulai";
  scenarioSelect.disabled = busy;
}

function showError(message) {
  errorMessage.textContent = message;
  errorMessage.hidden = false;
  statusLabel.textContent = "Perlu perhatian";
  statusLabel.dataset.state = "error";
}

async function responseMessage(response) {
  try {
    const body = await response.json();
    return body.detail || `Permintaan gagal (${response.status}).`;
  } catch {
    return `Permintaan gagal (${response.status}).`;
  }
}
