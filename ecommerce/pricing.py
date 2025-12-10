from typing import Dict, Tuple

def compute_price(sku: str, base_price: float, segment: str, quantity: int) -> Tuple[float, Dict]:
    discount = 0.0

    if segment == "distributore":
        discount = 0.18
    elif segment == "rivenditore_top":
        discount = 0.12
    elif segment == "rivenditore":
        discount = 0.08
    elif segment == "rivenditore_small":
        discount = 0.05

    if quantity >= 10:
        discount += 0.03
    elif quantity >= 50:
        discount += 0.06

    discount = min(discount, 0.35)
    final_price = round(base_price * (1 - discount), 4)

    meta = {
        "segment": segment,
        "quantity": quantity,
        "base_price": base_price,
        "discount": discount,
    }
    return final_price, meta
