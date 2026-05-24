from __future__ import annotations

import base64
import json
import socket
import ssl
from typing import Any
from urllib import request
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


def basic_auth_header(username: str, token: str) -> str:
    raw = f"{username}:{token}".encode("utf-8")
    return "Basic " + base64.b64encode(raw).decode("ascii")


def json_request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
    timeout: int = 30,
) -> Any:
    data = None
    merged_headers = {"Accept": "application/json"}
    if headers:
        merged_headers.update(headers)
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        merged_headers["Content-Type"] = "application/json"

    req = request.Request(url, data=data, headers=merged_headers, method=method.upper())
    try:
        with request.urlopen(req, timeout=timeout, context=_ssl_context()) as response:
            body = response.read().decode("utf-8")
            return _parse_response_body(body)
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method.upper()} {_safe_url(url)} failed with HTTP {exc.code}: {_clip_body(body)}") from exc
    except URLError as exc:
        reason = getattr(exc, "reason", exc)
        if isinstance(reason, ssl.SSLCertVerificationError):
            raise RuntimeError(
                "HTTPS 인증서 검증에 실패했습니다. "
                "네트워크 프록시/보안 프로그램이 인증서를 바꾸고 있거나, 앱에 CA 인증서 번들이 포함되지 않았을 수 있습니다. "
                f"상세: {reason}"
            ) from exc
        raise RuntimeError(f"{method.upper()} {_safe_url(url)} 요청에 실패했습니다: {reason}") from exc
    except TimeoutError as exc:
        raise RuntimeError(f"{method.upper()} {_safe_url(url)} 요청 시간이 초과되었습니다: {timeout}s") from exc
    except OSError as exc:
        if isinstance(exc, socket.timeout):
            raise RuntimeError(f"{method.upper()} {_safe_url(url)} 요청 시간이 초과되었습니다: {timeout}s") from exc
        raise RuntimeError(f"{method.upper()} {_safe_url(url)} 요청 중 네트워크 오류가 발생했습니다: {exc}") from exc


def _ssl_context() -> ssl.SSLContext:
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        return ssl.create_default_context()


def _parse_response_body(body: str) -> Any:
    if not body:
        return None
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {"text": body}


def _safe_url(url: str) -> str:
    sensitive = {"token", "key", "api_key", "apikey", "authorization", "secret", "client_secret"}
    parts = urlsplit(url)
    query = urlencode(
        [
            (key, "***" if key.lower() in sensitive else value)
            for key, value in parse_qsl(parts.query, keep_blank_values=True)
        ]
    )
    return urlunsplit((parts.scheme, parts.netloc, parts.path, query, ""))


def _clip_body(body: str, limit: int = 1200) -> str:
    text = body.strip()
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + "...(truncated)"
