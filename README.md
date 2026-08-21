# Template Application with Supabase Backend

A full-featured application template pre-configured with a robust PostgreSQL database schema for **Supabase**.

---

## 🚀 Quick Start

1. **Setup Supabase Project**:
   Create a new project at [Supabase](https://database.new).

2. **Initialize Database Schema**:
   Apply the SQL database schema located in [`supabase/schema.sql`](./supabase/schema.sql) via the Supabase Dashboard SQL Editor or Supabase CLI.

3. **Documentation**:
   Read the detailed database architecture and setup instructions in [`supabase/README.md`](./supabase/README.md).

---

## 🛠 Database Features

* **Supabase Auth Integration**: Automatic profile creation via database triggers when users sign up.
* **Role-Based Access Control**: Standardized `app_role` ENUM (`admin`, `manager`, `user`).
* **Multi-Tenancy Support**: Organizations/teams and organization membership tables.
* **Subscription Management**: Billing structures for SaaS applications.
* **Notifications & Settings**: Scalable notification logs and key-value app settings.
* **Audit Trail**: Security audit logging.
* **Row Level Security (RLS)**: Fine-grained data access controls enabled on all public tables.

---

## 📁 Repository Structure

```text
.
├── ANALYSIS.md          # Codebase gap analysis
├── README.md            # Root documentation
└── supabase/
    ├── README.md        # Supabase setup guide & architecture details
    └── schema.sql       # Full SQL database schema script
```
