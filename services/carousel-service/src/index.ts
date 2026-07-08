// TODO(deferred): Decide the fate of this service. It's a standalone
// Fastify + Cloudflare R2 + Redis carousel *image* renderer that nothing
// currently imports — the live carousel path is text slides via the
// generate-carousel edge function. Either delete it (recommended until there's
// a product reason for image carousels) or wire it up. Effort: small to
// delete, large to integrate. See docs/DEFERRED_WORK.md.
import Fastify from "fastify";

const app = Fastify({ logger: true });

app.get("/health", async () => ({ ok: true }));

const port = Number(process.env.PORT ?? 3100);
await app.listen({ port, host: "0.0.0.0" });

console.log(`carousel-service listening on :${port}`);
