# Supabase Database Documentation

This directory contains the production-ready PostgreSQL database schema and configuration for **Supabase**.

---

## 📐 Architecture Overview

The database schema is designed with security, scalability, and integration with Supabase Auth at its core.

### 1. **Tables & Relationships**
* **`public.profiles`**: Stores user profile information. Automatically synced with `auth.users` upon signup.
* **`public.organizations`**: Organization / team management. Linked to a profile owner.
* **`public.organization_members`**: Junction table mapping users to organizations with role assignments.
* **`public.subscriptions`**: Subscription lifecycle management (e.g., Stripe integration) for individual users or organizations.
* **`public.notifications`**: User notification feed with read status and flexible metadata.
* **`public.app_settings`**: Key-value settings store supporting both public and user/org specific settings.
* **`public.audit_logs`**: System activity audit trail.
* **`public.gap_categories`**: Functional areas / module categories where codebase gaps exist.
* **`public.gap_analysis_reports`**: Sessions and reports summarizing codebase gap audits.
* **`public.missing_items`**: Tracked missing components, bugs, or missing features with severity (`low`, `medium`, `high`, `critical`) and status.
* **`public.gap_remediation_steps`**: Actionable tasks and remediation steps linked to missing items.

---

## ⚡ Automatic Triggers & Functions

* **`handle_new_user()`**:
  Triggered automatically `AFTER INSERT ON auth.users`. Creates a matching `public.profiles` record with metadata and collision-safe unique username handling.

* **`handle_updated_at()`**:
  Triggered `BEFORE UPDATE` on tables with `updated_at` columns (`profiles`, `organizations`, `subscriptions`, `app_settings`, `gap_analysis_reports`, `missing_items`) to maintain accurate UTC timestamps.

---

## 🔒 Row Level Security (RLS) Policies

All public tables have Row Level Security enabled. Policies ensure:
* Users can only modify their own profile data.
* Organization data is restricted to team members and owners.
* Subscriptions are viewable only by authorized account holders.
* Audit logs and notifications are strictly scoped to the target user.
* Gap analysis reports and missing items are viewable by authenticated users and editable by assigned users or admins.

---

## 🚀 How to Apply the Schema

### Option A: Via Supabase Dashboard SQL Editor (Recommended)
1. Log in to your [Supabase Dashboard](https://database.new).
2. Select your project and navigate to **SQL Editor** in the side navigation.
3. Click **New Query**.
4. Copy the entire contents of [`schema.sql`](./schema.sql) into the query editor.
5. Click **Run** (or `Ctrl` / `Cmd` + `Enter`) to execute the script.

### Option B: Via Supabase CLI
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
