# Beckn v2 Migration - Local ONIX Test Setup

A local, runnable test network for [`beckn-v2-migration-docs`](https://github.com/abhey-WIL/beckn-v2-migration-docs)
(the V2 payload mapper, adapter configs and sample payloads for the UP ONA
agri-schemes/agri-procurement/soil-testing Beckn v2 migration project) - so
you can run **ONIX** locally with that mapper wired in, and fire edited
payloads at it to see them validated, transformed, signed and routed.

- `beckn-v2-migration-docs/` - an unmodified, vendored snapshot of the
  upstream docs repo (mapper source, sample configs, sample payloads,
  Postman collections). Kept for reference; `scripts/sync-mapper.sh`
  refreshes it.
- `local-setup/` - the actual runnable stack: two [beckn-onix](https://github.com/beckn/beckn-onix)
  adapters (BAP + BPP) wired to the V2 mapper, plus everything needed to
  send it payloads.

## Architecture

```
edit a payload                         BAP-side adapter                BPP-side adapter
in local-setup/payloads/               (onix-bap :8081)                (onix-bpp :8082)
        │                                     │                              │
        │  POST /bap/caller/discover          │                              │
        └────────────────────────────────────►│                              │
                                        transformPayload (V2 mapper:         │
                                          v1 legacy shape -> v2)             │
                                        addRoute -> sign -> validateSchema   │
                                               │                              │
                                               │  POST /bpp/receiver/discover │
                                               └─────────────────────────────►│
                                                                       validateSign (DeDi registry)
                                                                       addRoute -> validateSchema
                                                                       transformPayload -> sandbox-bpp
```

`on_discover` / `on_confirm` / `on_status` flow the same way in reverse,
through `bpp/caller` back to `bap/receiver`, ending up at `sandbox-bap`.

Both adapters share the identity `bap.example.com` / `bpp.example.com` -
the same pre-registered testnet identity beckn-onix's own examples and the
[beckn/starter-kit](https://github.com/beckn/starter-kit) use, so signature
verification against the real DeDi registry works without registering
anything yourself.

Routing is **hardcoded to the local containers** (`config/routing/*.yaml`)
rather than resolved dynamically from the registry, so a full
request/transform/sign/route cycle runs entirely inside this stack instead
of being sent to whatever `bpp.example.com` actually resolves to on the
live network. This is the same "run fully offline" pattern beckn/starter-kit's
README documents.

## Quick start

**Option A - Docker Compose (recommended):**

```bash
cd local-setup
scripts/start.sh
```

Requires Docker with access to Docker Hub (pulls `fidedocker/onix-adapter`
and `fidedocker/sandbox-2.0`). Brings up Redis, both ONIX adapters, and the
real `sandbox-bap`/`sandbox-bpp` application simulators, which auto-generate
`on_*` responses - so `discover -> confirm -> status` runs end to end with
no manual steps beyond sending the initial request.

**Option B - native (no Docker Hub required):**

```bash
cd local-setup
scripts/native-run.sh
```

Builds `beckn-onix` from source with Go (only needs `proxy.golang.org`,
not Docker Hub) and runs everything as local processes: Redis,
`onix-server --config=bap.yaml` on :8081, `onix-server --config=bpp.yaml`
on :8082, plus two minimal Python stubs standing in for `sandbox-bap`/
`sandbox-bpp` on :3001/:3002. The stubs log whatever they receive and ACK,
but - unlike the real sandbox image - don't auto-generate `on_*` responses,
so `confirm`/`status` won't get a matching callback on their own. Use this
path if Docker Hub isn't reachable from your network; use Option A for the
full automatic round trip. This is exactly how the setup here was built and
verified (see "What's been verified" below).

Both put the adapters on the same ports (`8081`/`8082`), so
`scripts/send-payload.sh` works the same way regardless of which one you
used.

## Sending edited payloads

`local-setup/payloads/` has an editable copy of every sample payload from
`beckn-v2-migration-docs/sample-payloads/` (agri-schemes, agri-procurement,
soil-testing). Edit one, then:

```bash
cd local-setup
scripts/send-payload.sh bap-caller:discover payloads/agri-schemes/search.json
scripts/send-payload.sh bap-caller:confirm  payloads/agri-schemes/confirm.json
scripts/send-payload.sh bap-caller:status   payloads/agri-schemes/status.json
```

Watch the adapter logs while you do this - that's where you see the mapper's
transformed output, the generated signature, and the routing decision:

```bash
docker compose logs -f onix-bap onix-bpp        # Docker Compose
tail -f .native/logs/onix-bap.log .native/logs/onix-bpp.log   # native
```

`context.bap_id`/`context.bap_uri` in the sample payloads are placeholders
(`<bap_id>`, `<bap_uri>`) - fill them in with `bap.example.com` and any URL
before sending, or the mapper will happily carry the placeholders straight
through into the transformed output.

## Updating the mapper

When upstream `beckn-v2-migration-docs` publishes a new mapper version:

```bash
cd local-setup
scripts/sync-mapper.sh
docker compose restart onix-bap onix-bpp   # or: scripts/native-stop.sh && scripts/native-run.sh
```

## What's been verified

Everything in `local-setup/` was built and exercised end to end (native
mode) while putting this together: `go build` of `beckn-onix`'s server and
all plugins, both adapters starting against these exact config files, and a
real `discover` payload sent through `bap/caller` - confirmed via the logs
that the V2 mapper correctly transformed the legacy v1-shaped
`agri-schemes/search.json` into a v2 catalog-filter payload (JSONPath
expression, `textSearch`, camelCased context, `version` bumped to `2.0.0`),
that it was signed and passed real v2 OpenAPI schema validation
(fetched live from `raw.githubusercontent.com`), and that it was routed to
and received by the local BPP adapter.

The one hop that could not be exercised in the sandbox this was built in is
signature verification against the live DeDi registry
(`fabric.nfh.global`) - that host was blocked by the sandbox's own network
policy (confirmed via an explicit 403), the same restriction that also
blocked pulling Docker Hub images there. Neither is a defect in this setup;
both are expected to work normally on a machine with ordinary internet
access, which is what `scripts/start.sh`/`scripts/native-run.sh` are built
for.

## Repository structure

```
beckn-v2-migration-docs/     vendored snapshot of the upstream docs repo
local-setup/
├── docker-compose.yml
├── config/
│   ├── bap.yaml              BAP adapter: modules, plugins, keys
│   ├── bpp.yaml               BPP adapter: modules, plugins, keys
│   ├── mappings.yaml          the V2 mapper (from mappings-v2/mappings/mappings.yaml)
│   └── routing/
│       ├── bap-caller.yaml    BAP outbound routing (local, hardcoded)
│       ├── bap-receiver.yaml  BAP inbound routing -> sandbox-bap
│       ├── bpp-caller.yaml    BPP outbound routing (local, hardcoded)
│       └── bpp-receiver.yaml  BPP inbound routing -> sandbox-bpp
├── payloads/                  editable copies of the sample payloads
└── scripts/
    ├── start.sh / stop.sh             Docker Compose
    ├── native-run.sh / native-stop.sh native fallback
    ├── send-payload.sh                POST a payload to a running adapter
    └── sync-mapper.sh                 pull the latest mapper from upstream
```

## Credits

Built on [beckn/beckn-onix](https://github.com/beckn/beckn-onix) (the ONIX
adapter) and informed by [beckn/starter-kit](https://github.com/beckn/starter-kit)'s
local network pattern. The mapper, configs and sample payloads come from
[abhey-WIL/beckn-v2-migration-docs](https://github.com/abhey-WIL/beckn-v2-migration-docs).
