# Placeholder per un semplice sistema di voto
from typing import Dict

def simple_vote(options: Dict[str, int]) -> str:
    if not options:
        return ""
    return max(options, key=options.get)
