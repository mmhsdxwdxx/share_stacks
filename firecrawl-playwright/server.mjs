import { createServer } from "node:http";
import { chromium, firefox, webkit } from "playwright";

const PORT = Number.parseInt(process.env.PORT ?? "3000", 10);
const BROWSER = (process.env.BROWSER ?? "chromium").toLowerCase();
const HEADLESS = (process.env.HEADLESS ?? "true").toLowerCase() !== "false";
const WAIT_UNTIL = process.env.WAIT_UNTIL ?? "domcontentloaded"; // domcontentloaded|load|networkidle
const BLOCK_MEDIA = (process.env.BLOCK_MEDIA ?? "true").toLowerCase() === "true";
const MAX_CONCURRENT_PAGES = Number.parseInt(
  process.env.MAX_CONCURRENT_PAGES ?? "4",
  10,
);
const NAVIGATION_TIMEOUT_MS = Number.parseInt(
  process.env.NAVIGATION_TIMEOUT_MS ?? "90000",
  10,
);
const ACTION_TIMEOUT_MS = Number.parseInt(
  process.env.ACTION_TIMEOUT_MS ?? "10000",
  10,
);

const PROXY_SERVER = process.env.PROXY_SERVER;
const PROXY_USERNAME = process.env.PROXY_USERNAME;
const PROXY_PASSWORD = process.env.PROXY_PASSWORD;

function json(res, statusCode, body) {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function readJson(req, maxBytes = 2 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", chunk => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new Error("payload too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      try {
        const text = Buffer.concat(chunks).toString("utf8");
        resolve(text ? JSON.parse(text) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

class Semaphore {
  constructor(maxPermits) {
    this.maxPermits = Math.max(1, maxPermits);
    this.permits = this.maxPermits;
    this.queue = [];
  }
  acquire() {
    if (this.permits > 0) {
      this.permits -= 1;
      return Promise.resolve();
    }
    return new Promise(resolve => this.queue.push(resolve));
  }
  release() {
    const next = this.queue.shift();
    if (next) next();
    else this.permits = Math.min(this.maxPermits, this.permits + 1);
  }
}

const semaphore = new Semaphore(MAX_CONCURRENT_PAGES);

function pickBrowser() {
  if (BROWSER === "firefox") return firefox;
  if (BROWSER === "webkit") return webkit;
  return chromium;
}

let browserPromise;
async function getBrowser() {
  if (!browserPromise) {
    const proxy =
      PROXY_SERVER && PROXY_SERVER.trim()
        ? {
            server: PROXY_SERVER,
            username: PROXY_USERNAME || undefined,
            password: PROXY_PASSWORD || undefined,
          }
        : undefined;
    browserPromise = pickBrowser().launch({ headless: HEADLESS, proxy });
  }
  return browserPromise;
}

async function handleScrape(req, res) {
  const startedAt = Date.now();
  await semaphore.acquire();
  try {
    const body = await readJson(req);
    const url = body?.url;
    const waitAfterLoad = Number.parseInt(body?.wait_after_load ?? "0", 10) || 0;
    const timeout = Number.parseInt(body?.timeout ?? "", 10) || NAVIGATION_TIMEOUT_MS;
    const headers = body?.headers && typeof body.headers === "object" ? body.headers : undefined;
    const skipTlsVerification = !!body?.skip_tls_verification;

    if (!url || typeof url !== "string") {
      json(res, 400, { error: "url is required" });
      return;
    }

    const browser = await getBrowser();
    const context = await browser.newContext({
      ignoreHTTPSErrors: skipTlsVerification,
      extraHTTPHeaders: headers,
    });
    context.setDefaultTimeout(ACTION_TIMEOUT_MS);
    context.setDefaultNavigationTimeout(timeout);

    const page = await context.newPage();

    if (BLOCK_MEDIA) {
      await page.route("**/*", route => {
        const type = route.request().resourceType();
        if (type === "image" || type === "media" || type === "font") {
          route.abort();
          return;
        }
        route.continue();
      });
    }

    let response;
    let pageError;
    try {
      response = await page.goto(url, { waitUntil: WAIT_UNTIL, timeout });
    } catch (e) {
      pageError = e?.message ? String(e.message) : String(e);
    }

    if (waitAfterLoad > 0) {
      const remaining = Math.max(0, timeout - (Date.now() - startedAt));
      if (remaining > 0) {
        await page.waitForTimeout(Math.min(waitAfterLoad, remaining));
      }
    }

    const status = response?.status?.() ?? 0;
    const responseHeaders = response?.headers?.() ?? {};
    const contentType =
      responseHeaders["content-type"] ?? responseHeaders["Content-Type"];

    let content = "";
    try {
      if (contentType && String(contentType).includes("application/json")) {
        content = await response.text();
      } else {
        content = await page.content();
      }
    } catch (e) {
      if (!pageError) pageError = e?.message ? String(e.message) : String(e);
    } finally {
      await page.close().catch(() => {});
      await context.close().catch(() => {});
    }

    json(res, 200, {
      content,
      pageStatusCode: status,
      pageError,
      contentType,
    });
  } catch (e) {
    json(res, 500, { error: e?.message ? String(e.message) : String(e) });
  } finally {
    semaphore.release();
  }
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? "/", "http://localhost");

    if (req.method === "GET" && url.pathname === "/health") {
      res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
      res.end("ok");
      return;
    }

    if (req.method === "POST" && url.pathname === "/scrape") {
      await handleScrape(req, res);
      return;
    }

    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    res.end("not found");
  } catch (e) {
    res.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    res.end(e?.message ? String(e.message) : String(e));
  }
});

server.listen(PORT, "0.0.0.0", () => {
  // eslint-disable-next-line no-console
  console.log(
    JSON.stringify({
      msg: "firecrawl-playwright ready",
      port: PORT,
      browser: BROWSER,
      headless: HEADLESS,
      blockMedia: BLOCK_MEDIA,
      maxConcurrentPages: MAX_CONCURRENT_PAGES,
      waitUntil: WAIT_UNTIL,
    }),
  );
});

