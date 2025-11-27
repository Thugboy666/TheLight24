# Placeholder gestione blacklist clienti
from typing import Set

_blacklist: Set[str] = set()

def is_blacklisted(vat_number: str) -> bool:
    return vat_number in _blacklist

def add_blacklist(vat_number: str):
    _blacklist.add(vat_number)
