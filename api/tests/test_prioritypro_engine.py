from datetime import date

from api.prioritypro_engine import build_prioritypro_results


def test_prioritypro_engine_basic_calculation():
    state_records = [
        {
            "customer_id": "1",
            "ragione_sociale": "Alpha",
            "piva": "IT0001",
            "priority_enabled": True,
            "pro_enabled": True,
            "shipments_free_used_this_week": 0,
            "points_balance_total": 120,
            "points_balance_earned": 100,
            "points_balance_purchased": 20,
        },
        {
            "customer_id": "2",
            "ragione_sociale": "Beta",
            "piva": "IT0002",
            "priority_enabled": True,
            "pro_enabled": False,
            "shipments_free_used_this_week": 1,
            "points_balance_total": 50,
            "points_balance_earned": 50,
            "points_balance_purchased": 0,
        },
    ]
    order_records = [
        {
            "order_id": "o1",
            "customer_id": "1",
            "order_date": date(2024, 9, 2),
            "imponibile": 100.0,
            "subcategoria": "remanufactured toner",
            "reman_detected": True,
        },
        {
            "order_id": "o2",
            "customer_id": "1",
            "order_date": date(2024, 9, 3),
            "imponibile": 120.0,
            "subcategoria": "ink",
            "reman_detected": False,
        },
        {
            "order_id": "o3",
            "customer_id": "1",
            "order_date": date(2024, 9, 4),
            "imponibile": 80.0,
            "subcategoria": "ink",
            "reman_detected": False,
        },
        {
            "order_id": "o4",
            "customer_id": "2",
            "order_date": date(2024, 9, 5),
            "imponibile": 50.0,
            "subcategoria": "ink",
            "reman_detected": False,
        },
    ]
    config = {
        "priority": {
            "markup_sicurezza": 0.4,
            "free_shipments_per_week": 1,
            "min_orders_for_avg": 3,
            "smp_default": 200,
            "round_up_mode": "unit",
            "anti_abuse_threshold_per_week": 2,
        },
        "pro": {"regola_2x_attiva": True},
    }

    results, summary = build_prioritypro_results(state_records, order_records, config)
    result_by_customer = {row["customer_id"]: row for row in results}

    alpha = result_by_customer["1"]
    assert alpha["ha_aderito"] == "Sì"
    assert alpha["smp"] == 140
    assert alpha["smp_source"] == "avg"
    assert alpha["shipments_free_remaining"] == 1
    assert alpha["reman_detected"] is True
    assert alpha["reman_orders"] == 1
    assert alpha["abuse_flag"] is True

    beta = result_by_customer["2"]
    assert beta["ha_aderito"] == "No"
    assert beta["smp"] == 200
    assert beta["smp_source"] == "fallback"
    assert beta["shipments_free_remaining"] == 0

    assert summary["customers"] == 2
    assert summary["aderito"] == 1
    assert summary["reman_customers"] == 1
    assert summary["abuse_flags"] == 1
