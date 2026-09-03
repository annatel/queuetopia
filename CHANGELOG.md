# Changelog

## 6.0.0 - Unreleased

- New `queuetopia_pending_queues` table (migration V8): one row per queue with pending work, whose `next_performable_at` encodes both a head job scheduled later and a post-failure backoff. The migration backfills it from the existing jobs backlog.
- The table is maintained transactionally at every job transition: `create_job` upserts the row in the same transaction as the job insert (keeping the earliest performable time), and job completion recomputes it from the queue's head job — next job's `scheduled_at` on success, the backed-off `next_attempt_at` on failure, row deleted when the queue empties. A missing row self-heals on recompute.
- The scheduler polls this table instead of running a `DISTINCT` scan over the whole jobs backlog — poll cost is now proportional to the number of pending queues, not to the backlog size. A stale row (e.g. an optimistic `next_performable_at`) is refreshed on the spot and drops out of subsequent polls.
- The pending row doubles as the queue's internal mutex: refreshes take it with `SELECT ... FOR UPDATE`, so a concurrent `create_job` can no longer race the delete/recompute of the same queue's row — the delete/create races are closed.
- Claiming the next performable job happens in a single transaction (head lookup, queue lock and post-lock recheck in one Multi), removing the window between choosing a job and claiming it; empty or not-yet-performable queues short-circuit before taking a lock.
- **Breaking:** a test seeding a bare job row must also seed the queue's pending row — the scheduler only polls the `queuetopia_pending_queues` table. `Queuetopia.Factories.build(:pending_queue, attrs)` provides the struct.
- **Breaking:** Postgres support is removed — Queuetopia targets MySQL only. The `postgrex` dependency, the per-adapter migration branches and the Postgres upsert options are gone.
- **Breaking:** `Queuetopia.Queue` is split into `Queuetopia.Jobs` (creation, claim, perform, results, cleanup), `Queuetopia.PendingQueues` (row maintenance and the poll listing) and `Queuetopia.Locks` (take, release, expire). `Queuetopia.Queue.Job` becomes `Queuetopia.Jobs.Job`; update any code referencing the old modules.
- **Breaking:** several formerly public job predicates (`done?`, `max_attempts_reached?`, the time check) are folded into `performable_now?` or made private; the `Queue` API is narrowed to the claim/get-next surface.
- Dependencies: `ecto`/`ecto_sql` 3.14, `myxql` 0.9 and `decimal` 3.1 — `decimal` < 3.0 is affected by CVE-2026-32686 (unbounded exponent in `Decimal.new`, DoS). Consumers must be able to take `decimal` 3.

## 5.0.0 - 2026-09-01

- **Breaking:** job creation is now always silent — `create_job` never wakes the scheduler, and the `notify?:` option (added in 3.0.0) is gone.
- **Breaking:** `handle_event/1` and `listen/1` are replaced by `notify_scheduler/0`. Waking the scheduler is now a deliberate post-commit act of the producer; a forgotten notification is covered by the periodic poll.

## 4.0.0 - 2026-08-31

- **Breaking:** the `scheduler_repo` option (added in 3.0.0) is replaced by an opt-in dedicated scheduler pool: `dedicated_scheduler_pool?: true` in the Queuetopia config (default off) makes the scheduler and the job cleaner query through a second instance of the Queuetopia's repo — same config and adapter, shared by every Queuetopia on that repo. The pool size comes from the `QUEUETOPIA_SCHEDULER_POOL_SIZE` environment variable; enabling the pool without it raises at startup.

## 3.0.0 - 2026-08-31

- **Breaking:** the performer module is now resolved by convention as `<scope>.Performer` at execution time; the `performer` option and the jobs-table column are removed (migration V7 drops the column). Remote producers no longer need to know the executor's performer module.
- `create_job` accepts `notify?: false`, letting callers insert jobs in bulk without waking the scheduler on each insert — a single notification at the end of the batch wakes it once.
- New `scheduler_repo` option: the Scheduler and JobCleaner can run their queries (poll, queue locking, job results, cleanup) through a dedicated repo, so their liveness does not depend on the business pool, and vice versa.
