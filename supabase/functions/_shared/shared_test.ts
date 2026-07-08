// Unit tests for pure _shared helpers. Run with:
//   deno test --allow-env supabase/functions/_shared/shared_test.ts
// (--allow-env because email.ts reads RESEND_API_KEY at module load.)

import { assertEquals } from "jsr:@std/assert@1";
import { jsonError, jsonResponse } from "./http.ts";
import { escapeHtml } from "./email.ts";
import { firstNameOf, guessFounderEmail, normalizeDomain } from "./contacts.ts";

Deno.test("jsonResponse sets status, CORS, and content type", async () => {
  const res = jsonResponse({ ok: true }, 201);
  assertEquals(res.status, 201);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(res.headers.get("Content-Type"), "application/json");
  assertEquals(await res.json(), { ok: true });
});

Deno.test("jsonError wraps the message", async () => {
  const res = jsonError("nope", 403);
  assertEquals(res.status, 403);
  assertEquals(await res.json(), { error: "nope" });
});

Deno.test("escapeHtml neutralizes markup and quotes", () => {
  assertEquals(
    escapeHtml(`<script>alert("x&y'z")</script>`),
    "&lt;script&gt;alert(&quot;x&amp;y&#39;z&quot;)&lt;/script&gt;",
  );
});

Deno.test("guessFounderEmail: plain name and domain", () => {
  assertEquals(guessFounderEmail("Jane Doe", "acme.io"), "jane@acme.io");
});

Deno.test("guessFounderEmail: honorific skipped, diacritics stripped, www removed", () => {
  assertEquals(guessFounderEmail("Dr. José Álvarez-Smith", "www.Acme.io"), "jose@acme.io");
});

Deno.test("guessFounderEmail: URL-shaped domain normalized", () => {
  assertEquals(guessFounderEmail("patrick collison", "https://stripe.com/about"), "patrick@stripe.com");
});

Deno.test("guessFounderEmail: bare honorific yields null", () => {
  assertEquals(guessFounderEmail("Dr.", "acme.io"), null);
});

Deno.test("guessFounderEmail: dotless domain yields null", () => {
  assertEquals(guessFounderEmail("Jane Doe", "localhost"), null);
});

Deno.test("guessFounderEmail: empty name yields null", () => {
  assertEquals(guessFounderEmail("", "acme.io"), null);
});

Deno.test("normalizeDomain strips scheme, path, and www", () => {
  assertEquals(normalizeDomain("https://www.Foo.Bar/baz?q=1"), "foo.bar");
  assertEquals(normalizeDomain("www.foo.bar"), "foo.bar");
  assertEquals(normalizeDomain(""), null);
});

Deno.test("firstNameOf returns the first token or null", () => {
  assertEquals(firstNameOf("Jane Doe"), "Jane");
  assertEquals(firstNameOf("   "), null);
});
