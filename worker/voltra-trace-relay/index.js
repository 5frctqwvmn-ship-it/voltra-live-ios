// voltra-trace-relay
// Cloudflare Worker. Receives Demo Mode trace JSON from the iOS app and
// opens a GitHub issue on 5frctqwvmn-ship-it/voltra-live-ios with the
// trace inline + a short summary header.
//
// Why a Worker (vs. shipping a GitHub PAT in the iOS binary):
//   • TestFlight / App Store binaries can be unpacked. Any embedded secret
//     is effectively public.
//   • A leaked PAT scoped to this repo would let an attacker open arbitrary
//     issues, edit them, even close PRs depending on scope.
//   • The Worker holds the PAT in env vars (encrypted at rest, never echoed
//     in logs) and sits behind a shared-secret header. The shared secret is
//     pure spam protection — losing it just means we have to rotate it,
//     not reissue any GitHub credentials.
//
// Required Cloudflare environment variables:
//   GITHUB_PAT           — fine-grained PAT with Issues:Write on the repo
//   GITHUB_REPO          — e.g. "5frctqwvmn-ship-it/voltra-live-ios"
//   APP_SHARED_TOKEN     — must match X-Voltra-Trace-Token from the iOS app
//
// Deploy:
//   wrangler deploy

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Health check
    if (request.method === "GET" && url.pathname === "/") {
      return json({ ok: true, service: "voltra-trace-relay" });
    }

    if (request.method !== "POST" || url.pathname !== "/trace") {
      return json({ error: "not found" }, 404);
    }

    // Auth — shared-secret header
    const provided = request.headers.get("X-Voltra-Trace-Token") || "";
    if (!env.APP_SHARED_TOKEN || provided !== env.APP_SHARED_TOKEN) {
      return json({ error: "unauthorized" }, 401);
    }

    // Parse body
    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ error: "invalid JSON body" }, 400);
    }
    if (!payload || typeof payload !== "object") {
      return json({ error: "missing body" }, 400);
    }

    // Trim very large bodies (issue body limit is ~64 KB, so cap traces)
    const MAX_INLINE = 50 * 1024;
    const records = Array.isArray(payload.records) ? payload.records : [];
    const header = payload.header || {};
    const userNote = (payload.userNote || "").toString().slice(0, 4000);

    // Build issue body
    const summary = [
      "## Demo Mode Trace",
      "",
      `- App: \`v${header.appShort || "?"} (${header.appBuild || "?"})\``,
      `- Entry source: \`${header.entrySource || "?"}\``,
      `- Started: \`${header.startedAtIso || "?"}\``,
      `- Device: \`${header.device || "?"} ${header.osVersion || ""}\``,
      `- Records: \`${records.length}\``,
      "",
      userNote ? `### Note from user\n\n${userNote}` : "",
      "",
      "### Trace JSON",
      "",
    ]
      .filter(Boolean)
      .join("\n");

    // Inline the JSON, truncating with a marker if it's too big.
    const fullJson = JSON.stringify(payload, null, 2);
    let traceBlock;
    if (fullJson.length <= MAX_INLINE) {
      traceBlock = "```json\n" + fullJson + "\n```";
    } else {
      // Keep the header + first N records inline, drop the rest with a note.
      const truncated = {
        header: payload.header,
        records: records.slice(0, 200),
        truncated: true,
        originalRecordCount: records.length,
      };
      traceBlock =
        "```json\n" +
        JSON.stringify(truncated, null, 2) +
        "\n```\n\n_Note: trace truncated, " +
        records.length +
        " total records, only first 200 inlined._";
    }

    const body = summary + traceBlock;
    const title = `[demo trace] v${header.appShort || "?"} (${
      header.appBuild || "?"
    }) — ${header.entrySource || "?"} — ${records.length} records`;

    // Open the GitHub issue
    if (!env.GITHUB_PAT || !env.GITHUB_REPO) {
      return json({ error: "GitHub config missing on relay" }, 500);
    }
    const ghResp = await fetch(
      `https://api.github.com/repos/${env.GITHUB_REPO}/issues`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.GITHUB_PAT}`,
          Accept: "application/vnd.github+json",
          "X-GitHub-Api-Version": "2022-11-28",
          "User-Agent": "voltra-trace-relay/1.0",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          title,
          body,
          labels: ["demo-trace"],
        }),
      }
    );
    if (!ghResp.ok) {
      const errText = await ghResp.text();
      return json(
        { error: "GitHub API error", status: ghResp.status, detail: errText },
        502
      );
    }
    const issue = await ghResp.json();
    return json({ ok: true, issueUrl: issue.html_url, number: issue.number });
  },
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
