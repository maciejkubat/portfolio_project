"""AWS Lambda: simple health-check for a list of URLs.

- Checks HTTP status (expected 200) for each URL.
- Returns the result in JSON: status, response time in ms, timestamp.
- Logs the run to AWS CloudWatch (standard logging module).

The list of URLs can come from (checked in this order):
1. the invocation event: {"urls": ["https://...", ...]} (direct/manual invoke)
2. API Gateway query string parameter: ?urls=https://a.com,https://b.com
3. the HEALTHCHECK_URLS environment variable (comma-separated URLs)
"""

import json
import logging
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DEFAULT_TIMEOUT_SECONDS = 5


def check_url(url: str, timeout: int = DEFAULT_TIMEOUT_SECONDS) -> dict:
    """Performs a single health-check and returns a dict with the result."""
    start = time.perf_counter()
    result = {
        "url": url,
        "status": "unhealthy",
        "http_status": None,
        "response_time_ms": None,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    request = urllib.request.Request(url, method="GET", headers={"User-Agent": "lambda-healthcheck/1.0"})

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
            result["http_status"] = response.status
            result["response_time_ms"] = elapsed_ms
            result["status"] = "healthy" if response.status == 200 else "unhealthy"
    except urllib.error.HTTPError as exc:
        result["http_status"] = exc.code
        result["response_time_ms"] = round((time.perf_counter() - start) * 1000, 2)
        result["error"] = f"HTTP {exc.code}: {exc.reason}"
    except urllib.error.URLError as exc:
        result["response_time_ms"] = round((time.perf_counter() - start) * 1000, 2)
        result["error"] = f"Connection error: {exc.reason}"
    except Exception as exc:  # e.g. socket timeout
        result["response_time_ms"] = round((time.perf_counter() - start) * 1000, 2)
        result["error"] = str(exc)

    return result


def get_urls(event: dict) -> list[str]:
    """Retrieves the list of URLs from the event, API Gateway query string, or the environment variable."""
    urls = event.get("urls") if isinstance(event, dict) else None

    if not urls and isinstance(event, dict):
        query_params = event.get("queryStringParameters") or {}
        query_urls = query_params.get("urls")
        if query_urls:
            urls = [u.strip() for u in query_urls.split(",") if u.strip()]

    if not urls:
        env_urls = os.environ.get("HEALTHCHECK_URLS", "")
        urls = [u.strip() for u in env_urls.split(",") if u.strip()]

    return urls or []


def lambda_handler(event, context):
    """AWS Lambda entry point."""
    logger.info("Health-check started. Event: %s", json.dumps(event, default=str))

    urls = get_urls(event)
    if not urls:
        logger.warning("No URLs provided (event 'urls' or env HEALTHCHECK_URLS).")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "No URLs to check"}),
        }

    results = {}
    for url in urls:
        logger.info("Checking URL: %s", url)
        result = check_url(url)
        if result["status"] == "healthy":
            logger.info("OK: %s (%s ms)", url, result["response_time_ms"])
        else:
            logger.error("FAILED: %s -> %s", url, result.get("error") or result["http_status"])
        results[url] = {
            "status": result["status"],
            "response_time_ms": result["response_time_ms"],
            "timestamp": result["timestamp"],
        }

    healthy_count = sum(1 for r in results.values() if r["status"] == "healthy")
    summary = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "total": len(results),
        "healthy": healthy_count,
        "unhealthy": len(results) - healthy_count,
        "overall_status": "healthy" if healthy_count == len(results) else "degraded",
        "results": results,
    }

    logger.info("Health-check finished: %s/%s healthy", healthy_count, len(results))

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(summary),
    }


if __name__ == "__main__":
    # Local test
    test_event = {"urls": ["https://example.com", "https://httpbin.org/status/500"]}
    print(json.dumps(json.loads(lambda_handler(test_event, None)["body"]), indent=2))
