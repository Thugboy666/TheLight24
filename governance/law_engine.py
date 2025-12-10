# Placeholder per motore regole
from typing import Dict, Any

def evaluate_case(case: Dict[str, Any]) -> Dict[str, Any]:
    # TODO: collegare a LLM e regole estese
    decision = {
        "allowed": True,
        "reason": "No blocking rule hit",
    }
    return decision
