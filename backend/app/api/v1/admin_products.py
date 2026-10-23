from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, Response, UploadFile, status

from app.api.deps import get_import_service, require
from app.core.config import get_settings
from app.core.rate_limit import IMPORT_LIMIT, limiter
from app.models import Permission, User
from app.schemas.product import ImportReport
from app.services.import_export import FileFormat, ImportFileError, ProductImportService

router = APIRouter(prefix="/admin/products", tags=["admin: products"])

ImportService = Annotated[ProductImportService, Depends(get_import_service)]

_MEDIA_TYPES = {
    FileFormat.XLSX: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    FileFormat.CSV: "text/csv; charset=utf-8",
}


async def _read_limited(file: UploadFile, max_bytes: int) -> bytes:
    """Читаем порциями и обрываем при превышении — не даём забить память гигантским файлом."""
    chunks, size = [], 0
    while chunk := await file.read(64 * 1024):
        size += len(chunk)
        if size > max_bytes:
            raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, f"File exceeds {max_bytes // 2**20} MB")
        chunks.append(chunk)
    return b"".join(chunks)


@router.post("/import", response_model=ImportReport)
@limiter.limit(IMPORT_LIMIT)
async def import_products(
    request: Request,  # нужен slowapi
    service: ImportService,
    _: Annotated[User, Depends(require(Permission.PRODUCTS_IMPORT))],
    file: Annotated[UploadFile, File(description=".xlsx или .csv; товар ищется по артикулу, иначе по названию и фасовке")],
    dry_run: Annotated[bool, Query(description="Только валидация, без записи в БД")] = False,
) -> ImportReport:
    content = await _read_limited(file, get_settings().max_import_file_mb * 2**20)
    try:
        report = await service.import_file(file.filename or "", content, dry_run=dry_run)
    except ImportFileError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc)) from exc
    except ValueError as exc:  # битый Excel/CSV, который не смог распарсить pandas/openpyxl
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Unable to parse file") from exc
    # Коммит выполнит get_session после успешного ответа (UoW)
    return report


@router.get("/export")
async def export_products(
    service: ImportService,
    _: Annotated[
        User, Depends(require(Permission.PRODUCTS_IMPORT, Permission.FINANCE_VIEW))
    ],  # в файле есть себестоимость
    fmt: Annotated[FileFormat, Query(alias="format")] = FileFormat.XLSX,
) -> Response:
    payload = await service.export(fmt)
    filename = f"products_{datetime.now(UTC):%Y%m%d_%H%M}.{fmt.value}"
    return Response(
        content=payload,
        media_type=_MEDIA_TYPES[fmt],
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
