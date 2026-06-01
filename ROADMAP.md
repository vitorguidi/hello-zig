# Zig Learning Roadmap → TigerBeetle-style Raft

Target: a distributed KVS with Raft consensus, deterministic simulation testing, and io_uring networking — built in the TigerBeetle discipline (fixed memory budgets, no dynamic allocation after init, crash-safe storage).

---

## Phase 0 — Zig Fluency

Goal: internalize Zig's memory and type model before touching I/O. Every project here should use **no standard library containers** — build your own.

### Data Structures

- **Singly-linked list** — pointer arithmetic, optional pointers (`?*Node`), `@fieldParentPtr`
- **Intrusive doubly-linked list** — embed the list node inside the payload struct; teaches you the intrusive pattern TigerBeetle uses everywhere
- **Ring buffer (SPSC)** — fixed-size, comptime capacity, power-of-two index masking; no atomics yet, just the layout
- **Dynamic array (ArrayList clone)** — manual `realloc` via allocator interface, amortized growth; understand when *not* to use this (fixed budgets)
- **Open-addressing hash map** — Robin Hood probing or linear probing with tombstones; comptime key/value types
- **B-tree** — internal vs leaf nodes, splitting on insert, merging on delete; this is the storage engine core. Use a fixed node size (e.g. 4096 bytes, one disk page). Make it generic over key/value with a comptime comparator.
- **Skip list** — probabilistic balancing, comptime max levels; useful contrast to B-tree for in-memory indexes
- **Min-heap / priority queue** — needed later for timer wheels in the event loop

### Memory

- **Arena allocator** — bump pointer over a fixed buffer, reset in O(1); implement the `std.mem.Allocator` interface from scratch
- **Pool allocator** — fixed-size slab, free list embedded in the free slots; zero overhead per allocation
- **Stack-based scratch allocator** — save/restore watermark; understand how TigerBeetle avoids heap fragmentation

### Comptime & Type System

- Generic `StaticArray(T, capacity)` — comptime-sized array with runtime length, no heap
- `TypedPool(T, capacity)` — pool allocator specialized to one type via comptime
- Implement a simple tagged union state machine with `std.meta.activeTag` and exhaustive switch — you will use this pattern constantly in Raft

### Error Handling

- Write a function chain where each layer adds to an error set; observe how `anyerror` vs explicit error sets interact
- Build a result type with `!T` that carries a string context — understand `std.fmt` and error return traces

---

## Phase 1 — OS / Filesystem / Networking Primitives

Goal: speak directly to the kernel. Use `std.posix` and `std.linux` — avoid higher-level wrappers so you know what syscalls are actually happening.

### Filesystem & I/O

- **Syscall basics** — open/read/write/close via `std.posix`; understand `O_DIRECT`, `O_SYNC`, `O_DSYNC`
- **`O_DIRECT` aligned I/O** — allocate a buffer aligned to 512 bytes (`std.mem.alignedAlloc`), write/read a fixed file; understand why direct I/O bypasses page cache and when you want that
- **`mmap`** — map a file, modify it, `msync`; compare throughput vs `read`/`write`
- **`fsync` vs `fdatasync`** — write a WAL entry, flush, understand the crash safety guarantee each gives
- **`sendfile`** — zero-copy file-to-socket transfer; will be used in the proxy
- **`writev` / `readv`** — scatter-gather I/O; understand iovec; used heavily with io_uring

### io_uring

- **Submission/completion rings** — open `io_uring` manually via `std.linux.io_uring_setup`; submit a `IORING_OP_READ`, harvest the completion
- **Fixed buffers** — register buffers with `IORING_REGISTER_BUFFERS`; understand why this avoids per-op mapping overhead
- **Linked requests** — chain a write + fsync as an atomic pair with `IOSQE_IO_LINK`
- **Multi-shot accept** — `IORING_OP_ACCEPT` with `IORING_ACCEPT_MULTISHOT`; accept many connections without re-submitting
- **Event loop skeleton** — single-threaded loop: submit batch → wait for completions → dispatch; this is the exact pattern TigerBeetle uses

### Networking

- **TCP echo server** — `socket` → `bind` → `listen` → `accept` → `recv`/`send` loop; blocking first
- **Non-blocking sockets** — `O_NONBLOCK` + `poll`/`epoll`; understand edge vs level triggering
- **Rewrite echo server with io_uring** — replace epoll with completion-based I/O; compare code structure
- **UDP** — send/receive datagrams; understand why Raft implementations sometimes use UDP for heartbeats
- **Unix domain sockets** — local IPC; you will use these in the simulator to fake the network

### Processes & Signals

- **`fork` + `exec`** — launch a subprocess, capture stdout via a pipe
- **Signal handling** — `SIGPIPE`, `SIGTERM`; understand why you must handle `SIGPIPE` in any server
- **`timerfd`** — kernel timer as a file descriptor; integrate with io_uring for tick-based heartbeats

---

## Phase 2 — Reverse Proxy

Build an HTTP/1.1 reverse proxy. This is the integration test for Phases 0–1.

**Constraints (enforce TigerBeetle discipline):**
- All memory pre-allocated at startup — no allocations in the hot path
- Fixed connection limit (e.g. 1024 clients + 1024 upstreams)
- Single-threaded io_uring event loop

**Steps:**

1. **HTTP/1.1 request parser** — hand-rolled, streaming, handles partial reads; output is a parsed `Request` struct pointing into the receive buffer (zero-copy)
2. **Upstream connection pool** — fixed array of upstream slots; idle/in-use state machine per slot
3. **Proxy loop** — accept client → parse request → acquire upstream slot → forward → stream response back → release slot
4. **Backpressure** — stop accepting new clients when all upstream slots are busy
5. **Health checking** — periodic `HEAD /health` to each upstream; remove unhealthy upstreams from rotation
6. **Observability** — counters for active connections, requests/sec, upstream latency; no dynamic strings, just `u64` fields

---

## Phase 3 — Snapshot Isolation KVS

Build the storage layer Raft will replicate. Crash-safe, MVCC, `O_DIRECT`.

**Steps:**

1. **WAL (Write-Ahead Log)**
   - Fixed-size log file, pre-allocated on disk (`fallocate`)
   - Each entry: `| checksum (16B) | length (4B) | payload |`
   - Checksums with xxHash or CRC32C
   - Recovery: scan from last known good offset, validate checksums, discard tail
   - Flush policy: `fdatasync` after each batch of entries

2. **Memtable**
   - Your B-tree from Phase 0, in-memory
   - Keyed by `(user_key, timestamp)` — the MVCC version
   - Supports point lookup at a given snapshot timestamp

3. **MVCC semantics**
   - Each write appends `(key, timestamp, value)` to the WAL then inserts into the memtable
   - Read at snapshot `T`: find the latest version of `key` with `timestamp <= T`
   - Snapshot = monotonic `u64` counter; bump on each transaction commit

4. **Compaction**
   - Periodically remove versions older than the oldest active snapshot
   - Single-threaded, runs between request batches

5. **API**
   - `begin() → SnapshotId`
   - `get(snapshot, key) → ?[]const u8`
   - `put(key, value) → void` (auto-assigned timestamp on commit)
   - `commit() → void` (WAL flush)
   - `abort() → void`

---

## Phase 4 — Raft (TigerBeetle Style)

Build Raft in three separable layers so each can be tested independently.

### Layer 1: Pure State Machine

Implement Raft as a **pure function** — no I/O, no threads, no time.

```
fn tick(state: *RaftState, messages: []const Message) []const Effect
```

`Effect` is a tagged union: `SendMessage`, `AppendLog`, `CommitEntry`, `BecomeLeader`, etc.

Test this exhaustively with unit tests before wiring anything real.

### Layer 2: Deterministic Simulator (VOPR style)

This is the TigerBeetle key insight. Before real networking, build a simulator:

- **Fake clock** — `u64` tick counter; inject via parameter, never `std.time`
- **Fake network** — message queue per node pair; support drop, delay, reorder, duplicate via configurable fault injection
- **Fake disk** — in-memory WAL that can be set to fail or corrupt on demand
- **Crash/restart** — zero out a node's state, replay its log from disk
- **Seed-based reproducibility** — all randomness flows from one `u64` seed; a failing test prints the seed, re-running with that seed reproduces the failure

Run millions of simulated ticks. Check invariants after every tick:
- At most one leader per term
- Committed entries never change
- Log matching property

### Layer 3: Real I/O

Wire the state machine to real networking and storage:

- **Transport** — io_uring TCP between nodes; serialize `Message` with a simple fixed header + payload
- **Persistent log** — your WAL from Phase 3
- **Timer** — `timerfd` integrated into the io_uring loop for election/heartbeat timeouts
- **State machine application** — committed log entries drive mutations on the KVS

### Raft Features to Implement (in order)

1. Leader election (RequestVote, randomized timeouts)
2. Log replication (AppendEntries, match/next index per follower)
3. Commit + apply (majority quorum, last applied index)
4. Log compaction (snapshots, InstallSnapshot RPC)
5. Cluster membership changes (joint consensus or single-server changes)

---

## Phase 5 — HFT Stack

Shift from correctness to latency. Everything here is about removing overhead.

### DPDK (Kernel Bypass)

- Set up DPDK with a test NIC (or `vdev` for development)
- Zig → C interop via `@cImport` for DPDK headers
- Implement a packet receive loop: `rte_eth_rx_burst` → process → `rte_eth_tx_burst`
- Fix CPU affinity: one lcore per RX queue (`rte_eal_remote_launch`)
- Measure: compare `recv`-based throughput vs DPDK on the same hardware

### Lock-Free Data Structures

- **SPSC queue** — single producer, single consumer; uses `std.atomic.Value` for head/tail; cache-line padded to avoid false sharing (`align(64)`)
- **MPSC queue** — multi-producer, single consumer; Michael-Scott queue or Dmitry Vyukov's intrusive variant
- **Seqlock** — for publishing a frequently-read value (e.g. best bid/ask) without blocking readers

### Cache-Aware Design

- Align hot structs to cache lines: `const Order = extern struct { ... } align(64)`
- Separate hot and cold fields into different structs (struct splitting)
- Measure false sharing with `perf c2c` before and after fixes
- Understand prefetching: `@prefetch` in Zig, `__builtin_prefetch` via C interop

### Memory

- **Huge pages** — `mmap` with `MAP_HUGETLB`; eliminates TLB misses on large buffers
- **NUMA awareness** — `mbind` / `set_mempolicy`; allocate memory on the same NUMA node as the CPU running the thread
- **`memfd_create`** — anonymous file-backed memory; useful for shared buffers between processes

### Application Layer

- **Order book** — price-level map (your B-tree), FIFO queue per level; process `Add`/`Cancel`/`Fill` messages from a SPSC queue fed by the DPDK RX loop
- **FIX parser** — tag=value format; zero-copy, no heap; benchmark against the DPDK receive rate

---

## Reading List (by phase)

| Phase | Read |
|-------|------|
| 0 | Zig language reference — comptime, allocators, error handling sections |
| 1 | `io_uring` by example (Lord's articles); Linux `man 2` pages for every syscall you use |
| 2 | HTTP/1.1 RFC 9112 (just the request-line and headers grammar) |
| 3 | "Designing Data-Intensive Applications" ch. 3 (storage engines) and ch. 7 (transactions) |
| 4 | Ongaro & Ousterhout 2014 ("In Search of an Understandable Consensus Algorithm"); TigerBeetle DESIGN.md and VOPR blog post |
| 5 | "Low Latency C++" (Vladislav Shpilevoy talks); DPDK Programmer's Guide; "What Every Programmer Should Know About Memory" (Drepper) |
