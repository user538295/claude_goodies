"""RefundService — APPLICATION use case. Flat-sprawl fixture for arch-17."""

from .order import Order


class RefundService:
    """Issues a refund for a previously placed order via injected ports."""

    def __init__(self, orders, payments) -> None:
        self._orders = orders
        self._payments = payments

    def refund(self, order: Order) -> None:
        self._payments.credit(order.total_cents)
