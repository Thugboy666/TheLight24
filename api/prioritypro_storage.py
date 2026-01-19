from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .db import get_meta_value, set_meta_value
from .prioritypro_engine import merge_prioritypro_config

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data" / "prioritypro"
INPUTS_DIR = DATA_DIR / "inputs"
EXPORTS_DIR = DATA_DIR / "exports"
AUDIT_FILE = DATA_DIR / "audit.jsonl"
LAST_RUN_FILE = DATA_DIR / "last_run.json"

CONFIG_KEY = "prioritypro_config"


def _ensure_dirs() -> None:
    INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)


def load_prioritypro_config() -> dict[str, Any]:
    raw = get_meta_value(CONFIG_KEY)
    payload: dict[str, Any] = {}
    if raw:
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {}
    return merge_prioritypro_config(payload)


def save_prioritypro_config(config: dict[str, Any]) -> dict[str, Any]:
    merged = merge_prioritypro_config(config)
    set_meta_value(CONFIG_KEY, json.dumps(merged, ensure_ascii=False))
    return merged


def save_prioritypro_import_data(
    kind: str,
    records: list[dict[str, Any]],
    stats: dict[str, Any],
    filename: str,
) -> dict[str, Any]:
    _ensure_dirs()
    payload = {
        "kind": kind,
        "filename": filename,
        "imported_at": datetime.now(timezone.utc).isoformat(),
        "records": records,
        "stats": stats,
    }
    target = INPUTS_DIR / f"{kind}.json"
    target.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return payload


def load_prioritypro_import_data(kind: str) -> dict[str, Any] | None:
    target = INPUTS_DIR / f"{kind}.json"
    if not target.exists():
        return None
    try:
        return json.loads(target.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def save_prioritypro_last_run(payload: dict[str, Any]) -> dict[str, Any]:
    _ensure_dirs()
    LAST_RUN_FILE.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return payload


def load_prioritypro_last_run() -> dict[str, Any] | None:
    if not LAST_RUN_FILE.exists():
        return None
    try:
        return json.loads(LAST_RUN_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def log_prioritypro_event(action: str, details: dict[str, Any]) -> None:
    _ensure_dirs()
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "action": action,
        "details": details,
    }
    with AUDIT_FILE.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
