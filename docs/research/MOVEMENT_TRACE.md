# Bounded movement trace prototype

The opt-in ground movement lab can write a local NDJSON observation trace when `-Dminecome.movementTraceFile=ABSOLUTE_PATH` is set. This is file IPC for the bounded follower experiment, separate from protocol-v1. Java emits observations; the PowerShell controller and game-thread Lua follower apply KCD poses and verify actual readbacks. The lab's existing movement lease, world guards and deadlines remain in force.

The file must be new, with an existing parent inside the actual workspace `runtime/evidence` directory. Resolved paths are checked to prevent a parent link escaping that directory; `CREATE_NEW` refuses an existing target. The receiver reads the file without modifying it. The writer flushes each record, limits the complete stream to **200 records / 64 KiB**, and reserves 2 KiB plus the last record slot for termination.

Every record contains `schema:1`, `kind`, `run`, `patch_sha256`, `source_kind`, `save`, `world`, strictly increasing `seq`, and `utc_ms`. `world` is the fresh lab save's UUID. The hash identifies the exact accepted ground-patch JSON, including its provenance. `source_kind` remains `standalone_fixture` for synthetic patches; file provenance alone is not authenticated live geometry.

- `kind:"begin"`: phase `SETTLING`, captured KCD `center:{x,y,z}`, Minecraft `anchor_mc:{x:0,y:64,z:0}`, local `started_monotonic_ns`, and explicit approximation flags.
- `kind:"sample"`: phase, local `monotonic_ns`, `server_seq`, `server_age_ns`, and separate `client` / `server` objects. Each contains feet `x/y/z`, `vx/vy/vz`, `on_ground`, and `proxy_support`. The `server` object is the authoritative observation for the bounded follower; the client object is separate prediction evidence.
- `kind:"end"`: phase, `result` (`passed`, `failed` or `stopped`), bounded reason and `last_server_seq`. An end record revokes the trace session; later appends are prohibited.

Samples are normally at most 10 Hz, during walking/rest/jump/landing. One initial and one final snapshot may bypass that throttle, while retaining the same freshness and sequence checks. Emission requires a newly advancing server sequence and an observation no older than **250 ms** on Java's monotonic clock. Throttled/stale/duplicate observations are skipped rather than relabelled fresh. Successful trace termination requires a fresh final `PASSED` snapshot; the lab releases its keys while awaiting that next advancing server observation, without extending its existing deadlines. UTC milliseconds permit another local process to impose its own age limit; monotonic clocks from different processes must not be compared. A missing end or stalled writer must expire at the receiver.

For this approximate static patch, the inverse coordinate mapping is:

```text
kcd.x = center.x + server.x
kcd.y = center.y - server.z
kcd.z = center.z + server.y - 64
```

That mapping is a captured local alignment, not shared-world calibration. A follower must verify the begin contract, patch hash, own process/world identity, increasing record/server sequences, timestamps, finite bounds and displacement before applying any pose. It must consume only the fresh `server` observation and stop on termination, failure, world change or stale input. The file's `SETTLING` snapshot does not authorize movement; actual active-phase and ground-proof requirements belong to the follower controller.

The receiver verifies exact fields and types, duplicate keys, run/hash/world identity,
contiguous record sequences and advancing server observations before committing state.
Only fresh active-phase samples following server ground/proxy proof authorize targets.
It bounds actual observation age to300ms by adding trace UTC age to
`server_age_ns`; the controller repeats that check immediately before dispatch.
The HTTP request has its own150ms limit, while the game independently enforces its
400ms arrival lease and fixed8s deadline. These bounds do not promise end-to-end
latency. A `passed` end requires an immediately preceding fresh grounded `PASSED`
sample, rechecked for age at termination. Invalid records leave receiver state unchanged.

Source/build status: trace integration compiled, with126 focused Java ground/trace
checks passing. The Lua follower passed25 standalone cases with simulated engine
bindings. The final receiver passed15 standalone PowerShell cases. Root separately
ran both actual games:22 server frames forwarded,21 delayed KCD player/camera
receipts, guarded restoration verified, and Minecraft exited0 normally. See
[progress](../PROGRESS.md#live-coupled-movement--2026-10-12) for evidence and limits.

The final compound-age and successful-end guards were added after that live run.
The26-record captured trace passes an offline replay using each record's recorded
UTC time; all22 recorded dispatches also meet the stricter age bound, with a maximum
82.9525ms observation age measured at HTTP completion. This is validation of a
historical recording, not a second live run or a packaged-JAR installation test.
