import json
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from api.db import get_client_by_id, list_orders
from core.logger import logger
from llm.model_client import complete_text

ANALYTICS_CACHE_TTL_MINUTES = 20
_ANALYTICS_CACHE: Dict[str, Dict[str, Any]] = {}


def _parse_order_date(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        clean_value = value.replace("Z", "+00:00")
        return datetime.fromisoformat(clean_value)
    except Exception:
        return None


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


def _normalize_orders_for_client(customer_id: Any, client_email: Optional[str]) -> List[Dict[str, Any]]:
    client = get_client_by_id(int(customer_id)) if customer_id is not None else None
    email = client_email or (client or {}).get("email")
    name = (client or {}).get("ragione_sociale") or (client or {}).get("name")
    orders = list_orders(customer_email=email, customer_name=name, include_all=False)
    if orders:
        return orders
    return _demo_orders(customer_id or "demo")


def compute_sales_metrics(orders: List[Dict[str, Any]]) -> Dict[str, Any]:
    now = datetime.now(timezone.utc)
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

    for order in orders:
        amount = float(order.get("total_amount") or 0)
        dt = _parse_order_date(order.get("order_date"))
        cat = (order.get("cause") or order.get("status") or "Generale").strip()
        category_totals[cat] += amount
        if dt:
            key = _month_key(dt)
            monthly_totals[key] += amount
            if dt >= start_current_month:
                current_month_total += amount

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

    orders = orders_override if orders_override is not None else _normalize_orders_for_client(customer_id, client_email)
    stats = compute_sales_metrics(orders)
    ai_block = await get_customer_risk_and_upsell_suggestions(customer_id, stats)
    result = {
        "customer_id": str(customer_id),
        "period": stats["period"],
        "categories": stats["categories"],
        "margin": stats["margin"],
        "ai": ai_block,
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
]
