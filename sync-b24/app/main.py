import logging
import signal
import sys
import threading

from app.clients.bitrix import BitrixClient
from app.config import settings
from app.db import pool, wait_for_db
from app.workers.absence import AbsenceWorker
from app.workers.scud_departments import ScudDepartmentsWorker
from app.workers.scud_events import ScudEventsWorker
from app.workers.scud_regime import ScudRegimeWorker
from app.workers.scud_sessions import ScudSessionsWorker
from app.workers.scud_users import ScudUsersWorker
from app.workers.timeman import TimemanWorker

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

shutdown_event = threading.Event()


def handle_signal(signum, frame):
    logger.info("Received signal %d, shutting down…", signum)
    shutdown_event.set()


def main():
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    wait_for_db()
    client = BitrixClient()

    workers = [
        ScudEventsWorker(client),
        ScudSessionsWorker(client),
        ScudRegimeWorker(client),
        TimemanWorker(client),
        AbsenceWorker(client),
        ScudUsersWorker(client),
        ScudDepartmentsWorker(client),
    ]

    threads = []
    for worker in workers:
        t = threading.Thread(target=worker.run_forever, daemon=True)
        t.start()
        threads.append(t)

    logger.info("All workers started, waiting for shutdown signal…")
    shutdown_event.wait()
    logger.info("Shutting down…")
    pool.close()
    sys.exit(0)


if __name__ == "__main__":
    main()
