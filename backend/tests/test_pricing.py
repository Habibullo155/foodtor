from decimal import Decimal as D

from app.models import Product
from app.services.pricing import Audience, PriceSource, PricingContext, PricingRules, price_for


def product(id_=1, retail="1000.00", category_id=10, compare_at=None) -> Product:
    return Product(
        id=id_,
        sku=f"S{id_}",
        name="P",
        retail_price=D(retail),
        cost_price=D("500"),
        compare_at_price=D(compare_at) if compare_at else None,
        category_id=category_id,
    )


RULES = PricingRules(
    price_list_name="Опт-1",
    default_percent=D("5"),
    items={1: [(1, D("900.00")), (10, D("850.00")), (100, D("790.00"))]},
    category_percent={20: D("25")},
)
B2B = PricingContext(Audience.B2B, RULES)


def test_anonymous_and_b2c_see_retail_with_marketing_compare_at():
    p = product(compare_at="1200.00")
    for ctx in (PricingContext(Audience.ANONYMOUS), PricingContext(Audience.B2C)):
        u = price_for(p, ctx)
        assert (u.unit_price, u.compare_at_price, u.is_wholesale, u.tiers) == (D("1000.00"), D("1200.00"), False, ())


def test_b2b_tiered_price_depends_on_quantity_and_strikes_retail():
    p = product()
    assert price_for(p, B2B, 1).unit_price == D("900.00")
    assert price_for(p, B2B, 9).unit_price == D("900.00")
    assert price_for(p, B2B, 10).unit_price == D("850.00")
    u = price_for(p, B2B, 500)
    assert (u.unit_price, u.compare_at_price, u.source) == (D("790.00"), D("1000.00"), PriceSource.PRICE_LIST)
    assert [t.min_quantity for t in u.tiers] == [1, 10, 100]


def test_priority_category_then_list_default():
    assert price_for(product(2, category_id=20), B2B).unit_price == D("750.00")
    u = price_for(product(3, category_id=99), B2B)
    assert (u.unit_price, u.source) == (D("950.00"), PriceSource.LIST_DISCOUNT)


def test_wholesale_never_above_retail():
    rules = PricingRules("bad", items={1: [(1, D("1500"))]})
    u = price_for(product(), PricingContext(Audience.B2B, rules))
    assert (u.unit_price, u.source) == (D("1000.00"), PriceSource.RETAIL)


def test_unverified_b2b_context_falls_back_to_retail():
    assert price_for(product(), PricingContext(Audience.B2B, None)).source is PriceSource.RETAIL
