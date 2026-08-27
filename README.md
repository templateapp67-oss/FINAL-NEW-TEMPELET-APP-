# Template Application with Supabase Backend

A full-featured application template pre-configured with a robust PostgreSQL database schema and CLI migrations for **Supabase**.

---

## 🚀 Quick Start

1. **Setup Supabase Project**:
   Create a new project at [Supabase](https://database.new) or initialize locally using Supabase CLI.

2. **Initialize Database via Migration or SQL**:
   - **CLI Migration (Recommended)**:
     ```bash
     supabase db push
     ```
   - **Manual Execution**:
     Apply [`supabase/schema.sql`](./supabase/schema.sql) via the Supabase Dashboard SQL Editor.

3. **Documentation**:
   Read the detailed database architecture, security policies, and setup instructions in [`supabase/README.md`](./supabase/README.md).

4. **Audit & Remediation Status**:
   Review [`UNIFIED_AUDIT.md`](./UNIFIED_AUDIT.md) for details on resolved P0/P1/P2 security & schema findings.

---

## 🛠 Database Features

* **Supabase Auth Integration**: Automatic profile creation via database triggers when users sign up, with race-condition-safe username generation.
* **Role-Based Access Control & Role Escalation Protection**: Standardized `app_role` ENUM (`admin`, `manager`, `user`) with trigger checks preventing unauthorized role escalation.
* **Multi-Tenancy Support**: Organizations/teams and organization membership tables using non-recursive helper functions to prevent RLS circular dependencies.
* **Subscription Management**: Flexible SaaS billing structures (User or Org XOR scoped).
* **Notifications & Settings**: Scalable notification logs and key-value app settings with scoped unique constraints.
* **Audit Trail**: Security audit logging using `INET` client IP addresses.
* **Gap Analysis & Remediation Tracking**: Track codebase gaps, missing items, severity, and remediation steps with completion consistency constraints.
* **Row Level Security (RLS) & Explicit Grants**: Fine-grained data access controls and explicit role grants (`anon`, `authenticated`, `service_role`).

---

## 📁 Repository Structure

```text
.
├── ANALYSIS.md          # Codebase gap analysis & remediation history
├── README.md            # Root documentation
├── UNIFIED_AUDIT.md     # Unified security and architecture audit status
└── supabase/
    ├── README.md        # Supabase setup guide & architecture details
    ├── config.toml      # Supabase CLI project configuration
    ├── schema.sql       # Full production database schema script
    └── migrations/
        └── 20260101000000_initial_schema.sql  # Initial reproducible migration
```
