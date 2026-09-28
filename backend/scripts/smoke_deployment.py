"""Run a repeatable, post-deployment smoke test against a live SayFridge API."""
from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from datetime import date
from urllib.parse import urlsplit

import httpx


SPACE_NAME = "Deployment Smoke Pantry"
DEFINITION_NAME = "Deployment Smoke Item"
INVENTORY_NOTE = "Created by the deployment smoke test; safe to reuse."


class SmokeFailure(RuntimeError):
    """A required deployed behavior did not pass."""


@dataclass(frozen=True, slots=True)
class SmokeConfig:
    base_url: str
    user_email: str
    user_password: str
    admin_email: str
    admin_password: str
    timeout_seconds: float = 20.0

    @classmethod
    def from_environment(cls, base_url: str | None = None) -> "SmokeConfig":
        values = {
            "SMOKE_BASE_URL": base_url or os.getenv("SMOKE_BASE_URL", ""),
            "SMOKE_USER_EMAIL": os.getenv("SMOKE_USER_EMAIL", ""),
            "SMOKE_USER_PASSWORD": os.getenv("SMOKE_USER_PASSWORD", ""),
            "SMOKE_ADMIN_EMAIL": os.getenv("SMOKE_ADMIN_EMAIL", ""),
            "SMOKE_ADMIN_PASSWORD": os.getenv("SMOKE_ADMIN_PASSWORD", ""),
        }
        missing = [name for name, value in values.items() if not value]
        if missing:
            raise SmokeFailure(
                "Missing smoke-test configuration: " + ", ".join(missing)
            )

        normalized_url = values["SMOKE_BASE_URL"].strip().rstrip("/")
        parsed = urlsplit(normalized_url)
        local_http = parsed.scheme == "http" and parsed.hostname in {
            "127.0.0.1",
            "localhost",
        }
        if (
            not parsed.netloc
            or (parsed.scheme != "https" and not local_http)
            or parsed.path
            or parsed.query
            or parsed.fragment
            or parsed.username is not None
            or parsed.password is not None
        ):
            raise SmokeFailure(
                "SMOKE_BASE_URL must be an HTTPS origin without a path, except "
                "for localhost development"
            )
        try:
            timeout = float(os.getenv("SMOKE_TIMEOUT_SECONDS", "20"))
        except ValueError as exc:
            raise SmokeFailure("SMOKE_TIMEOUT_SECONDS must be numeric") from exc
        if not 1 <= timeout <= 120:
            raise SmokeFailure("SMOKE_TIMEOUT_SECONDS must be between 1 and 120")

        return cls(
            base_url=normalized_url,
            user_email=values["SMOKE_USER_EMAIL"].strip().lower(),
            user_password=values["SMOKE_USER_PASSWORD"],
            admin_email=values["SMOKE_ADMIN_EMAIL"].strip().lower(),
            admin_password=values["SMOKE_ADMIN_PASSWORD"],
            timeout_seconds=timeout,
        )


def _json(response: httpx.Response, label: str) -> dict:
    try:
        body = response.json()
    except ValueError as exc:
        raise SmokeFailure(
            f"{label} returned non-JSON HTTP {response.status_code}: "
            f"{response.text[:300]}"
        ) from exc
    if not isinstance(body, dict):
        raise SmokeFailure(f"{label} returned a non-object JSON response")
    return body


def _expect(
    response: httpx.Response,
    expected_status: int | tuple[int, ...],
    label: str,
) -> dict:
    statuses = (expected_status,) if isinstance(expected_status, int) else expected_status
    if response.status_code not in statuses:
        raise SmokeFailure(
            f"{label} returned HTTP {response.status_code}, expected {statuses}: "
            f"{response.text[:500]}"
        )
    return _json(response, label)


def _login(client: httpx.Client, email: str, password: str, label: str) -> dict:
    body = _expect(
        client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
        ),
        200,
        label,
    )
    token = body.get("access_token")
    if not isinstance(token, str) or not token:
        raise SmokeFailure(f"{label} did not return an access token")
    return {"Authorization": f"Bearer {token}"}


def _find(items: list[dict], **expected) -> dict | None:
    return next(
        (
            item
            for item in items
            if all(item.get(key) == value for key, value in expected.items())
        ),
        None,
    )


def run_smoke(
    config: SmokeConfig,
    *,
    transport: httpx.BaseTransport | None = None,
    today: date | None = None,
) -> None:
    today = today or date.today()
    with httpx.Client(
        base_url=config.base_url,
        timeout=config.timeout_seconds,
        follow_redirects=False,
        transport=transport,
    ) as client:
        health = _expect(client.get("/health"), 200, "health check")
        if health.get("status") != "ok":
            raise SmokeFailure("health check did not report status=ok")
        print("PASS health")

        version = _expect(
            client.get("/api/v1/system/version"), 200, "version check"
        )
        if not isinstance(version.get("version"), str) or not version["version"]:
            raise SmokeFailure("version check did not return an application version")
        print(
            "PASS version "
            f"{version['version']} (commit {version.get('commit_sha') or 'unavailable'})"
        )

        credentials = {
            "email": config.user_email,
            "password": config.user_password,
        }
        registration = client.post("/api/v1/auth/register", json=credentials)
        _expect(registration, (201, 409), "registration")
        print("PASS registration (created or existing dedicated account)")

        user_headers = _login(
            client,
            config.user_email,
            config.user_password,
            "user login",
        )
        profile = _expect(
            client.get("/api/v1/auth/me", headers=user_headers),
            200,
            "current user",
        )
        if profile.get("email") != config.user_email.lower():
            raise SmokeFailure("current user does not match SMOKE_USER_EMAIL")
        print("PASS login and authenticated identity")

        spaces = _expect(
            client.get(
                "/api/v1/storage-spaces",
                params={"status": "ACTIVE", "page": 1, "page_size": 100},
                headers=user_headers,
            ),
            200,
            "storage-space list",
        ).get("items", [])
        space = _find(spaces, name=SPACE_NAME, status="ACTIVE")
        if space is None:
            space = _expect(
                client.post(
                    "/api/v1/storage-spaces",
                    json={"name": SPACE_NAME, "type": "PANTRY"},
                    headers=user_headers,
                ),
                201,
                "storage-space creation",
            )

        categories = _expect(
            client.get(
                "/api/v1/item-categories",
                params={"status": "ACTIVE", "page": 1, "page_size": 100},
                headers=user_headers,
            ),
            200,
            "category list",
        ).get("items", [])
        if not categories:
            raise SmokeFailure("category list is empty; initialize the deployment database")

        definitions = _expect(
            client.get(
                "/api/v1/item-definitions",
                params={
                    "status": "ACTIVE",
                    "scope": "PRIVATE",
                    "q": DEFINITION_NAME,
                    "page": 1,
                    "page_size": 100,
                },
                headers=user_headers,
            ),
            200,
            "item-definition list",
        ).get("items", [])
        definition = _find(
            definitions,
            name=DEFINITION_NAME,
            scope="PRIVATE",
            status="ACTIVE",
        )
        if definition is None:
            definition = _expect(
                client.post(
                    "/api/v1/item-definitions",
                    json={
                        "name": DEFINITION_NAME,
                        "category_id": categories[0]["id"],
                    },
                    headers=user_headers,
                ),
                201,
                "item-definition creation",
            )

        inventory = _expect(
            client.get(
                "/api/v1/inventory-items",
                params={
                    "status": "IN_STOCK",
                    "q": DEFINITION_NAME,
                    "page": 1,
                    "page_size": 100,
                },
                headers=user_headers,
            ),
            200,
            "inventory list",
        ).get("items", [])
        item = _find(inventory, item_definition_id=definition["id"])
        if item is None:
            item = _expect(
                client.post(
                    "/api/v1/inventory-items",
                    json={
                        "storage_space_id": space["id"],
                        "item_definition_id": definition["id"],
                        "amount": "1",
                        "unit": "each",
                        "expiry_date": today.isoformat(),
                        "notes": INVENTORY_NOTE,
                    },
                    headers=user_headers,
                ),
                201,
                "inventory creation",
            )
        _expect(
            client.get(
                f"/api/v1/inventory-items/{item['id']}",
                headers=user_headers,
            ),
            200,
            "inventory detail",
        )
        print("PASS inventory list, creation/reuse, and detail")

        expiry = _expect(
            client.get(
                "/api/v1/inventory-items/expiry-summary",
                params={
                    "as_of": today.isoformat(),
                    "days_before": 3,
                    "page": 1,
                    "page_size": 100,
                },
                headers=user_headers,
            ),
            200,
            "expiry summary",
        )
        if _find(expiry.get("items", []), id=item["id"]) is None:
            raise SmokeFailure("expiry summary did not include the smoke inventory item")
        print("PASS expiry summary")

        admin_headers = _login(
            client,
            config.admin_email,
            config.admin_password,
            "administrator login",
        )
        users = _expect(
            client.get(
                "/api/v1/admin/users",
                params={"q": config.user_email, "page": 1, "page_size": 20},
                headers=admin_headers,
            ),
            200,
            "administrator user list",
        ).get("items", [])
        if _find(users, email=config.user_email.lower()) is None:
            raise SmokeFailure("administrator query did not return the smoke user")
        print("PASS administrator authentication and account query")

    print("Deployment smoke test passed.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-url",
        help="Deployed backend origin; otherwise read SMOKE_BASE_URL.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        run_smoke(SmokeConfig.from_environment(args.base_url))
    except (SmokeFailure, httpx.HTTPError) as exc:
        print(f"Deployment smoke test failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
