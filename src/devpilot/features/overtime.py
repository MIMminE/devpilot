from __future__ import annotations

from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
import json
from zoneinfo import ZoneInfo

from devpilot.app_state import read_state, write_state
from devpilot.config import AppConfig


DEFAULT_SETTINGS = {
    "hourly_rate": "0",
    "monthly_standard_hours": "209",
    "overtime_multiplier": "1.5",
    "night_multiplier": "0.5",
    "holiday_multiplier": "0.5",
    "rounding_minutes": 10,
    "currency": "KRW",
    "inclusive_salary_enabled": False,
    "inclusive_weekly_hours": "0",
    "base_monthly_salary": "0",
    "inclusive_overtime_pay": "0",
    "statutory_base_pay": "0",
}


def save_overtime_settings(
    *,
    hourly_rate: str,
    overtime_multiplier: str,
    night_multiplier: str,
    holiday_multiplier: str,
    rounding_minutes: int,
    currency: str = "KRW",
    inclusive_salary_enabled: bool = False,
    inclusive_weekly_hours: str = "0",
    base_monthly_salary: str = "0",
    inclusive_overtime_pay: str = "0",
    statutory_base_pay: str = "0",
) -> str:
    settings = {
        "hourly_rate": str(_decimal(hourly_rate)),
        "overtime_multiplier": str(_decimal(overtime_multiplier)),
        "night_multiplier": str(_decimal(night_multiplier)),
        "holiday_multiplier": str(_decimal(holiday_multiplier)),
        "rounding_minutes": max(1, int(rounding_minutes)),
        "currency": currency.strip() or "KRW",
        "inclusive_salary_enabled": bool(inclusive_salary_enabled),
        "inclusive_weekly_hours": str(_decimal(inclusive_weekly_hours)),
        "base_monthly_salary": str(_decimal(base_monthly_salary)),
        "inclusive_overtime_pay": str(_decimal(inclusive_overtime_pay)),
        "statutory_base_pay": str(_decimal(statutory_base_pay)),
    }
    state = read_state()
    state["overtime_settings"] = settings
    write_state(state)
    return "연장 근무 계산 설정을 저장했습니다."


def add_overtime_record(
    config: AppConfig,
    *,
    work_date: str,
    hours: str = "",
    kind: str = "overtime",
    start_time: str = "",
    end_time: str = "",
    memo: str = "",
) -> str:
    now = datetime.now(ZoneInfo(config.general.timezone))
    record = _build_record(
        record_id=f"ot-{now.strftime('%Y%m%d%H%M%S%f')}",
        created_at=now.isoformat(timespec="seconds"),
        work_date=work_date,
        hours=hours,
        kind=kind,
        start_time=start_time,
        end_time=end_time,
        memo=memo,
    )
    state = read_state()
    records = [item for item in list(state.get("overtime_records") or []) if isinstance(item, dict)]
    _ensure_no_duplicate_overtime_time(record, records)
    records.append(record)
    state["overtime_records"] = records[-1000:]
    write_state(state)
    return _record_saved_message("연장 근무 기록을 저장했습니다.", record)


def update_overtime_record(
    *,
    record_id: str,
    work_date: str,
    hours: str = "",
    kind: str = "overtime",
    start_time: str = "",
    end_time: str = "",
    memo: str = "",
) -> str:
    state = read_state()
    records = [item for item in list(state.get("overtime_records") or []) if isinstance(item, dict)]
    for index, item in enumerate(records):
        if str(item.get("id") or "") != record_id:
            continue
        updated = _build_record(
            record_id=record_id,
            created_at=str(item.get("created_at") or ""),
            work_date=work_date,
            hours=hours,
            kind=kind,
            start_time=start_time,
            end_time=end_time,
            memo=memo,
        )
        _ensure_no_duplicate_overtime_time(updated, records, exclude_id=record_id)
        records[index] = updated
        state["overtime_records"] = records
        write_state(state)
        return _record_saved_message("연장 근무 기록을 수정했습니다.", records[index])
    raise RuntimeError(f"연장 근무 기록을 찾지 못했습니다: {record_id}")


def delete_overtime_record(*, record_id: str) -> str:
    state = read_state()
    records = [item for item in list(state.get("overtime_records") or []) if isinstance(item, dict)]
    next_records = [item for item in records if str(item.get("id") or "") != record_id]
    if len(next_records) == len(records):
        raise RuntimeError(f"연장 근무 기록을 찾지 못했습니다: {record_id}")
    state["overtime_records"] = next_records
    write_state(state)
    return "연장 근무 기록을 삭제했습니다."


def _build_record(
    *,
    record_id: str,
    created_at: str,
    work_date: str,
    hours: str,
    kind: str,
    start_time: str,
    end_time: str,
    memo: str,
) -> dict:
    normalized_date = _parse_date(work_date or date.today().isoformat())
    settings = _settings()
    calculated = _calculate_time_breakdown(normalized_date, start_time, end_time, settings["rounding_minutes"])
    rounded_hours = calculated["hours"] if calculated else _round_hours(_decimal(hours), settings["rounding_minutes"])
    if rounded_hours <= 0:
        raise RuntimeError("연장 근무 시간은 0보다 커야 합니다.")
    selected_kind = kind if kind in {"overtime", "night", "holiday"} else "overtime"
    is_weekend = _is_weekend(normalized_date)
    return {
        "id": record_id,
        "created_at": created_at,
        "date": normalized_date,
        "hours": str(rounded_hours),
        "kind": selected_kind,
        "effective_kind": _effective_kind(
            {
                "date": normalized_date,
                "kind": selected_kind,
                "night_hours": str(calculated["night_hours"]) if calculated else "",
                "holiday_hours": str(calculated["holiday_hours"]) if calculated else "",
            }
        ),
        "is_weekend": is_weekend,
        "day_type": "weekend" if is_weekend else "weekday",
        "start_time": calculated["start_time"] if calculated else "",
        "end_time": calculated["end_time"] if calculated else "",
        "auto_classified": bool(calculated),
        "night_hours": str(calculated["night_hours"]) if calculated else "0",
        "holiday_hours": str(calculated["holiday_hours"]) if calculated else str(rounded_hours if selected_kind == "holiday" else 0),
        "memo": memo.strip(),
    }


def _record_saved_message(title: str, record: dict) -> str:
    settings = _settings()
    amount = _record_amount(record, settings)
    return "\n".join(
        [
            title,
            f"- id: {record['id']}",
            f"- date: {record['date']}",
            f"- time: {_time_range_label(record)}",
            f"- hours: {record['hours']}",
            f"- kind: {_kind_label(record['effective_kind'])}",
            f"- estimated_allowance: {_money(amount, settings['currency'])}",
        ]
    )


def overtime_records(*, month: str = "", output_format: str = "json") -> str:
    records = _records(month)
    if output_format == "json":
        return json.dumps(records, ensure_ascii=False, indent=2)
    if not records:
        return "연장 근무 기록이 없습니다."
    return "\n".join(
        ["연장 근무 기록"]
        + [
            (
                f"- {item.get('date')} {item.get('hours')}h "
                f"{_kind_label(str(item.get('effective_kind') or item.get('kind') or 'overtime'))}"
                f"{' (자동)' if item.get('auto_classified') else ''}"
                f" | {item.get('memo') or '-'}"
            )
            for item in records
        ]
    )


def overtime_summary(*, month: str = "", output_format: str = "json") -> str:
    month = month or date.today().strftime("%Y-%m")
    settings = _settings()
    records = _records(month)
    total_hours = sum((_decimal(str(item.get("hours") or "0")) for item in records), Decimal("0"))
    gross_amount = sum((_record_amount(item, settings) for item in records), Decimal("0"))
    included_hours = _included_monthly_hours(settings)
    payable_hours = max(Decimal("0"), total_hours - included_hours) if settings.get("inclusive_salary_enabled") else total_hours
    calculated_included_allowance = _included_allowance(settings)
    effective_included_allowance = calculated_included_allowance if settings.get("inclusive_salary_enabled") else Decimal("0")
    estimated_allowance = (
        max(Decimal("0"), gross_amount - effective_included_allowance)
        if settings.get("inclusive_salary_enabled")
        else gross_amount
    ).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    payload = {
        "month": month,
        "currency": settings["currency"],
        "record_count": len(records),
        "total_hours": str(total_hours),
        "included_hours": str(included_hours),
        "payable_hours": str(payable_hours),
        "effective_hourly_rate": str(_effective_hourly_rate(settings).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
        "gross_calculated_allowance": str(gross_amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
        "included_allowance": str(effective_included_allowance.quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
        "calculated_included_allowance": str(calculated_included_allowance.quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
        "contract_included_allowance": str(_decimal(settings["inclusive_overtime_pay"]).quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
        "estimated_allowance": str(estimated_allowance),
        "settings": settings,
        "records": records,
    }
    if output_format == "json":
        return json.dumps(payload, ensure_ascii=False, indent=2)
    return "\n".join(
        [
            f"{month} 연장 근무 요약",
            f"- 기록: {len(records)}건",
            f"- 시간: {total_hours}h",
            f"- 포괄 포함 시간: {included_hours}h",
            f"- 추가 산정 시간: {payable_hours}h",
            f"- 예상 추가 수당: {_money(estimated_allowance, settings['currency'])}",
            "- 실제 지급액은 회사 정책/근로계약/세전·세후 기준에 따라 달라질 수 있습니다.",
        ]
    )


def overtime_settings(*, output_format: str = "json") -> str:
    settings = _settings()
    if output_format == "json":
        return json.dumps(settings, ensure_ascii=False, indent=2)
    return "\n".join([f"{key}: {value}" for key, value in settings.items()])


def _settings() -> dict:
    state = read_state()
    raw = state.get("overtime_settings") if isinstance(state.get("overtime_settings"), dict) else {}
    return {**DEFAULT_SETTINGS, **raw}


def _records(month: str = "") -> list[dict]:
    records = [item for item in list(read_state().get("overtime_records") or []) if isinstance(item, dict)]
    if month:
        records = [item for item in records if str(item.get("date") or "").startswith(month)]
    return sorted((_enriched_record(item) for item in records), key=lambda item: str(item.get("date") or ""), reverse=True)


def _record_amount(record: dict, settings: dict) -> Decimal:
    hours = _decimal(str(record.get("hours") or "0"))
    rate = _effective_hourly_rate(settings)
    multiplier = _decimal(settings["overtime_multiplier"])
    if record.get("auto_classified"):
        night_hours = _decimal(str(record.get("night_hours") or "0"))
        holiday_hours = _decimal(str(record.get("holiday_hours") or "0"))
        amount = hours * rate * multiplier
        amount += night_hours * rate * _decimal(settings["night_multiplier"])
        amount += holiday_hours * rate * _decimal(settings["holiday_multiplier"])
        return amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP)

    kind = _effective_kind(record)
    if "night" in kind:
        multiplier += _decimal(settings["night_multiplier"])
    if "holiday" in kind:
        multiplier += _decimal(settings["holiday_multiplier"])
    return (hours * rate * multiplier).quantize(Decimal("1"), rounding=ROUND_HALF_UP)


def _effective_hourly_rate(settings: dict) -> Decimal:
    explicit_rate = _decimal(settings["hourly_rate"])
    if explicit_rate > 0:
        return explicit_rate
    monthly_hours = _decimal(str(settings.get("monthly_standard_hours") or "209"))
    if monthly_hours <= 0:
        monthly_hours = Decimal("209")
    statutory_base_pay = _decimal(str(settings.get("statutory_base_pay") or "0"))
    if statutory_base_pay > 0:
        return statutory_base_pay / monthly_hours
    base_monthly_salary = _decimal(str(settings.get("base_monthly_salary") or "0"))
    if base_monthly_salary > 0:
        return base_monthly_salary / monthly_hours
    return Decimal("0")


def _enriched_record(record: dict) -> dict:
    enriched = dict(record)
    normalized_date = str(enriched.get("date") or "")
    is_weekend = _is_weekend(normalized_date)
    enriched["kind"] = str(enriched.get("kind") or "overtime")
    enriched["effective_kind"] = _effective_kind(enriched)
    enriched["is_weekend"] = is_weekend
    enriched["day_type"] = "weekend" if is_weekend else "weekday"
    enriched["start_time"] = str(enriched.get("start_time") or "")
    enriched["end_time"] = str(enriched.get("end_time") or "")
    enriched["auto_classified"] = bool(enriched.get("auto_classified"))
    enriched["night_hours"] = str(enriched.get("night_hours") or "0")
    enriched["holiday_hours"] = str(enriched.get("holiday_hours") or "0")
    return enriched


def _effective_kind(record: dict) -> str:
    kind = str(record.get("kind") or "overtime")
    is_weekend = _is_weekend(str(record.get("date") or ""))
    night_hours = _decimal(str(record.get("night_hours") or "0"))
    holiday_hours = _decimal(str(record.get("holiday_hours") or "0"))
    if holiday_hours > 0 and night_hours > 0:
        return "holiday_night"
    if holiday_hours > 0:
        return "holiday"
    if night_hours > 0:
        return "night"
    if kind == "night" and is_weekend:
        return "holiday_night"
    if kind == "overtime" and is_weekend:
        return "holiday"
    return kind


def _calculate_time_breakdown(work_date: str, start_value: str, end_value: str, rounding_minutes: int) -> dict | None:
    start_value = start_value.strip()
    end_value = end_value.strip()
    if not start_value and not end_value:
        return None
    if not start_value or not end_value:
        raise RuntimeError("시작 시간과 종료 시간을 함께 입력해 주세요.")

    start_clock = _parse_time(start_value)
    end_clock = _parse_time(end_value)
    start_dt = datetime.combine(date.fromisoformat(work_date), start_clock)
    end_dt = datetime.combine(date.fromisoformat(work_date), end_clock)
    if end_dt <= start_dt:
        end_dt += timedelta(days=1)

    total_hours = _round_hours(_duration_hours(start_dt, end_dt), rounding_minutes)
    night_hours = _round_hours(_overlap_hours(start_dt, end_dt, _night_windows(start_dt, end_dt)), rounding_minutes)
    holiday_hours = _round_hours(_overlap_hours(start_dt, end_dt, _holiday_windows(start_dt, end_dt)), rounding_minutes)
    return {
        "hours": total_hours,
        "night_hours": min(night_hours, total_hours),
        "holiday_hours": min(holiday_hours, total_hours),
        "start_time": _format_time(start_clock),
        "end_time": _format_time(end_clock),
    }


def _night_windows(start_dt: datetime, end_dt: datetime) -> list[tuple[datetime, datetime]]:
    windows: list[tuple[datetime, datetime]] = []
    current = start_dt.date() - timedelta(days=1)
    while current <= end_dt.date():
        windows.append((datetime.combine(current, time(22, 0)), datetime.combine(current + timedelta(days=1), time(6, 0))))
        current += timedelta(days=1)
    return windows


def _holiday_windows(start_dt: datetime, end_dt: datetime) -> list[tuple[datetime, datetime]]:
    windows: list[tuple[datetime, datetime]] = []
    current = start_dt.date()
    while current <= end_dt.date():
        if current.weekday() >= 5:
            windows.append((datetime.combine(current, time.min), datetime.combine(current + timedelta(days=1), time.min)))
        current += timedelta(days=1)
    return windows


def _overlap_hours(start_dt: datetime, end_dt: datetime, windows: list[tuple[datetime, datetime]]) -> Decimal:
    seconds = 0.0
    for window_start, window_end in windows:
        overlap_start = max(start_dt, window_start)
        overlap_end = min(end_dt, window_end)
        if overlap_end > overlap_start:
            seconds += (overlap_end - overlap_start).total_seconds()
    return Decimal(str(seconds)) / Decimal(3600)


def _duration_hours(start_dt: datetime, end_dt: datetime) -> Decimal:
    return Decimal(str((end_dt - start_dt).total_seconds())) / Decimal(3600)


def _parse_time(value: str) -> time:
    try:
        return datetime.strptime(value, "%H:%M").time()
    except ValueError as exc:
        raise RuntimeError(f"시간 형식이 올바르지 않습니다: {value}. HH:MM 형식으로 입력해 주세요.") from exc


def _format_time(value: time) -> str:
    return value.strftime("%H:%M")


def _time_range_label(record: dict) -> str:
    start_value = str(record.get("start_time") or "")
    end_value = str(record.get("end_time") or "")
    if start_value and end_value:
        return f"{start_value}-{end_value}"
    return "-"


def _ensure_no_duplicate_overtime_time(record: dict, records: list[dict], *, exclude_id: str = "") -> None:
    for item in records:
        if exclude_id and str(item.get("id") or "") == exclude_id:
            continue
        if _is_duplicate_overtime_time(record, item):
            raise RuntimeError(
                "\n".join(
                    [
                        "이미 겹치는 연장 근무 기록이 있습니다.",
                        f"- 기존: {item.get('date') or '-'} {_time_range_label(item)} {item.get('hours') or '-'}h",
                        f"- 신규: {record.get('date') or '-'} {_time_range_label(record)} {record.get('hours') or '-'}h",
                    ]
                )
            )


def _is_duplicate_overtime_time(left: dict, right: dict) -> bool:
    left_range = _record_interval(left)
    right_range = _record_interval(right)
    if left_range and right_range:
        return _intervals_overlap(left_range, right_range)
    if left_range or right_range:
        return False
    return (
        str(left.get("date") or "") == str(right.get("date") or "")
        and str(left.get("effective_kind") or left.get("kind") or "") == str(right.get("effective_kind") or right.get("kind") or "")
        and _decimal(str(left.get("hours") or "0")) == _decimal(str(right.get("hours") or "0"))
    )


def _record_interval(record: dict) -> tuple[datetime, datetime] | None:
    work_date = str(record.get("date") or "")
    start_value = str(record.get("start_time") or "").strip()
    end_value = str(record.get("end_time") or "").strip()
    if not work_date or not start_value or not end_value:
        return None
    start_dt = datetime.combine(date.fromisoformat(work_date), _parse_time(start_value))
    end_dt = datetime.combine(date.fromisoformat(work_date), _parse_time(end_value))
    if end_dt <= start_dt:
        end_dt += timedelta(days=1)
    return start_dt, end_dt


def _intervals_overlap(left: tuple[datetime, datetime], right: tuple[datetime, datetime]) -> bool:
    left_start, left_end = left
    right_start, right_end = right
    return max(left_start, right_start) < min(left_end, right_end)


def _is_weekend(value: str) -> bool:
    try:
        return date.fromisoformat(value).weekday() >= 5
    except ValueError:
        return False


def _kind_label(value: str) -> str:
    if value == "holiday_night":
        return "휴일·야간"
    if value == "night":
        return "야간"
    if value == "holiday":
        return "휴일"
    return "연장"


def _included_monthly_hours(settings: dict) -> Decimal:
    if not settings.get("inclusive_salary_enabled"):
        return Decimal("0")
    return (_decimal(settings["inclusive_weekly_hours"]) * Decimal("4.345")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _included_allowance(settings: dict) -> Decimal:
    if not settings.get("inclusive_salary_enabled"):
        return Decimal("0")
    return (_included_monthly_hours(settings) * _effective_hourly_rate(settings) * _decimal(settings["overtime_multiplier"])).quantize(
        Decimal("1"),
        rounding=ROUND_HALF_UP,
    )


def _round_hours(hours: Decimal, rounding_minutes: int) -> Decimal:
    minutes = hours * Decimal(60)
    rounded_minutes = (minutes / Decimal(rounding_minutes)).quantize(Decimal("1"), rounding=ROUND_HALF_UP) * Decimal(rounding_minutes)
    return (rounded_minutes / Decimal(60)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _parse_date(value: str) -> str:
    return date.fromisoformat(value).isoformat()


def _decimal(value: str) -> Decimal:
    try:
        return Decimal(str(value).replace(",", "").strip())
    except Exception as exc:
        raise RuntimeError(f"숫자 형식이 올바르지 않습니다: {value}") from exc


def _money(value: Decimal, currency: str) -> str:
    rounded = value.quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    return f"{int(rounded):,} {currency}"
