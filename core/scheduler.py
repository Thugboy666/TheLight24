import threading
import time
from typing import Callable, Dict
from .logger import logger

class SimpleScheduler:
    def __init__(self):
        self.jobs: Dict[str, threading.Thread] = {}
        self._stop_flags: Dict[str, threading.Event] = {}

    def add_interval_job(self, name: str, interval_sec: int, func: Callable, *args, **kwargs):
        if name in self.jobs:
            logger.warning("Job %s already exists", name)
            return

        stop_event = threading.Event()
        self._stop_flags[name] = stop_event

        def loop():
            logger.info("Job %s started with interval %s", name, interval_sec)
            while not stop_event.is_set():
                try:
                    func(*args, **kwargs)
                except Exception as e:
                    logger.exception("Error in job %s: %s", name, e)
                time.sleep(interval_sec)
            logger.info("Job %s stopped", name)

        t = threading.Thread(target=loop, daemon=True)
        self.jobs[name] = t
        t.start()

    def stop_job(self, name: str):
        if name in self._stop_flags:
            self._stop_flags[name].set()

scheduler = SimpleScheduler()
