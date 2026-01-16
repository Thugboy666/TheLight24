import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch

from api.analytics import ANALYTICS_TZ, compute_sales_metrics, get_customer_analytics, reset_cache


class SalesMetricsTests(unittest.TestCase):
    def test_compute_sales_metrics_handles_periods_and_categories(self):
        now = datetime.now(timezone.utc).replace(day=15, hour=0, minute=0, second=0, microsecond=0)
        last_month = now - timedelta(days=35)
        two_months = now - timedelta(days=65)
        orders = [
            {"order_date": now.isoformat(), "total_amount": 100, "cause": "Office"},
            {"order_date": last_month.isoformat(), "total_amount": 200, "cause": "Consumabili"},
            {"order_date": two_months.isoformat(), "total_amount": 50, "cause": "Office"},
        ]

        stats = compute_sales_metrics(orders)
        self.assertAlmostEqual(stats["period"]["current_month_total"], 100)
        self.assertAlmostEqual(stats["period"]["last_3_months_total"], 250)
        categories = {c["name"]: c["total"] for c in stats["categories"]}
        self.assertIn("Office", categories)
        self.assertEqual(categories.get("Consumabili"), 200)

    def test_compute_sales_metrics_handles_naive_and_aware_dates(self):
        now = datetime.now(ANALYTICS_TZ).replace(day=15, hour=10, minute=0, second=0, microsecond=0)
        last_month = now - timedelta(days=32)
        naive_date = now.replace(tzinfo=None)
        aware_date = now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
        iso_no_tz = now.replace(tzinfo=None).isoformat()
        orders = [
            {"order_date": naive_date, "total_amount": 120, "cause": "Office"},
            {"order_date": aware_date, "total_amount": 80, "cause": "Office"},
            {"order_date": iso_no_tz, "total_amount": 25, "cause": "Office"},
            {"order_date": last_month.isoformat(), "total_amount": 50, "cause": "Consumabili"},
        ]

        stats = compute_sales_metrics(orders)
        self.assertAlmostEqual(stats["period"]["current_month_total"], 225)
        self.assertAlmostEqual(stats["period"]["last_3_months_total"], 50)
        categories = {c["name"]: c["total"] for c in stats["categories"]}
        self.assertEqual(categories.get("Office"), 225)
        debug = stats["debug"]
        self.assertEqual(debug["invalid_dates_count"], 0)
        self.assertEqual(debug["total_orders_seen"], 4)
        self.assertIsNotNone(debug["earliest_order_date"])
        self.assertIsNotNone(debug["latest_order_date"])

    def test_compute_sales_metrics_counts_invalid_dates(self):
        now = datetime.now(timezone.utc)
        orders = [
            {"order_date": "not-a-date", "total_amount": 10, "cause": "Office"},
            {"order_date": 45000, "total_amount": 20, "cause": "Office"},
            {"order_date": now, "total_amount": 30, "cause": "Office"},
        ]

        stats = compute_sales_metrics(orders)
        debug = stats["debug"]
        self.assertEqual(debug["total_orders_seen"], 3)
        self.assertEqual(debug["invalid_dates_count"], 2)
        self.assertEqual(debug["parsed_orders_count"], 1)
        self.assertIsNotNone(debug["earliest_order_date"])
        self.assertIsNotNone(debug["latest_order_date"])


class AnalyticsCacheTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        reset_cache()

    async def test_cache_returns_cached_payload(self):
        demo_orders = [
            {"order_date": datetime.now(timezone.utc).isoformat(), "total_amount": 120, "cause": "Demo"}
        ]
        with patch(
            "api.analytics.get_customer_risk_and_upsell_suggestions",
            AsyncMock(return_value={"churn_risk_score": 10, "churn_risk_level": "low", "upsell_suggestions": []}),
        ):
            first = await get_customer_analytics(99, "demo@example.com", refresh=True, orders_override=demo_orders)
            self.assertFalse(first["cached"])
            second = await get_customer_analytics(99, "demo@example.com", refresh=False, orders_override=demo_orders)
            self.assertTrue(second["cached"])
            self.assertEqual(second["customer_id"], "99")


if __name__ == "__main__":
    unittest.main()
