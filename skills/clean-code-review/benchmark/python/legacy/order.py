"""Order — DOMAIN entity. Part of the flat-sprawl fixture for arch-17.

DELIBERATELY FLAWED layout — see ../../planted.tsv. Do not reorganize.
"""


class Order:
    """A placed order with its line total, in minor currency units."""

    def __init__(self, order_id: str, total_cents: int) -> None:
        self._order_id = order_id
        self._total_cents = total_cents

    @property
    def total_cents(self) -> int:
        return self._total_cents
