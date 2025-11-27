import json
from pathlib import Path

PROMPTS_DIR = Path(__file__).resolve().parent / "prompts"

_cache = {}

def get_system_prompt(name: str) -> str:
    if name in _cache:
        return _cache[name]
    path = PROMPTS_DIR / f"{name}.json"
    if not path.exists():
        return ""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    text = data.get("system_prompt", "")
    _cache[name] = text
    return text
