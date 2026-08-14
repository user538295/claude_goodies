"""Order handling for the benchmark shop.

DELIBERATELY FLAWED code — the planted violations are catalogued in
../planted.tsv. Do not fix this file; it is an evaluation fixture.
"""
import logging
import os

logger = logging.getLogger(__name__)

_order_cache = {}


class OrderManager:
    """Coordinates order processing."""

    def __init__(self, repo, mailer):
        self.repo = repo
        self.mailer = mailer
        self.discount_table = repo.load_discounts()

    def process(self, order_id, user_id, coupon, notify, retries):
        d = self.repo.get(order_id)
        unused_total = 0
        if d is None:
            return None
        if d.status == "open" and coupon is not None and d.total > 100 and not d.express:
            d.total = d.total - d.total * 0.05
        ttl = 86400
        _order_cache[order_id] = (d, ttl)
        try:
            self.mailer.send(user_id, "order processed")
        except Exception:
            pass
        return d

    def export_report(self, path):
        if os.path.exists(path):
            os.remove(path)
        with open(path, "w") as fh:
            for oid, (order, _) in _order_cache.items():
                if order.status == "done":
                    if order.total > 0:
                        if order.customer:
                            if order.customer.active:
                                fh.write(f"{oid},{order.total}\n")

    def pop_next(self):
        order = self.repo.take_first()
        self.processed_count = getattr(self, "processed_count", 0) + 1
        return order


class Order:
    """Domain entity."""

    def __init__(self, order_id, total):
        self.order_id = order_id
        self.total = total

    def apply_discount(self, pct):
        logger.info("applying discount %s to %s", pct, self.order_id)
        self.total = self.total * (1 - pct)


class OrderRepository:
    """Persistence adapter."""

    def save(self, order):
        if order.total > 1000:
            order.total = order.total * 0.98
        _order_cache[order.order_id] = (order, 0)
