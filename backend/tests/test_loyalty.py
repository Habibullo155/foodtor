from decimal import Decimal as D

from app.models import DiscountType, LoyaltyTier
from app.services.loyalty import allocate_discount, calculate_discount, resolve_tier


def tier(name: str, threshold: str, kind: DiscountType, value: str) -> LoyaltyTier:
    return LoyaltyTier(
        name=name,
        min_total_spent=D(threshold),
        discount_type=kind,
        discount_value=D(value),
        min_order_for_fixed=D("0"),
        is_active=True,
    )


TIERS = [
    tier("Bronze", "0", DiscountType.PERCENT, "0"),
    tier("Silver", "10000", DiscountType.PERCENT, "5"),
    tier("Gold", "50000", DiscountType.FIXED, "1000"),
]


def test_resolve_tier_boundaries():
    assert resolve_tier(D("9999.99"), TIERS).name == "Bronze"
    assert resolve_tier(D("10000"), TIERS).name == "Silver"
    assert resolve_tier(D("75000"), TIERS).name == "Gold"


def test_fixed_discount_never_exceeds_subtotal():
    assert calculate_discount(D("500"), TIERS[2]) == D("500.00")


def test_percent_discount_rounding():
    assert calculate_discount(D("333.33"), TIERS[1]) == D("16.67")


def test_allocation_sums_exactly():
    shares = allocate_discount([D("100"), D("100"), D("100")], D("10.00"))
    assert sum(shares) == D("10.00")
    assert shares == [D("3.34"), D("3.33"), D("3.33")]
