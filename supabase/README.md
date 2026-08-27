# Supabase Database Documentation

This directory contains the production-ready PostgreSQL database schema and configuration for **Supabase**.

---

## 📐 Architecture Overview

The database schema is designed with security, scalability, and integration with Supabase Auth at its core.

### 1. **Tables & Relationships**
* **`public.profiles`**: Stores user profile information. Automatically synced with `auth.users` upon signup. Protected against role escalation.
* **`public.organizations`**: Organization / team / workspace management. Automatically provisions owner admin membership upon creation.
* **`public.organization_members`**: Junction table mapping users to organizations with role assignments.
* **`public.subscriptions`**: Subscription lifecycle management for individual users or organizations.
* **`public.notifications`**: User notification feed with read status and flexible metadata.
* **`public.app_settings`**: Key-value settings store supporting public, user-scoped, or org-scoped settings.
* **`public.audit_logs`**: System activity audit trail using `INET` for IP addresses.
* **`public.gap_categories`**: Functional areas / module categories where codebase gaps exist.
* **`public.gap_analysis_reports`**: Sessions and reports summarizing codebase gap audits.
* **`public.missing_items`**: Tracked missing components, bugs, or missing features with severity (`low`, `medium`, `high`, `critical`) and status.
* **`public.gap_remediation_steps`**: Actionable tasks and remediation steps linked to missing items.

---

## ⚡ Automatic Triggers & Functions

* **`handle_new_user()`**:
  Triggered automatically `AFTER INSERT ON auth.users`. Creates a matching `public.profiles` record with metadata, search path safety, and collision-safe unique username handling.

* **`handle_new_organization()`**:
  Triggered automatically `AFTER INSERT ON public.organizations`. Automatically inserts the workspace creator into `public.organization_members` as an `admin`.

* **`handle_updated_at()`**:
  Triggered `BEFORE UPDATE` on tables with `updated_at` columns (`profiles`, `organizations`, `subscriptions`, `app_settings`, `gap_analysis_reports`, `missing_items`) to maintain accurate UTC timestamps.

* **Private Security Helpers (`private.*`)**:
  - `private.is_org_member(org_id, user_id)`: Prevents circular RLS recursion when reading membership.
  - `private.is_org_owner(org_id, user_id)`: Prevents circular RLS recursion when reading ownership.
  - `private.get_user_role(user_id)`: Safely checks profile role without exposing execution to public API roles.

---

## 🔒 Row Level Security (RLS) Policies & Grants

All public tables have Row Level Security enabled and explicit least-privilege `GRANT` statements applied:
* Users can view authenticated profiles and update only non-role fields of their own profile.
* Organization data is restricted to team members and owners without circular recursion.
* Subscriptions are viewable by authorized user/org account holders.
* Audit logs and notifications are strictly scoped to the target user or admins.
* Gap analysis reports and missing items are viewable by authenticated users and editable by assigned users or admins.

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
2. Select your project and navigate to **SQL Editor** in the side navigation.
3. Click **New Query**.
4. Copy the entire contents of [`schema.sql`](./schema.sql) into the query editor.
5. Click **Run** (or `Ctrl` / `Cmd` + `Enter`) to execute the script.
