# Placeholder per automazioni giornaliere
from core.scheduler import scheduler
from services.sync_readypro import sync_readypro_once

def register_jobs():
    # esempio: sync Ready Pro ogni 10 minuti
    scheduler.add_interval_job("sync_readypro", interval_sec=600, func=sync_readypro_once)
