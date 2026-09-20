"""Money — DOMAIN value object. Part of the flat-sprawl fixture for arch-17."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Money:
    """An immutable amount in minor units plus a currency code."""

    amount_cents: int
    currency: str

    def add(self, other: "Money") -> "Money":
        return Money(self.amount_cents + other.amount_cents, self.currency)
