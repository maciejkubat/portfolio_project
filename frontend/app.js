(function () {
  "use strict";

  const urlListEl = document.getElementById("url-list");
  const addUrlBtn = document.getElementById("add-url");
  const runCheckBtn = document.getElementById("run-check");
  const spinnerWrap = document.getElementById("spinner-wrap");
  const errorBox = document.getElementById("error-box");
  const summaryBox = document.getElementById("summary-box");
  const resultsEl = document.getElementById("results");

  function createUrlRow(value) {
    const row = document.createElement("div");
    row.className = "url-row";

    const control = document.createElement("div");
    control.className = "control";

    const input = document.createElement("input");
    input.className = "input";
    input.type = "url";
    input.placeholder = "https://example.com";
    input.value = value || "";

    control.appendChild(input);
    row.appendChild(control);

    const removeBtn = document.createElement("button");
    removeBtn.type = "button";
    removeBtn.className = "button is-danger is-light";
    removeBtn.innerHTML = "&times;";
    removeBtn.addEventListener("click", function () {
      if (urlListEl.children.length > 1) {
        row.remove();
      } else {
        input.value = "";
      }
    });
    row.appendChild(removeBtn);

    return row;
  }

  function addUrlRow(value) {
    urlListEl.appendChild(createUrlRow(value));
  }

  function getUrls() {
    return Array.from(urlListEl.querySelectorAll("input"))
      .map((input) => input.value.trim())
      .filter((value) => value.length > 0);
  }

  function showError(message) {
    errorBox.textContent = message;
    errorBox.style.display = "block";
  }

  function hideError() {
    errorBox.style.display = "none";
  }

  function setLoading(isLoading) {
    spinnerWrap.style.display = isLoading ? "flex" : "none";
    runCheckBtn.disabled = isLoading;
  }

  function renderResults(data) {
    resultsEl.innerHTML = "";

    document.getElementById("tag-total").textContent = "Total: " + data.total;
    document.getElementById("tag-healthy").textContent = "Healthy: " + data.healthy;
    document.getElementById("tag-unhealthy").textContent = "Unhealthy: " + data.unhealthy;
    summaryBox.style.display = "block";

    Object.entries(data.results).forEach(function ([url, result]) {
      const column = document.createElement("div");
      column.className = "column is-one-third";

      const isHealthy = result.status === "healthy";
      const tagClass = isHealthy ? "is-success" : "is-danger";
      const responseTime =
        result.response_time_ms !== null && result.response_time_ms !== undefined
          ? result.response_time_ms + " ms"
          : "n/a";

      column.innerHTML =
        '<div class="card result-card">' +
        '<div class="card-content">' +
        '<p class="result-url has-text-weight-semibold mb-2">' + escapeHtml(url) + "</p>" +
        '<span class="tag ' + tagClass + ' mb-2">' + escapeHtml(result.status) + "</span>" +
        '<p class="is-size-7">Response time: ' + responseTime + "</p>" +
        '<p class="is-size-7">Checked at: ' + escapeHtml(result.timestamp) + "</p>" +
        "</div>" +
        "</div>";

      resultsEl.appendChild(column);
    });
  }

  function escapeHtml(value) {
    const div = document.createElement("div");
    div.textContent = value === null || value === undefined ? "" : String(value);
    return div.innerHTML;
  }

  async function runHealthCheck() {
    hideError();
    resultsEl.innerHTML = "";
    summaryBox.style.display = "none";

    const urls = getUrls();
    if (urls.length === 0) {
      showError("Please add at least one URL.");
      return;
    }

    if (!window.API_URL) {
      showError("API_URL is not configured (config.js is missing or invalid).");
      return;
    }

    setLoading(true);

    try {
      const query = encodeURIComponent(urls.join(","));
      const response = await fetch(window.API_URL + "?urls=" + query);
      const data = await response.json();

      if (!response.ok) {
        showError(data.error || "Health check request failed (HTTP " + response.status + ").");
        return;
      }

      renderResults(data);
    } catch (err) {
      showError("Network error: " + err.message);
    } finally {
      setLoading(false);
    }
  }

  addUrlBtn.addEventListener("click", function () {
    addUrlRow("");
  });

  runCheckBtn.addEventListener("click", runHealthCheck);

  // Start with two empty rows for convenience.
  addUrlRow("");
  addUrlRow("");
})();
