import json
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from api.db import get_client_by_id, list_orders
from core.logger import logger
from llm.model_client import complete_text

ANALYTICS_CACHE_TTL_MINUTES = 20
_ANALYTICS_CACHE: Dict[str, Dict[str, Any]] = {}

try:
    from zoneinfo import ZoneInfo

    ANALYTICS_TZ = ZoneInfo("Europe/Rome")
    ANALYTICS_TZ_NAME = "Europe/Rome"
except Exception:  # pragma: no cover - zoneinfo fallback
    ANALYTICS_TZ = timezone.utc
    ANALYTICS_TZ_NAME = "UTC"


def parse_order_datetime(value: Optional[Any]) -> Optional[datetime]:
    if not value:
        return None
    dt: Optional[datetime]
    if isinstance(value, datetime):
        dt = value
    else:
        text = str(value).strip()
        if not text:
            return None
        if text.endswith("Z"):
            text = f"{text[:-1]}+00:00"
        try:
            dt = datetime.fromisoformat(text)
        except Exception:
            return None
    if dt.tzinfo is None or dt.tzinfo.utcoffset(dt) is None:
        return dt.replace(tzinfo=ANALYTICS_TZ)
    return dt.astimezone(ANALYTICS_TZ)


def _month_key(dt: datetime) -> str:
    return f"{dt.year:04d}-{dt.month:02d}"


def _demo_orders(customer_id: Any) -> List[Dict[str, Any]]:
    # Dati dimostrativi deterministici per ambiente dev
    base = int(str(customer_id)[-2:] or 1)
    now = datetime.now(timezone.utc)
    demo = []
    for idx in range(1, 5):
        month_dt = now - timedelta(days=idx * 20)
        demo.append(
            {
                "order_date": month_dt.isoformat(),
                "total_amount": base * 10 + idx * 50,
                "cause": "Consumabili" if idx % 2 == 0 else "Office",
                "status": "demo",
            }
        )
    return demo


def _normalize_orders_for_client(
    customer_id: Any, client_email: Optional[str], client_name: Optional[str] = None, client_record: Optional[Dict[str, Any]] = None
) -> List[Dict[str, Any]]:
    client = client_record or (get_client_by_id(int(customer_id)) if customer_id is not None else None)
    email = client_email or (client or {}).get("email")
    name = client_name or (client or {}).get("ragione_sociale") or (client or {}).get("name")
    orders = list_orders(customer_email=email, customer_name=name, include_all=False)
    if orders:
        return orders
    return _demo_orders(customer_id or "demo")


def get_orders_for_customer(
    customer_id: Any, client_email: Optional[str], client_name: Optional[str] = None, client_record: Optional[Dict[str, Any]] = None
) -> List[Dict[str, Any]]:
    return _normalize_orders_for_client(customer_id, client_email, client_name=client_name, client_record=client_record)


def get_orders_debug_info(orders: List[Dict[str, Any]], customer_id: Any, customer_email: Optional[str]) -> Dict[str, Any]:
    dates: List[datetime] = []
    for order in orders:
        parsed = parse_order_datetime(order.get("order_date"))
        if parsed:
            dates.append(parsed)
    first = min(dates) if dates else None
    last = max(dates) if dates else None
    return {
        "customer_id": str(customer_id) if customer_id is not None else None,
        "email": customer_email,
        "orders_count": len(orders),
        "first_order_date": first.isoformat() if first else None,
        "last_order_date": last.isoformat() if last else None,
        "timezone": ANALYTICS_TZ_NAME,
    }


def compute_sales_metrics(orders: List[Dict[str, Any]]) -> Dict[str, Any]:
    now = datetime.now(ANALYTICS_TZ)
    start_current_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    def start_of_previous_months(n: int) -> datetime:
        month = start_current_month.month - n
        year = start_current_month.year
        while month <= 0:
            month += 12
            year -= 1
        return start_current_month.replace(year=year, month=month)

    monthly_totals: Dict[str, float] = defaultdict(float)
    category_totals: Dict[str, float] = defaultdict(float)
    current_month_total = 0.0
    total_orders_count = len(orders)
    parsed_orders_count = 0
    invalid_dates_count = 0

    for order in orders:
        amount = float(order.get("total_amount") or 0)
        dt = parse_order_datetime(order.get("order_date"))
        cat = (order.get("cause") or order.get("status") or "Generale").strip()
        category_totals[cat] += amount
        if dt:
            parsed_orders_count += 1
            key = _month_key(dt)
            monthly_totals[key] += amount
            if dt >= start_current_month:
                current_month_total += amount
        else:
            invalid_dates_count += 1

    last_three_months_total = 0.0
    prev_months_totals: List[float] = []
    for i in range(1, 4):
        start_month = start_of_previous_months(i)
        month_key = f"{start_month.year:04d}-{start_month.month:02d}"
        value = monthly_totals.get(month_key, 0.0)
        prev_months_totals.append(value)
        last_three_months_total += value

    prev_avg = last_three_months_total / 3 if prev_months_totals else 0
    if prev_avg > 0:
        growth_percent = ((current_month_total - prev_avg) / prev_avg) * 100
    elif current_month_total > 0:
        growth_percent = 100.0
    else:
        growth_percent = 0.0

    sorted_categories = sorted(
        [{"name": k, "total": round(v, 2)} for k, v in category_totals.items()],
        key=lambda x: x["total"],
        reverse=True,
    )

    margin_percent = None

    return {
        "period": {
            "current_month_total": round(current_month_total, 2),
            "last_3_months_total": round(last_three_months_total, 2),
            "growth_percent": round(growth_percent, 2),
        },
        "categories": sorted_categories,
        "margin": {"average_margin_percent": margin_percent},
        "debug": {
            "invalid_dates_count": invalid_dates_count,
            "total_orders_count": total_orders_count,
            "parsed_orders_count": parsed_orders_count,
        },
    }


async def get_customer_risk_and_upsell_suggestions(customer_id: Any, stats: Dict[str, Any]) -> Dict[str, Any]:
    prompt = (
        "Agisci da analista B2B. Dati cliente: "
        f"mese_corrente={stats['period']['current_month_total']}, "
        f"ultimi3mesi={stats['period']['last_3_months_total']}, "
        f"crescita={stats['period']['growth_percent']}%. "
        f"Categorie top: {[c['name'] for c in stats.get('categories', [])][:3]}. "
        "Restituisci JSON compatto con chiavi: churn_risk_score (0-100),"
        " churn_risk_level (low/medium/high), upsell_suggestions (lista 2-5 frasi brevi)."
    )
    try:
        raw = await complete_text(prompt, max_tokens=200, temperature=0.4)
        parsed = json.loads(raw)
        score = int(parsed.get("churn_risk_score", 50))
        level = str(parsed.get("churn_risk_level") or "medium")
        suggestions = parsed.get("upsell_suggestions") or []
        if not isinstance(suggestions, list):
            suggestions = [str(suggestions)]
        suggestions = [str(s) for s in suggestions if s]
        level = level.lower()
        if level not in ("low", "medium", "high"):
            level = "medium"
        score = max(0, min(100, score))
    except Exception:
        logger.exception("LLM churn risk fallback")
        score = 50
        level = "medium"
        suggestions = [
            "Proponi bundle consumabili + carta.",
            "Suggerisci rinnovo con sconto di fedeltà.",
        ]

    return {
        "churn_risk_score": score,
        "churn_risk_level": level,
        "upsell_suggestions": suggestions,
    }


def _cache_key(customer_id: Any) -> str:
    return str(customer_id)


def _get_cached(customer_id: Any) -> Optional[Dict[str, Any]]:
    key = _cache_key(customer_id)
    entry = _ANALYTICS_CACHE.get(key)
    if not entry:
        return None
    ttl = timedelta(minutes=ANALYTICS_CACHE_TTL_MINUTES)
    if datetime.now(timezone.utc) - entry["ts"] > ttl:
        _ANALYTICS_CACHE.pop(key, None)
        return None
    cached_copy = dict(entry["data"])
    cached_copy["cached"] = True
    return cached_copy


def _set_cache(customer_id: Any, data: Dict[str, Any]) -> None:
    key = _cache_key(customer_id)
    _ANALYTICS_CACHE[key] = {"data": data, "ts": datetime.now(timezone.utc)}


def reset_cache():
    _ANALYTICS_CACHE.clear()


async def get_customer_analytics(
    customer_id: Any, client_email: Optional[str], refresh: bool = False, orders_override: Optional[List[Dict[str, Any]]] = None
) -> Dict[str, Any]:
    if not refresh:
        cached = _get_cached(customer_id)
        if cached:
            return cached

    orders = orders_override if orders_override is not None else get_orders_for_customer(customer_id, client_email)
    stats = compute_sales_metrics(orders)
    ai_block = await get_customer_risk_and_upsell_suggestions(customer_id, stats)
    result = {
        "customer_id": str(customer_id),
        "period": stats["period"],
        "categories": stats["categories"],
        "margin": stats["margin"],
        "ai": ai_block,
        "debug": stats.get("debug", {}),
        "cached": False,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    _set_cache(customer_id, result)
    return result


__all__ = [
    "get_customer_analytics",
    "compute_sales_metrics",
    "get_customer_risk_and_upsell_suggestions",
    "reset_cache",
    "ANALYTICS_CACHE_TTL_MINUTES",
    "ANALYTICS_TZ",
    "ANALYTICS_TZ_NAME",
    "parse_order_datetime",
    "get_orders_for_customer",
    "get_orders_debug_info",
]
