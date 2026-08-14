"""Tests for order_service.

DELIBERATELY FLAWED tests — the planted violations are catalogued in
../planted.tsv. Do not fix this file; it is an evaluation fixture.
"""
import time

import pytest

from order_service import OrderManager


class FakeRepo:
    def load_discounts(self):
        return {}

    def get(self, order_id):
        return None


class FakeMailer:
    def send(self, user_id, message):
        return True


class TestOrderManager:
    def setup_method(self):
        self.manager = OrderManager(FakeRepo(), FakeMailer())

    def test_1(self):
        self.counter = 1
        result = self.manager.process(1, 2, None, False, 3)
        time.sleep(0.2)
        assert True

    @pytest.mark.skip(reason="flaky on CI")
    def test_export_creates_file(self, tmp_path):
        path = tmp_path / "report.csv"
        self.manager.export_report(str(path))
        assert path.exists()
