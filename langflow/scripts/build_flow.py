from __future__ import annotations

import json
import os
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_STARTER = Path(
    "/Users/sfatimahazzahra/langflow-python/.venv/lib/python3.12/site-packages/"
    "langflow/initial_setup/starter_projects/Basic Prompting.json"
)


def starter_path() -> Path:
    configured = os.getenv("LANGFLOW_STARTER_JSON")
    path = Path(configured).expanduser() if configured else DEFAULT_STARTER
    if not path.exists():
        raise FileNotFoundError(
            "Basic Prompting.json tidak ditemukan. Atur LANGFLOW_STARTER_JSON ke starter flow Langflow."
        )
    return path


def build() -> Path:
    flow = json.loads(starter_path().read_text())
    prefixes = ("ChatInput-", "Prompt-", "LanguageModelComponent-", "ChatOutput-")
    nodes = [deepcopy(node) for node in flow["data"]["nodes"] if node["id"].startswith(prefixes)]
    node_ids = {node["id"] for node in nodes}

    prompt = next(node for node in nodes if node["id"].startswith("Prompt-"))
    model = next(node for node in nodes if node["id"].startswith("LanguageModelComponent-"))
    prompt["data"]["node"]["template"]["template"]["value"] = (
        ROOT / "langflow" / "prompts" / "system_prompt.md"
    ).read_text()
    prompt["data"]["node"]["template"]["use_double_brackets"]["value"] = True

    template = model["data"]["node"]["template"]
    template["model"]["value"] = [
        {
            "provider": "OpenRouter",
            "name": "openai/gpt-4o-mini",
            "icon": "OpenRouter",
            "tool_calling": True,
            "reasoning": False,
            "search": False,
            "preview": False,
            "not_supported": False,
            "deprecated": False,
            "default": True,
            "model_type": "llm",
            "created": 0,
        }
    ]
    template["model_name"]["value"] = ""
    template["provider"]["value"] = ""
    template["temperature"]["value"] = 0.0

    flow["name"] = "Rambu"
    flow["description"] = "Menilai indikasi risiko dari transkrip panggilan yang telah disamarkan."
    flow["endpoint_name"] = "rambu"
    flow["last_tested_version"] = "1.12.3"
    flow["tags"] = ["call safety", "indonesian", "risk analysis"]
    flow["data"]["nodes"] = nodes
    flow["data"]["edges"] = [
        deepcopy(edge)
        for edge in flow["data"]["edges"]
        if edge["source"] in node_ids and edge["target"] in node_ids
    ]

    output = ROOT / "langflow" / "flows" / "Rambu.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(flow, indent=2, ensure_ascii=False) + "\n")
    return output


if __name__ == "__main__":
    print(build())
