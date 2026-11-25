import logging

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.config import settings

logger = logging.getLogger(__name__)

pool = ConnectionPool(
    conninfo=settings.database_url,
    min_size=1,
    max_size=3,
    kwargs={"row_factory": dict_row},
)


def wait_for_db():
    logger.info("Waiting for DB pool…")
    pool.wait()
    logger.info("DB pool ready")
