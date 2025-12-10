from core.logger import logger

def audit_event(event_type: str, data: dict):
    logger.info("AUDIT %s: %s", event_type, data)
