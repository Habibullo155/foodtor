import hashlib
from datetime import UTC, datetime
from decimal import Decimal, InvalidOperation
from html import escape
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates

from app.api.deps import SessionDep
from app.api.v1.marketing import visible_banners
from app.api.v1.stories import visible_stories
from app.core.config import get_settings
from app.repositories.catalog import CatalogRepository
from app.services import shop_info
from app.services.recommendations import RecommendationService
from app.web import catalog as data

HERE = Path(__file__).parent
STATIC = HERE / "static"
templates = Jinja2Templates(directory=HERE / "templates")


async def _fresh_shop_info(session: SessionDep) -> None:
    await shop_info.load(session)


router = APIRouter(include_in_schema=False, dependencies=[Depends(_fresh_shop_info)])


def rub(value) -> str:
    if value is None:
        return ""
    v = Decimal(str(value))
    whole = f"{int(v):,}".replace(",", " ")
    frac = v - int(v)
    return f"{whole},{int(round(frac * 100)):02d} ₽" if frac else f"{whole} ₽"


def plural(n: int, one: str, few: str, many: str) -> str:
    n10, n100 = n % 10, n % 100
    if n10 == 1 and n100 != 11:
        return one
    if 2 <= n10 <= 4 and not 12 <= n100 <= 14:
        return few
    return many


_asset_versions: dict[str, str] = {}


def asset(path: str) -> str:
    """/static/… с версией по содержимому: браузер кэширует надолго, а новый релиз подхватывает сразу."""
    if path not in _asset_versions or get_settings().app_env == "dev":
        f = STATIC / path
        _asset_versions[path] = hashlib.sha256(f.read_bytes()).hexdigest()[:10] if f.exists() else "0"
    return f"/static/{path}?v={_asset_versions[path]}"


def stories_json(stories) -> list[dict]:
    return [
        {
            "id": s.id,
            "title": s.title,
            "color": s.color_hex,
            "slides": [
                {
                    "image": x.image_url,
                    "headline": x.headline,
                    "caption": x.caption,
                    "cta_label": x.cta_label,
                    "cta_url": x.cta_url,
                }
                for x in s.slides
            ],
        }
        for s in stories
    ]


templates.env.filters["rub"] = rub
templates.env.globals.update(
    plural=plural,
    asset=asset,
    stories_json=stories_json,
    product_url=data.product_url,
    year=lambda: datetime.now(UTC).year,
)


def site_base(request: Request) -> str:
    """Адрес сайта для canonical/sitemap/микроразметки: в проде — из настроек, а не из заголовка Host."""
    s = get_settings()
    return s.public_shop_url.rstrip("/") if s.is_prod else str(request.base_url).rstrip("/")


def site_url(request: Request, path: str, query: str = "") -> str:
    return site_base(request) + path + (f"?{query}" if query else "")


def render(request: Request, name: str, status_code: int = 200, **ctx) -> HTMLResponse:
    s = get_settings()
    info = shop_info.current()
    if "canonical" not in ctx:
        ctx["canonical"] = site_url(request, request.url.path)
    ctx.setdefault("base_url", site_base(request) + "/")
    return templates.TemplateResponse(
        request,
        name,
        {
            "shop_name": s.shop_name,
            "hours": info.hours,
            "socials": info.socials,
            "contacts": info.contacts,
            "delivery": info.delivery,
            "referral": info.referral,
            "legal": info.legal,
            "online_payment": s.payments_enabled,
            **ctx,
        },
        status_code=status_code,
    )


def absolute(request: Request, url: str) -> str:
    return url if url.startswith("http") else site_base(request) + "/" + url.lstrip("/")


def _decimal(v: str | None) -> Decimal | None:
    try:
        return Decimal(v) if v not in (None, "") else None
    except InvalidOperation:
        return None


@router.get("/", response_class=HTMLResponse)
async def home(request: Request, session: SessionDep):
    cats = await data.categories(session)
    stories = await visible_stories(session)
    banners = await visible_banners(session)
    hits = await data.rail(session, hits=True)
    sale = await data.rail(session, sale=True)
    first = await data.catalog(session, data.Filters())
    return render(
        request,
        "home.html",
        categories=cats,
        hits=hits,
        sale=sale,
        page=first,
        stories=stories,
        banners=banners,
        filters=data.Filters(),
        title=f"{get_settings().shop_name} — овощи, фрукты и бакалея с доставкой",
        description="Свежие овощи, фрукты, ягоды и бакалея с доставкой на дом. Доставляем в удобное время, "
        "оплата при получении.",
    )


async def _catalog_page(
    request: Request,
    session,
    category_slug: str | None,
    q: str,
    brand: list[str],
    price_min: str | None,
    price_max: str | None,
    in_stock: bool,
    sort: str,
    page: int,
):
    category = None
    if category_slug:
        category = await data.category_by_slug(session, category_slug)
        if category is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND)
    f = data.Filters(
        q=q.strip()[:100],
        category=category,
        brands=[b for b in brand if b][:20],
        price_min=_decimal(price_min),
        price_max=_decimal(price_max),
        in_stock=in_stock,
        sort=sort if sort in ("popular", "price_asc", "price_desc", "new") else "popular",
        page=page,
    )
    result = await data.catalog(session, f)
    title = f"Поиск «{f.q}»" if f.q else (category.name if category else "Каталог")
    # Фильтры/сортировка — не дубли для поисковика (noindex + canonical на чистую страницу);
    # страницы пагинации — самостоятельные: canonical на себя, rel=prev/next
    base = f"/catalog/{category.slug}" if category else "/catalog"
    clean = not (f.q or f.active or f.sort != "popular")
    page_url = lambda n: site_url(request, base, f"page={n}" if n > 1 else "")  # noqa: E731
    return render(
        request,
        "catalog.html",
        filters=f,
        page=result,
        categories=await data.categories(session),
        title=f"{title}{f' — страница {result.page}' if result.page > 1 else ''} — купить с доставкой | "
        f"{get_settings().shop_name}",
        heading=title,
        description=f"{title}: {result.total} {plural(result.total, 'товар', 'товара', 'товаров')} с доставкой на дом.",
        canonical=page_url(result.page) if clean else page_url(1),
        prev_url=page_url(result.page - 1) if clean and result.page > 1 else None,
        next_url=page_url(result.page + 1) if clean and result.page < result.pages else None,
        noindex=not clean,
    )


@router.get("/catalog", response_class=HTMLResponse)
@router.get("/catalog/{category_slug}", response_class=HTMLResponse)
@router.get("/search", response_class=HTMLResponse)
async def catalog_page(
    request: Request,
    session: SessionDep,
    category_slug: str | None = None,
    q: Annotated[str, Query(max_length=100)] = "",
    brand: Annotated[list[str] | None, Query()] = None,
    price_min: str | None = None,
    price_max: str | None = None,
    in_stock: bool = False,
    sort: str = "popular",
    page: Annotated[int, Query(ge=1, le=1000)] = 1,
):
    return await _catalog_page(
        request, session, category_slug, q, brand or [], price_min, price_max, in_stock, sort, page
    )


@router.get("/product/{product_ref}", response_class=HTMLResponse)
async def product_page(request: Request, session: SessionDep, product_ref: str):
    pid = product_ref.split("-", 1)[0]
    if not pid.isdigit():
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    product = await CatalogRepository(session).get_active(int(pid))
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    url = data.product_url(product)
    if request.url.path != url:  # старое/неполное название в адресе → постоянный редирект на канонический
        return RedirectResponse(url, status.HTTP_301_MOVED_PERMANENTLY)
    rec = RecommendationService(session)
    cross, similar = await rec.cross_sell([product.id]), await rec.similar(product)
    items = await data.summaries(session, [product, *cross, *similar])
    summary, rest = items[0], items[1:]
    return render(
        request,
        "product.html",
        p=summary,
        product=product,
        images=[i.url for i in product.images],
        abs_images=[absolute(request, i.url) for i in product.images],
        cross=rest[: len(cross)],
        similar=rest[len(cross) :],
        reviews=await data.product_reviews(session, product.id),
        title=f"{product.name}{', ' + product.unit if product.unit else ''} — купить за {rub(summary.price.price)} | "
        f"{get_settings().shop_name}",
        description=(
            product.description
            or f"{product.name} {product.unit or ''} от {product.brand or 'производителя'}. Доставка за 2 часа."
        )[:160],
        og_image=absolute(request, summary.image_url) if summary.image_url else None,
        og_type="product",
    )


def _shell(name: str, title: str):
    async def page(request: Request):
        return render(request, name, title=f"{title} | {get_settings().shop_name}", noindex=True)

    return page


@router.get("/promo", response_class=HTMLResponse)
async def promo(request: Request, session: SessionDep):
    items = await data.rail(session, sale=True, limit=120)
    name = get_settings().shop_name
    return render(
        request,
        "promo.html",
        items=items,
        title=f"Акции и скидки на продукты | {name}",
        heading="Акции",
        description="Скидки на овощи, фрукты и бакалею с доставкой на дом. Обновляем каждую неделю.",
    )


@router.get("/business", response_class=HTMLResponse)
async def business(request: Request):
    name = get_settings().shop_name
    return render(
        request,
        "business.html",
        title=f"Продукты оптом для бизнеса — кафе, ресторанов, магазинов | {name}",
        heading="Для бизнеса",
        description="Оптовые цены на овощи, фрукты и бакалею для кафе, ресторанов, магазинов и офисов. "
        "Доставка, оплата при получении.",
    )


@router.get("/support", response_class=HTMLResponse)
async def support(request: Request):
    name = get_settings().shop_name
    return render(
        request,
        "support.html",
        title=f"Поддержка | {name}",
        heading="Поддержка",
        description=f"Служба поддержки {name}: ответим на вопросы о заказе, доставке и оплате.",
    )


@router.get("/friends", response_class=HTMLResponse)
async def friends(request: Request):
    if not shop_info.current().referral.enabled:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    name = get_settings().shop_name
    return render(
        request,
        "friends.html",
        title=f"Приведи друга | {name}",
        heading="Приведи друга",
        description="Пригласите друга в магазин — подарим скидку вам обоим.",
    )


router.add_api_route("/cart", _shell("cart.html", "Корзина"), response_class=HTMLResponse)
router.add_api_route("/checkout", _shell("checkout.html", "Оформление заказа"), response_class=HTMLResponse)
router.add_api_route("/login", _shell("login.html", "Вход"), response_class=HTMLResponse)
router.add_api_route("/account", _shell("account.html", "Личный кабинет"), response_class=HTMLResponse)
@router.get("/payment/return", response_class=HTMLResponse)
async def payment_return(request: Request):
    if not get_settings().payments_enabled:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    return render(request, "payment_return.html", title=f"Оплата | {get_settings().shop_name}", noindex=True)


@router.get("/info/{slug}", response_class=HTMLResponse)
async def info_page(request: Request, slug: str):
    pages = {
        "delivery": "Доставка",
        "payment": "Оплата",
        "offer": "Публичная оферта",
        "privacy": "Политика конфиденциальности",
        "returns": "Возврат и обмен",
        "contacts": "Контакты",
        "about": "О нас",
    }
    if slug not in pages:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    return render(
        request,
        f"info/{slug}.html",
        title=f"{pages[slug]} | {get_settings().shop_name}",
        heading=pages[slug],
    )


@router.get("/robots.txt", response_class=PlainTextResponse)
async def robots(request: Request):
    base = site_base(request)
    return (
        "User-agent: *\nDisallow: /cart\nDisallow: /checkout\nDisallow: /account\nDisallow: /login\n"
        "Disallow: /search\nDisallow: /api/\nDisallow: /*?*sort=\nDisallow: /*?*brand=\n"
        f"Sitemap: {base}/sitemap.xml\n"
    )


@router.get("/sitemap.xml")
async def sitemap(request: Request, session: SessionDep):
    base = site_base(request)
    cats, prods = await data.all_for_sitemap(session)

    def url(loc: str, lastmod=None, prio: str = "0.6") -> str:
        mod = f"<lastmod>{lastmod.date().isoformat()}</lastmod>" if lastmod else ""
        return f"<url><loc>{escape(loc)}</loc>{mod}<priority>{prio}</priority></url>"

    body = url(f"{base}/", prio="1.0") + url(f"{base}/catalog", prio="0.9")
    body += url(f"{base}/promo", prio="0.8") + url(f"{base}/business", prio="0.5") + url(f"{base}/support", prio="0.3")
    body += "".join(url(f"{base}/catalog/{c.slug}", prio="0.8") for c in cats)
    body += "".join(url(base + data.product_url(p), p.updated_at) for p in prods)
    body += "".join(
        url(f"{base}/info/{s}", prio="0.3") for s in ("about", "delivery", "payment", "returns", "contacts", "offer", "privacy")
    )
    xml = f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{body}</urlset>'
    return Response(xml, media_type="application/xml")


async def not_found_page(request: Request) -> HTMLResponse:
    return render(request, "404.html", status_code=404, title="Страница не найдена", noindex=True)
