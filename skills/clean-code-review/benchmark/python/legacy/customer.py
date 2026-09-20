"""Customer — DOMAIN entity. Part of the flat-sprawl fixture for arch-17."""


class Customer:
    """A customer identified by an opaque id."""

    def __init__(self, customer_id: str, name: str) -> None:
        self._customer_id = customer_id
        self._name = name

    @property
    def name(self) -> str:
        return self._name
