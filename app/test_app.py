"""Unit tests for the health-check Lambda function."""

import json
import urllib.error
from unittest.mock import patch

import app


class FakeResponse:
    """Minimal stand-in for the object returned by urllib.request.urlopen()."""

    def __init__(self, status):
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class TestCheckUrl:
    @patch("app.urllib.request.urlopen")
    def test_healthy_when_status_200(self, mock_urlopen):
        mock_urlopen.return_value = FakeResponse(200)

        result = app.check_url("https://example.com")

        assert result["status"] == "healthy"
        assert result["http_status"] == 200
        assert result["response_time_ms"] >= 0
        assert result["url"] == "https://example.com"
        assert "timestamp" in result

    @patch("app.urllib.request.urlopen")
    def test_unhealthy_when_status_not_200(self, mock_urlopen):
        mock_urlopen.return_value = FakeResponse(301)

        result = app.check_url("https://example.com")

        assert result["status"] == "unhealthy"
        assert result["http_status"] == 301

    @patch("app.urllib.request.urlopen")
    def test_unhealthy_on_http_error(self, mock_urlopen):
        mock_urlopen.side_effect = urllib.error.HTTPError(
            url="https://example.com", code=500, msg="Server Error", hdrs=None, fp=None
        )

        result = app.check_url("https://example.com")

        assert result["status"] == "unhealthy"
        assert result["http_status"] == 500
        assert "HTTP 500" in result["error"]

    @patch("app.urllib.request.urlopen")
    def test_unhealthy_on_connection_error(self, mock_urlopen):
        mock_urlopen.side_effect = urllib.error.URLError("Name or service not known")

        result = app.check_url("https://does-not-exist.invalid")

        assert result["status"] == "unhealthy"
        assert result["http_status"] is None
        assert "Connection error" in result["error"]


class TestGetUrls:
    def test_urls_from_event(self):
        event = {"urls": ["https://a.com", "https://b.com"]}
        assert app.get_urls(event) == ["https://a.com", "https://b.com"]

    def test_urls_from_query_string_parameters(self):
        event = {"queryStringParameters": {"urls": "https://a.com, https://b.com"}}
        assert app.get_urls(event) == ["https://a.com", "https://b.com"]

    def test_urls_from_env_var(self, monkeypatch):
        monkeypatch.setenv("HEALTHCHECK_URLS", "https://a.com,https://b.com")
        assert app.get_urls({}) == ["https://a.com", "https://b.com"]

    def test_no_urls_returns_empty_list(self, monkeypatch):
        monkeypatch.delenv("HEALTHCHECK_URLS", raising=False)
        assert app.get_urls({}) == []


class TestLambdaHandler:
    @patch("app.check_url")
    def test_returns_400_when_no_urls(self, mock_check_url, monkeypatch):
        monkeypatch.delenv("HEALTHCHECK_URLS", raising=False)

        response = app.lambda_handler({}, None)

        assert response["statusCode"] == 400
        assert json.loads(response["body"]) == {"error": "No URLs to check"}
        mock_check_url.assert_not_called()

    @patch("app.check_url")
    def test_returns_200_with_results_keyed_by_url(self, mock_check_url):
        mock_check_url.side_effect = [
            {
                "url": "https://a.com",
                "status": "healthy",
                "http_status": 200,
                "response_time_ms": 12.3,
                "timestamp": "2026-01-01T00:00:00+00:00",
            },
            {
                "url": "https://b.com",
                "status": "unhealthy",
                "http_status": 500,
                "response_time_ms": 45.6,
                "timestamp": "2026-01-01T00:00:00+00:00",
                "error": "HTTP 500: Server Error",
            },
        ]

        event = {"urls": ["https://a.com", "https://b.com"]}
        response = app.lambda_handler(event, None)
        body = json.loads(response["body"])

        assert response["statusCode"] == 200
        assert body["total"] == 2
        assert body["healthy"] == 1
        assert body["unhealthy"] == 1
        assert body["overall_status"] == "degraded"
        assert body["results"]["https://a.com"]["status"] == "healthy"
        assert body["results"]["https://b.com"]["status"] == "unhealthy"
