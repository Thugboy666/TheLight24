import uuid
from datetime import datetime

def now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"

def gen_request_id() -> str:
    return str(uuid.uuid4())
