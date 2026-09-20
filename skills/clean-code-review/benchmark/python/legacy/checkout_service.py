"""CheckoutService — APPLICATION use case. Flat-sprawl fixture for arch-17.

This is the file the benchmark run adds, which triggers arch-17's read of the
whole flat `legacy/` directory. Do not reorganize — the flat layout is the point.
"""

from .order import Order


class CheckoutService:
    """Orchestrates placing an order through an injected repository port."""

    def __init__(self, orders) -> None:
        self._orders = orders

    def place(self, order: Order) -> None:
        self._orders.save(order)
