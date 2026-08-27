# Supabase Database Documentation

This directory contains the production-ready PostgreSQL database schema, migrations, and CLI configuration for **Supabase**.

---

## 📐 Architecture & Security Features

The database schema is designed with security, scalability, and integration with Supabase Auth at its core.

### 1. **Tables & Scope Constraints**
* **`public.profiles`**: User profiles linked to `auth.users`. Includes trigger-enforced role escalation protection (`protect_profile_role()`).
* **`public.organizations`**: Organization / team management. Linked to profile owner.
* **`public.organization_members`**: Junction table mapping users to organizations.
* **`public.subscriptions`**: Subscription lifecycle (Stripe integration) enforcing XOR ownership (`user_id` OR `organization_id`).
* **`public.notifications`**: User notification feed with read status and flexible metadata.
* **`public.app_settings`**: Scoped key-value settings store supporting global, user, or organization scope.
* **`public.audit_logs`**: System audit trail using PostgreSQL `INET` column for IP addresses.
* **`public.gap_categories`**: Functional areas / module categories where codebase gaps exist.
* **`public.gap_analysis_reports`**: Sessions and reports summarizing codebase gap audits.
* **`public.missing_items`**: Tracked missing components, bugs, or missing features with severity and status.
* **`public.gap_remediation_steps`**: Actionable remediation steps with step sequence uniqueness and `is_completed`/`completed_at` consistency constraints.

---

## ⚡ Automatic Triggers & SECURITY DEFINER Functions

* **`handle_new_user()`**:
  Triggered automatically `AFTER INSERT ON auth.users`. Creates a matching `public.profiles` record with collision-safe unique username handling and `SET search_path = ''`.

* **`handle_updated_at()`**:
  Triggered `BEFORE UPDATE` on tables with `updated_at` columns using `now()` and `SET search_path = ''`.

* **`is_org_owner()`, `is_org_member()`, `is_admin_or_manager()`**:
  Helper functions executing as `SECURITY DEFINER` with pinned search paths (`SET search_path = ''`) to break circular dependencies in Row Level Security (RLS) policies.

---

## 🔒 Row Level Security (RLS) & Data API Grants

All public tables have Row Level Security enabled:
* Explicit `GRANT` statements are defined for `anon`, `authenticated`, and `service_role`.
* Helper functions revoke `EXECUTE` from `PUBLIC` and `anon` to prevent direct unauthenticated invocation.
* Profiles role column modifications are restricted to `admin` / `manager` roles or `service_role`.
* Organization policies leverage `is_org_owner()` and `is_org_member()` to avoid recursive PostgreSQL query evaluation.

---

## 🚀 How to Apply the Schema

### Option A: Via Supabase CLI (Recommended)
1. Ensure the Supabase CLI is installed:
   ```bash
   npm install -g supabase
   ```
2. Link your local project to Supabase:
   ```bash
   supabase link --project-ref your-project-ref
   ```
3. Run the migration script:
   ```bash
   supabase db push
   ```

### Option B: Via Supabase Dashboard SQL Editor
1. Log in to your [Supabase Dashboard](https://database.new).
2. Select your project and navigate to **SQL Editor**.
3. Copy the entire contents of [`schema.sql`](./schema.sql) into the editor and click **Run**.
