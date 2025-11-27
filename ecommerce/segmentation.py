# Placeholder per regole di segmentazione
def segment_from_turnover(turnover_eur: float) -> str:
    if turnover_eur >= 50000:
        return "distributore"
    if turnover_eur >= 20000:
        return "rivenditore_top"
    if turnover_eur >= 5000:
        return "rivenditore"
    return "rivenditore_small"
