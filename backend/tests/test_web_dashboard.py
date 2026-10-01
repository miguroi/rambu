import json
import subprocess
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ScenarioParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.in_scenarios = False
        self.values: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "select" and values.get("id") == "scenario-select":
            self.in_scenarios = True
        elif tag == "option" and self.in_scenarios:
            self.values.append((values.get("value", ""), values.get("data-audio", "")))

    def handle_endtag(self, tag: str) -> None:
        if tag == "select":
            self.in_scenarios = False


def test_dashboard_exposes_only_the_four_canonical_scenarios() -> None:
    parser = ScenarioParser()
    parser.feed((ROOT / "backend/web/index.html").read_text())

    assert parser.values == [
        ("bank-otp", "/samples/bank-otp.wav"),
        ("kecelakaan-transfer", "/samples/kecelakaan-transfer.wav"),
        ("kurir-aplikasi", "/samples/kurir-aplikasi.wav"),
        ("tetangga-aman", "/samples/tetangga-aman.wav"),
    ]


def test_terminal_error_clears_stale_assessment_and_stops_browser_session() -> None:
    script_path = ROOT / "backend/web/app.js"
    harness = r"""
const fs = require("fs");
const vm = require("vm");
const elements = new Map();
let clearedTimers = 0;

function element(id) {
  if (elements.has(id)) return elements.get(id);
  const value = {
    id,
    hidden: false,
    textContent: "",
    dataset: {},
    style: {},
    disabled: false,
    currentTime: 0,
    paused: false,
    children: [],
    selectedOptions: [{ dataset: { audio: "/samples/bank-otp.wav" } }],
    addEventListener() {},
    replaceChildren() { this.children = []; },
    appendChild(child) { this.children.push(child); },
    play() { this.paused = false; return Promise.resolve(); },
    pause() { this.paused = true; },
  };
  elements.set(id, value);
  return value;
}

const context = {
  document: {
    querySelector(selector) { return element(selector.slice(1)); },
    createElement() { return element(`created-${elements.size}`); },
  },
  window: {
    clearTimeout() { clearedTimers += 1; },
    setTimeout() { return 7; },
  },
  fetch: async () => { throw new Error("not called"); },
  console,
  setTimeout,
  clearTimeout,
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(process.argv[1], "utf8"), context);
vm.runInContext(`
  renderSnapshot({
    status: "running", progress: 50, transcript: "contoh",
    assessment: {
      risk_level: "high_risk", signals: ["urgency"],
      evidence: [{quote: "contoh", signals: ["urgency"]}],
      explanation: "lama", recommended_action: "lama"
    }, error: null
  });
  renderSnapshot({
    status: "error", progress: 50, transcript: "contoh",
    assessment: null,
    error: {code: "analysis_timeout", message: "Langflow gagal."}
  });
`, context);

console.log(JSON.stringify({
  riskHidden: element("risk-banner").hidden,
  emptyHidden: element("assessment-empty").hidden,
  risk: element("risk-banner").dataset.risk,
  riskText: element("risk-value").textContent,
  indicators: element("indicator-list").children.length,
  explanation: element("explanation-text").textContent,
  action: element("action-text").textContent,
  audioPaused: element("call-audio").paused,
  status: element("processing-status").textContent,
  state: element("processing-status").dataset.state,
  error: element("error-message").textContent,
  clearedTimers,
}));
"""

    completed = subprocess.run(
        ["node", "-e", harness, str(script_path)],
        check=True,
        capture_output=True,
        text=True,
    )
    result = json.loads(completed.stdout)

    assert result == {
        "riskHidden": True,
        "emptyHidden": False,
        "risk": "pending",
        "riskText": "Menunggu analisis",
        "indicators": 0,
        "explanation": "",
        "action": "",
        "audioPaused": True,
        "status": "Gagal",
        "state": "error",
        "error": "Langflow gagal.",
        "clearedTimers": 1,
    }
