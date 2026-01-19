from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterable

from .xlsx_utils import normalize_header, read_xlsx_table, safe_float, safe_int


STATE_DEFAULT_MAPPING = {
    "customer_id": ["customer_id", "id_cliente", "cliente_id", "id"],
    "ragione_sociale": ["ragione_sociale", "ragione sociale", "azienda", "nome"],
    "piva": ["piva", "p.iva", "partita_iva", "partita iva"],
    "priority_enabled": ["priority_enabled", "priority", "priority_attivo"],
    "pro_enabled": ["pro_enabled", "pro", "pro_attivo"],
    "shipments_free_used_this_week": [
        "shipments_free_used_this_week",
        "spedizioni_free_usate_settimana",
        "spedizioni_usate_settimana",
    ],
    "shipments_free_week_start": [
        "shipments_free_week_start",
        "last_reset_week",
        "inizio_settimana",
    ],
    "points_balance_total": ["points_balance_total", "punti_totali", "points_total"],
    "points_balance_earned": [
        "points_balance_earned",
        "punti_guadagnati",
        "points_earned",
    ],
    "points_balance_purchased": [
        "points_balance_purchased",
        "punti_acquistati",
        "points_purchased",
    ],
}

ORDERS_DEFAULT_MAPPING = {
    "order_id": ["order_id", "id_ordine", "ordine_id"],
    "customer_id": ["customer_id", "id_cliente", "cliente_id"],
    "order_date": ["order_date", "data_ordine", "data"],
    "imponibile": ["imponibile", "totale", "imponibile_totale"],
    "subcategoria": ["subcategoria", "categoria", "sottocategoria"],
}


DEFAULT_CONFIG = {
    "priority": {
        "priority_fee_eur": 99,
        "markup_sicurezza": 0.40,
        "free_shipments_per_week": 1,
        "min_orders_for_avg": 3,
        "smp_default": 250,
        "round_up_mode": "unit",
        "pilot_region": "Campania",
        "anti_abuse_threshold_per_week": 3,
    },
    "pro": {
        "earn_rate_eur_per_point": 10,
        "topup_eur_to_points_ratio": 1,
        "min_topup_monthly": 0,
        "min_topup_yearly": 0,
        "bonus_points_pct": 0,
        "max_discount_pct": 0,
        "points_expiry_months": None,
        "regola_2x_attiva": True,
    },
    "integration": {
        "regola_punti_sconto_spedizione": True,
        "extra_free_shipment_points_cost": None,
        "priorita_consumo": "spedizione_gratis_poi_punti",
    },
    "mappings": {
        "state": STATE_DEFAULT_MAPPING,
        "orders": ORDERS_DEFAULT_MAPPING,
    },
    "reman_subcategory_match": "remanufactured",
}


@dataclass
class ParseStats:
    processed: int = 0
    valid: int = 0
    invalid: int = 0


def _normalize_mapping_value(value: Any, fallback: list[str]) -> list[str]:
    if isinstance(value, list):
        items = [str(v).strip() for v in value if str(v).strip()]
        return items or fallback
    if isinstance(value, str):
        items = [part.strip() for part in value.split(",") if part.strip()]
        return items or fallback
    return fallback


def _merge_mapping(default: dict[str, list[str]], incoming: dict[str, Any]) -> dict[str, list[str]]:
    merged: dict[str, list[str]] = {}
    for key, fallback in default.items():
        merged[key] = _normalize_mapping_value(incoming.get(key), fallback)
    for key, value in incoming.items():
        if key not in merged:
            merged[key] = _normalize_mapping_value(value, [])
    return merged


def merge_prioritypro_config(custom: dict[str, Any] | None) -> dict[str, Any]:
    custom = custom or {}
    merged = json.loads(json.dumps(DEFAULT_CONFIG))
    for section in ("priority", "pro", "integration", "mappings"):
        if isinstance(custom.get(section), dict):
            merged[section].update(custom[section])
    if isinstance(custom.get("reman_subcategory_match"), str):
        merged["reman_subcategory_match"] = custom["reman_subcategory_match"]

    merged["mappings"]["state"] = _merge_mapping(
        STATE_DEFAULT_MAPPING, merged["mappings"].get("state", {})
    )
    merged["mappings"]["orders"] = _merge_mapping(
        ORDERS_DEFAULT_MAPPING, merged["mappings"].get("orders", {})
    )
    return merged


def _normalize_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    if isinstance(value, (int, float)):
        return value != 0
    s = str(value).strip().lower()
    return s in {"1", "true", "si", "sì", "yes", "y", "on"}


def _parse_date(value: Any) -> date | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    s = str(value).strip()
    if not s:
        return None
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%Y/%m/%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(s).date()
    except ValueError:
        return None


def _get_cell_by_mapping(
    row: Iterable[Any], header_map: dict[str, int], candidates: list[str]
) -> Any:
    row_list = list(row)
    for cand in candidates:
        key = normalize_header(cand)
        idx = header_map.get(key)
        if idx is not None and idx < len(row_list):
            return row_list[idx]
    return None


def parse_prioritypro_state_xlsx(
    file_bytes: bytes, mapping: dict[str, Any]
) -> tuple[list[dict[str, Any]], ParseStats]:
    header_map, rows = read_xlsx_table(file_bytes)
    merged_mapping = _merge_mapping(STATE_DEFAULT_MAPPING, mapping)
    stats = ParseStats()
    records: list[dict[str, Any]] = []
    for row in rows:
        stats.processed += 1
        customer_id = _get_cell_by_mapping(row, header_map, merged_mapping["customer_id"])
        if customer_id is None or str(customer_id).strip() == "":
            stats.invalid += 1
            continue
        record = {
            "customer_id": str(customer_id).strip(),
            "ragione_sociale": _get_cell_by_mapping(
                row, header_map, merged_mapping["ragione_sociale"]
            ),
            "piva": _get_cell_by_mapping(row, header_map, merged_mapping["piva"]),
            "priority_enabled": _normalize_bool(
                _get_cell_by_mapping(row, header_map, merged_mapping["priority_enabled"])
            ),
            "pro_enabled": _normalize_bool(
                _get_cell_by_mapping(row, header_map, merged_mapping["pro_enabled"])
            ),
            "shipments_free_used_this_week": safe_int(
                _get_cell_by_mapping(
                    row, header_map, merged_mapping["shipments_free_used_this_week"]
                ),
                0,
            ),
            "shipments_free_week_start": _get_cell_by_mapping(
                row, header_map, merged_mapping["shipments_free_week_start"]
            ),
            "points_balance_total": safe_int(
                _get_cell_by_mapping(row, header_map, merged_mapping["points_balance_total"]),
                0,
            ),
            "points_balance_earned": safe_int(
                _get_cell_by_mapping(
                    row, header_map, merged_mapping["points_balance_earned"]
                ),
                0,
            ),
            "points_balance_purchased": safe_int(
                _get_cell_by_mapping(
                    row, header_map, merged_mapping["points_balance_purchased"]
                ),
                0,
            ),
        }
        record["ragione_sociale"] = (
            str(record["ragione_sociale"]).strip()
            if record["ragione_sociale"] is not None
            else ""
        )
        record["piva"] = (
            str(record["piva"]).strip() if record["piva"] is not None else ""
        )
        records.append(record)
        stats.valid += 1
    return records, stats


def parse_prioritypro_orders_xlsx(
    file_bytes: bytes, mapping: dict[str, Any], reman_match: str
) -> tuple[list[dict[str, Any]], ParseStats]:
    header_map, rows = read_xlsx_table(file_bytes)
    merged_mapping = _merge_mapping(ORDERS_DEFAULT_MAPPING, mapping)
    stats = ParseStats()
    records: list[dict[str, Any]] = []
    match_value = (reman_match or "remanufactured").strip().lower()
    for row in rows:
        stats.processed += 1
        customer_id = _get_cell_by_mapping(row, header_map, merged_mapping["customer_id"])
        if customer_id is None or str(customer_id).strip() == "":
            stats.invalid += 1
            continue
        order_id = _get_cell_by_mapping(row, header_map, merged_mapping["order_id"])
        imponibile = safe_float(
            _get_cell_by_mapping(row, header_map, merged_mapping["imponibile"]), 0.0
        )
        subcategoria = _get_cell_by_mapping(
            row, header_map, merged_mapping["subcategoria"]
        )
        subcategoria_str = str(subcategoria).strip() if subcategoria is not None else ""
        record = {
            "order_id": str(order_id).strip() if order_id is not None else "",
            "customer_id": str(customer_id).strip(),
            "order_date": _parse_date(
                _get_cell_by_mapping(row, header_map, merged_mapping["order_date"])
            ),
            "imponibile": imponibile,
            "subcategoria": subcategoria_str,
            "reman_detected": match_value in subcategoria_str.lower() if match_value else False,
        }
        records.append(record)
        stats.valid += 1
    return records, stats


def _round_up(value: float, mode: str) -> float:
    if mode == "decina":
        return math.ceil(value / 10) * 10
    return math.ceil(value)


def build_prioritypro_results(
    state_records: list[dict[str, Any]],
    order_records: list[dict[str, Any]],
    config: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    cfg = merge_prioritypro_config(config)
    priority_cfg = cfg["priority"]
    pro_cfg = cfg["pro"]

    orders_by_customer: dict[str, list[dict[str, Any]]] = {}
    for order in order_records:
        cust_id = str(order.get("customer_id", "")).strip()
        if not cust_id:
            continue
        orders_by_customer.setdefault(cust_id, []).append(order)

    results: list[dict[str, Any]] = []
    aderito_count = 0
    reman_customers = 0
    abuse_count = 0
    unmatched_orders = 0

    for customer in state_records:
        cust_id = str(customer.get("customer_id", "")).strip()
        orders = orders_by_customer.get(cust_id, [])
        if not orders:
            unmatched_orders += 1
        orders_sorted = sorted(
            orders,
            key=lambda o: (
                o.get("order_date") or date.min,
                o.get("order_id") or "",
            ),
        )
        imponibili = [o.get("imponibile", 0.0) or 0.0 for o in orders_sorted]
        avg_imponibile = sum(imponibili) / len(imponibili) if imponibili else 0.0
        min_orders = safe_int(priority_cfg.get("min_orders_for_avg"), 3)
        markup = safe_float(priority_cfg.get("markup_sicurezza"), 0.4)
        smp_default = safe_float(priority_cfg.get("smp_default"), 0.0)
        if imponibili and len(imponibili) >= min_orders:
            smp_raw = avg_imponibile * (1 + markup)
            smp_source = "avg"
        else:
            smp_raw = smp_default
            smp_source = "fallback"
        round_mode = str(priority_cfg.get("round_up_mode") or "unit")
        smp_value = _round_up(smp_raw, round_mode)

        free_per_week = safe_int(priority_cfg.get("free_shipments_per_week"), 0)
        used_this_week = safe_int(customer.get("shipments_free_used_this_week"), 0)
        remaining = max(free_per_week - used_this_week, 0)
        priority_enabled = bool(customer.get("priority_enabled"))
        pro_enabled = bool(customer.get("pro_enabled"))
        aderito = priority_enabled and pro_enabled
        if aderito:
            aderito_count += 1

        latest_order = orders_sorted[-1] if orders_sorted else None
        latest_imponibile = latest_order.get("imponibile", 0.0) if latest_order else 0.0
        regola_2x = bool(pro_cfg.get("regola_2x_attiva", True))
        max_points_usable = (
            math.floor(latest_imponibile / 2) if regola_2x and latest_imponibile else 0
        )
        eligible_free = bool(aderito and remaining > 0 and latest_imponibile >= smp_value)
        eligible_points = bool(pro_enabled and max_points_usable > 0)

        reman_count = sum(1 for o in orders_sorted if o.get("reman_detected"))
        reman_detected = reman_count > 0
        if reman_detected:
            reman_customers += 1

        abuse_threshold = safe_int(priority_cfg.get("anti_abuse_threshold_per_week"), 0)
        abuse_flag = False
        if abuse_threshold and orders_sorted:
            weekly_counts: dict[tuple[int, int], int] = {}
            for o in orders_sorted:
                o_date = o.get("order_date")
                if not o_date:
                    continue
                if o.get("imponibile", 0.0) >= smp_value:
                    continue
                week_key = o_date.isocalendar()[:2]
                weekly_counts[week_key] = weekly_counts.get(week_key, 0) + 1
            abuse_flag = any(count >= abuse_threshold for count in weekly_counts.values())
        if abuse_flag:
            abuse_count += 1

        results.append(
            {
                "customer_id": cust_id,
                "ragione_sociale": customer.get("ragione_sociale") or "",
                "piva": customer.get("piva") or "",
                "ha_aderito": "Sì" if aderito else "No",
                "smp": smp_value,
                "smp_source": smp_source,
                "shipments_free_used_this_week": used_this_week,
                "shipments_free_remaining": remaining,
                "points_balance_total": safe_int(customer.get("points_balance_total"), 0),
                "points_balance_earned": safe_int(customer.get("points_balance_earned"), 0),
                "points_balance_purchased": safe_int(
                    customer.get("points_balance_purchased"), 0
                ),
                "reman_detected": reman_detected,
                "reman_orders": reman_count,
                "abuse_flag": abuse_flag,
                "max_points_usable_this_order": max_points_usable,
                "eligible_free_shipment": eligible_free,
                "eligible_points_discount": eligible_points,
            }
        )

    summary = {
        "customers": len(results),
        "aderito": aderito_count,
        "reman_customers": reman_customers,
        "abuse_flags": abuse_count,
        "unmatched_orders": unmatched_orders,
    }
    return results, summary


def export_prioritypro_csv(results: list[dict[str, Any]], output_path: Path) -> None:
    fieldnames = [
        "customer_id",
        "ragione_sociale",
        "piva",
        "ha_aderito",
        "smp",
        "smp_source",
        "shipments_free_used_this_week",
        "shipments_free_remaining",
        "points_balance_total",
        "points_balance_earned",
        "points_balance_purchased",
        "reman_detected",
        "reman_orders",
        "abuse_flag",
    ]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in results:
            writer.writerow({k: row.get(k) for k in fieldnames})


def export_prioritypro_xlsx(results: list[dict[str, Any]], output_path: Path) -> None:
    from openpyxl import Workbook

    headers = [
        "customer_id",
        "ragione_sociale",
        "piva",
        "ha_aderito",
        "smp",
        "smp_source",
        "shipments_free_used_this_week",
        "shipments_free_remaining",
        "points_balance_total",
        "points_balance_earned",
        "points_balance_purchased",
        "reman_detected",
        "reman_orders",
        "abuse_flag",
    ]
    wb = Workbook()
    ws = wb.active
    ws.append(headers)
    for row in results:
        ws.append([row.get(header) for header in headers])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(output_path)


def _load_xlsx_file(path: Path) -> bytes:
    return path.read_bytes()


def run_cli() -> int:
    parser = argparse.ArgumentParser(description="Priority & Pro engine")
    parser.add_argument("--state", required=True, help="Percorso file stato clienti")
    parser.add_argument("--orders", required=True, help="Percorso file ordini")
    parser.add_argument("--out", required=True, help="Directory output")
    args = parser.parse_args()

    state_bytes = _load_xlsx_file(Path(args.state))
    orders_bytes = _load_xlsx_file(Path(args.orders))
    config = merge_prioritypro_config({})
    state_records, _ = parse_prioritypro_state_xlsx(
        state_bytes, config["mappings"]["state"]
    )
    order_records, _ = parse_prioritypro_orders_xlsx(
        orders_bytes, config["mappings"]["orders"], config["reman_subcategory_match"]
    )
    results, summary = build_prioritypro_results(state_records, order_records, config)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "prioritypro_export.csv"
    xlsx_path = out_dir / "prioritypro_export.xlsx"
    export_prioritypro_csv(results, csv_path)
    export_prioritypro_xlsx(results, xlsx_path)
    summary_path = out_dir / "prioritypro_summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(run_cli())
