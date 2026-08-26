# Unified Database and Backend Gap Audit

## Executive summary

The repository now contains a documented Supabase schema, but it is not yet safe to describe as production-ready. The most urgent problems are authorization defects in the profile and organization policies, followed by an incomplete deployment layout and missing verification. No application backend, generated client types, automated tests, or CI workflow are present, so backend integration cannot currently be validated end to end.

This audit is based on commit `3b83fc758920c92d0d85fe747fdcbae287f6230b` and a static review of `supabase/schema.sql`, `README.md`, and `supabase/README.md`. A live database was not available, so every database finding must be confirmed with a local Supabase reset and role-based policy tests before deployment.

## Release recommendation

**Do not deploy the schema to production in its current form.** Resolve the P0 authorization issues, convert the schema into a reproducible migration, and add policy tests first.

## Findings

### P0 — Users can grant themselves privileged roles

`profiles.role` defaults to `user`, but authenticated users may insert and update their own entire profile row. The RLS checks only ownership of `id`; they do not prevent a client from supplying or changing `role` to `admin` or `manager`. Other policies trust that column for privileged access, including access to all audit logs and updates to gap items.

Evidence:

- `supabase/schema.sql:48-58` defines the client-visible `role` column.
- `supabase/schema.sql:314-323` permits self-insert and self-update without protecting `role`.
- `supabase/schema.sql:411-426` and `supabase/schema.sql:444-448` use `profiles.role` as authorization data.

Required remediation:

1. Remove client write privileges from authorization columns. Grant updates only to an explicit list of safe profile columns, or move roles into a private membership/authorization table managed only by trusted server code.
2. Prevent client profile insertion if the auth trigger owns profile creation.
3. Add negative tests proving an authenticated user cannot create or update an `admin`/`manager` role.

### P0 — Organization RLS policies form a circular dependency

The organization SELECT policy queries `organization_members`, while the membership SELECT and management policies query `organizations`. PostgreSQL evaluates RLS on those nested table reads, so these policies can recurse and fail with an infinite-recursion error. Subscription access also traverses the membership policy and inherits the same risk.

Evidence:

- `supabase/schema.sql:325-335` reads memberships from the organizations policy.
- `supabase/schema.sql:353-373` reads organizations from membership policies.
- `supabase/schema.sql:375-385` reads memberships from the subscriptions policy.

Required remediation:

1. Move membership/ownership checks into narrowly scoped helper functions in a non-exposed schema.
2. If a helper must be `SECURITY DEFINER`, set `search_path = ''`, schema-qualify every object, validate `(select auth.uid())` inside the function, and revoke direct execution from API roles.
3. Test owner, member, non-member, anonymous, and service-role behavior for every operation.

### P0 — The checked-in schema is not deployable with the documented CLI command

The README directs users to run `supabase db push`, but the repository has only `supabase/schema.sql`. `db push` applies pending files from `supabase/migrations`; it does not apply this standalone file. There is also no `supabase/config.toml`, migration history, seed, or reset-based verification path.

Evidence:

- `README.md` and `supabase/README.md` describe `supabase db push` as the installation command.
- The repository contains no `supabase/migrations/` directory.

Required remediation:

1. Initialize the Supabase project layout.
2. Generate a timestamped initial migration with `supabase migration new` and place the reviewed SQL there.
3. Verify from an empty database with `supabase db reset`, then preview remote deployment with `supabase db push --dry-run`.

### P1 — Privileged functions are exposed and do not pin `search_path`

Both trigger functions are declared `SECURITY DEFINER` in the exposed `public` schema. `handle_updated_at` does not need elevated privileges. `handle_new_user` may require them because it is invoked from `auth.users`, but it does not pin `search_path` or explicitly restrict execution.

Evidence:

- `supabase/schema.sql:209-216` defines `public.handle_updated_at()` as `SECURITY DEFINER`.
- `supabase/schema.sql:249-282` defines `public.handle_new_user()` as `SECURITY DEFINER` without `SET search_path = ''`.

Required remediation:

1. Make `handle_updated_at` a normal invoker function.
2. Put privileged helpers in a private schema, pin an empty search path, schema-qualify all names, and revoke `EXECUTE` from `PUBLIC`, `anon`, and `authenticated`.
3. Add a migration test proving signup succeeds while direct API invocation is denied.

### P1 — Concurrent signups can fail during username generation

The signup trigger checks whether a username exists and then inserts it. Two signups choosing the same username can both pass the check before either insert commits; one then violates the unique constraint and may abort user creation. The short UUID suffix is only added when the earlier row is already visible.

Evidence: `supabase/schema.sql:256-279`.

Required remediation: generate a collision-resistant username without a check-then-insert race, or catch `unique_violation` and retry with a deterministic suffix. Add a concurrent-signup regression test.

### P1 — Data API privileges are implicit and environment-dependent

RLS policies are present, but the migration does not explicitly grant or revoke table operations for `anon` and `authenticated`. Current Supabase projects may not expose new public tables automatically. Consequently, the same schema can be inaccessible in one project and over-privileged in another depending on project defaults.

Required remediation: define least-privilege grants per table and operation in the migration. Keep internal tables ungranted, and test grants separately from RLS policies.

### P1 — Ownership constraints allow ambiguous records

- `subscriptions` accepts both `user_id` and `organization_id`; its check requires only one or more, not exactly one.
- `app_settings` accepts neither or both owners and has no uniqueness constraint for a key within a user or organization scope.
- `gap_remediation_steps` does not enforce uniqueness of `(missing_item_id, step_number)` or consistency between `is_completed` and `completed_at`.

Evidence: `supabase/schema.sql:82-97`, `112-122`, and `170-179`.

Required remediation: add explicit XOR/check constraints and scoped unique constraints that match the intended domain model.

### P1 — Several foreign-key and policy columns lack supporting indexes

Missing leading indexes include:

- `app_settings.user_id`, `app_settings.organization_id`
- `gap_analysis_reports.created_by`
- `missing_items.category_id`, `missing_items.assigned_to`

These columns are used by foreign keys, filters, or authorization paths and will require table scans as data grows. Conversely, indexes on `profiles.username` and `organizations.slug` duplicate indexes already created by unique constraints, and `idx_org_members_org_id` duplicates the leading column of `UNIQUE (organization_id, user_id)`.

### P2 — Timestamp and network types should be tightened

- `timezone('utc', now())` produces a timestamp without time zone before assignment back to `timestamptz`; use `now()` directly for an absolute timestamp.
- `audit_logs.ip_address` should use PostgreSQL `inet` rather than unrestricted text.

Evidence: timestamp defaults throughout `supabase/schema.sql` and `ip_address` at line 132.

### P2 — Audit data is client-forgeable

Any authenticated user can insert an audit entry for their own `user_id` while controlling `action`, `entity`, `entity_id`, `details`, and `ip_address`. If this table is intended as a trustworthy security trail, writes must come from trusted server/database code and client INSERT should be revoked.

Evidence: `supabase/schema.sql:124-134` and `423-426`.

### P2 — The schema script is only partially rerunnable

Tables, types, indexes, and triggers use conditional creation or replacement patterns, but policies are created unconditionally. A second execution fails when the first existing policy is reached. This conflicts with the script's all-in-one setup positioning and makes partial recovery unreliable.

Required remediation: prefer an immutable migration that runs exactly once. If a declarative rerunnable script is retained, explicitly drop/recreate policies or guard their creation consistently.

### P2 — The previous analysis is stale

`ANALYSIS.md` says the repository contains only `.git` and lacks a README, source, and configuration. The repository now contains a schema and documentation, so that report is no longer an accurate description of the current tree.

Required remediation: replace it with, or clearly mark it as, a historical snapshot.

## Missing backend integration

The repository has no application code, API layer, environment contract, generated database types, tests, or CI. The schema therefore has no demonstrated consumers and no automated validation of:

- signup/profile trigger behavior;
- anonymous, authenticated, owner, member, manager, and admin access;
- organization membership lifecycle;
- subscription ownership rules;
- notification read/update flows;
- gap-report creation and remediation workflows;
- expected Data API grants; or
- migration replay from a clean database.

## Recommended implementation sequence

1. Fix profile-role escalation and circular organization policies.
2. Convert the schema to a timestamped migration and add explicit grants.
3. Harden functions and make signup username creation concurrency-safe.
4. Add ownership constraints and missing indexes; remove redundant indexes.
5. Add SQL policy tests for every role and CRUD operation.
6. Add CI that starts the local Supabase stack, runs `supabase db reset`, executes tests and advisors, and fails on schema drift.
7. Add application code and generated client types only after the database contract is reproducible.

## Acceptance criteria for production readiness

- A clean `supabase db reset` succeeds from the committed migration chain.
- Role-escalation and cross-tenant access tests fail closed.
- Auth signup succeeds under duplicate and concurrent username scenarios.
- Every exposed table has explicit grants and operation-specific RLS policies.
- Privileged functions are outside exposed schemas, have a pinned search path, and have restricted execution.
- Foreign keys and RLS filter columns have appropriate leading indexes.
- Supabase security and performance advisors report no unresolved findings accepted for release.
- CI runs the migration and policy test suite on every pull request.
