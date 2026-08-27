# Template Application with Supabase Backend

A full-featured application template pre-configured with a robust, production-ready PostgreSQL database schema for **Supabase**.

---

## 🚀 Quick Start

1. **Setup Supabase Project**:
   Create a new project at [Supabase](https://database.new).

2. **Initialize Database Schema via Supabase CLI (Recommended)**:
   ```bash
   supabase link --project-ref your-project-ref
   supabase db push
   ```

3. **Alternative: Via Supabase Dashboard SQL Editor**:
   Copy and execute [`supabase/schema.sql`](./supabase/schema.sql) in the Supabase Dashboard SQL Editor.

4. **Documentation & Audit**:
   - Read detailed architecture guidelines in [`supabase/README.md`](./supabase/README.md).
   - Review audit resolution status in [`UNIFIED_AUDIT.md`](./UNIFIED_AUDIT.md).
   - Review codebase gap analysis in [`ANALYSIS.md`](./ANALYSIS.md).

---

## 🛠 Database Features

* **Supabase Auth Integration**: Automatic profile creation via database triggers when users sign up.
* **Automatic Workspace Provisioning**: Automatic admin membership creation when a user creates an organization/workspace.
* **Role-Based Access Control**: Standardized `app_role` ENUM (`admin`, `manager`, `user`) with role-escalation protection.
* **Multi-Tenancy Support**: Organizations/teams and organization membership tables with recursion-free security helper functions.
* **Subscription Management**: Billing structures for SaaS applications supporting user or organization scopes.
* **Notifications & Settings**: Scalable notification logs and key-value app settings.
* **Audit Trail**: Security audit logging using Postgres `INET` network types.
* **Gap Analysis & Remediation Tracking**: Track codebase gaps, missing items, severity, and remediation steps.
* **Row Level Security (RLS)**: Fine-grained, idempotent data access controls enabled on all public tables with least-privilege table grants.

---

## 📁 Repository Structure

```text
.
├── ANALYSIS.md          # Codebase gap analysis & remediation report
├── README.md            # Root documentation
├── UNIFIED_AUDIT.md     # Security audit & remediation report
└── supabase/
    ├── README.md        # Supabase setup guide & architecture details
    ├── config.toml      # Supabase project configuration
    ├── schema.sql       # Full production-ready SQL database schema script
    └── migrations/
        └── 20240329000000_initial_schema.sql  # Timestamped initial schema migration
```
