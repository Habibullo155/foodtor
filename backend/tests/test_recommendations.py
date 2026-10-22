from app.models import RelationKind
from app.services.recommendations import RecommendationService, rank_candidates
from tests import factories as f


def ids(ranked):
    return [c.product_id for c in ranked]


def test_affinity_is_normalized_by_popularity():
    # 10 совместных покупок у сверхпопулярного (1000 заказов) слабее, чем 6 у нишевого (36)
    ranked = rank_candidates(
        manual={},
        together={1: 10, 2: 6},
        popularity={1: 1000, 2: 36},
        categories={1: 1, 2: 2},
        exclude=[],
        limit=5,
    )
    assert ids(ranked)[0] == 2


def test_manual_link_beats_weak_signals_and_cart_items_excluded():
    ranked = rank_candidates(
        manual={3: 1.0},
        together={1: 2},
        popularity={1: 4, 3: 1, 9: 50},
        categories={1: 1, 3: 2, 9: 3},
        exclude=[9],
        limit=5,
    )
    assert ids(ranked)[0] == 3 and 9 not in ids(ranked)


def test_unsellable_candidates_dropped():
    ranked = rank_candidates(manual={5: 1.0}, together={}, popularity={}, categories={}, exclude=[], limit=5)
    assert ranked == []


def test_diversity_max_two_per_category_then_tail():
    together = {i: 10 - i for i in range(1, 6)}  # все из категории 1, кроме 5
    cats = {1: 1, 2: 1, 3: 1, 4: 1, 5: 2}
    ranked = rank_candidates(manual={}, together=together, popularity={}, categories=cats, exclude=[], limit=4)
    assert ids(ranked)[:3] == [1, 2, 5]  # третий из категории 1 уступил место другой категории
    assert len(ranked) == 4


async def test_cross_sell_learns_from_order_history(db):
    veg, greens, oil = await f.category(db, "Овощи"), await f.category(db, "Зелень"), await f.category(db, "Масло")
    tomato = await f.product(db, "Томаты", cat=veg)
    dill = await f.product(db, "Укроп", cat=greens)
    olive = await f.product(db, "Масло", cat=oil)
    banana = await f.product(db, "Бананы", cat=veg)  # популярный, но с томатами не берут
    out_of_stock = await f.product(db, "Базилик", cat=greens, stock=0)
    u = await f.customer(db)
    for _ in range(4):
        await f.delivered_order(db, u, tomato, dill)
    await f.delivered_order(db, u, tomato, out_of_stock)
    for _ in range(12):
        await f.delivered_order(db, u, banana)
    await f.relate(db, tomato, olive)  # ручная связь из админки
    await db.commit()

    recs = await RecommendationService(db).cross_sell([tomato.id], limit=4)
    names = [p.name for p in recs]
    assert names[:2] == ["Масло", "Укроп"] or names[:2] == ["Укроп", "Масло"]
    assert "Базилик" not in names  # нет в наличии
    assert "Томаты" not in names
    assert names.index("Укроп") < names.index("Бананы") if "Бананы" in names else True


async def test_similar_falls_back_to_pricier_same_category(db):
    veg = await f.category(db)
    base = await f.product(db, "Томаты", "200", cat=veg)
    _pricier = await f.product(db, "Томаты черри", "260", cat=veg)
    _too_expensive = await f.product(db, "Томаты трюфельные", "900", cat=veg)
    _cheaper = await f.product(db, "Томаты эконом", "120", cat=veg)
    manual = await f.product(db, "Томаты Сан-Марцано", "330", cat=veg)
    await f.relate(db, base, manual, RelationKind.UPSELL)
    await db.commit()

    names = [p.name for p in await RecommendationService(db).similar(base)]
    assert names[0] == "Томаты Сан-Марцано"
    assert "Томаты черри" in names
    assert "Томаты трюфельные" not in names and "Томаты эконом" not in names
