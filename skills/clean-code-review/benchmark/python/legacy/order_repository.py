"""PostgresOrderRepository — INFRASTRUCTURE adapter. Flat-sprawl fixture (arch-17)."""

import psycopg2

from .order import Order


class PostgresOrderRepository:
    """Persists orders to PostgreSQL — concrete infrastructure I/O."""

    def __init__(self, dsn: str) -> None:
        self._conn = psycopg2.connect(dsn)

    def save(self, order: Order) -> None:
        with self._conn.cursor() as cur:
            cur.execute("INSERT INTO orders(id) VALUES (%s)", (order.total_cents,))
