-- ====================================================================
-- SUPABASE COMPLETE DATABASE SCHEMA (PRODUCTION-READY)
-- ====================================================================
-- Description: Complete production-ready database schema for Supabase
-- Includes: Extensions, Enums, Tables, Foreign Keys, Triggers, Security Helpers,
--          Idempotent RLS Policies, Indexes, and Explicit Grants.
-- Modules: Core Auth Profiles, Organizations, Subscriptions, Notifications,
--          App Settings, Audit Logs, and Gap Analysis / Missing Items Tracking.
-- ====================================================================

-- --------------------------------------------------------------------
-- 1. EXTENSIONS
-- --------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- --------------------------------------------------------------------
-- 2. PRIVATE SECURITY HELPER SCHEMA & FUNCTIONS
-- --------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

-- --------------------------------------------------------------------
-- 3. CUSTOM TYPES & ENUMS
-- --------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE public.app_role AS ENUM ('admin', 'manager', 'user');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE public.subscription_status AS ENUM ('active', 'trialing', 'past_due', 'canceled', 'unpaid');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE public.subscription_tier AS ENUM ('free', 'pro', 'enterprise');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE public.notification_type AS ENUM ('info', 'warning', 'success', 'error');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE public.gap_severity AS ENUM ('low', 'medium', 'high', 'critical');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE public.gap_status AS ENUM ('identified', 'in_review', 'in_progress', 'resolved', 'ignored');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- --------------------------------------------------------------------
-- 4. TABLES & CONSTRAINTS
-- --------------------------------------------------------------------

-- PROFILES (Links directly with Supabase Auth users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE,
    full_name TEXT,
    avatar_url TEXT,
    website TEXT,
    role public.app_role DEFAULT 'user'::public.app_role NOT NULL,
    bio TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ORGANIZATIONS / TEAMS
CREATE TABLE IF NOT EXISTS public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    owner_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    logo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ORGANIZATION MEMBERS
CREATE TABLE IF NOT EXISTS public.organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    role public.app_role DEFAULT 'user'::public.app_role NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(organization_id, user_id)
);

-- SUBSCRIPTIONS
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    status public.subscription_status DEFAULT 'active'::public.subscription_status NOT NULL,
    tier public.subscription_tier DEFAULT 'free'::public.subscription_tier NOT NULL,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    cancel_at_period_end BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT sub_owner_exact_one_check CHECK (
        (user_id IS NOT NULL AND organization_id IS NULL) OR
        (user_id IS NULL AND organization_id IS NOT NULL)
    )
);

-- NOTIFICATIONS
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type public.notification_type DEFAULT 'info'::public.notification_type NOT NULL,
    is_read BOOLEAN DEFAULT false NOT NULL,
    link TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- APP SETTINGS
CREATE TABLE IF NOT EXISTS public.app_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value JSONB NOT NULL,
    is_public BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT settings_owner_exact_one_check CHECK (
        (user_id IS NOT NULL AND organization_id IS NULL) OR
        (user_id IS NULL AND organization_id IS NOT NULL) OR
        (user_id IS NULL AND organization_id IS NULL AND is_public = true)
    )
);

-- Unique setting key constraint scoped to user or organization or global public
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_settings_global_key ON public.app_settings(key) WHERE user_id IS NULL AND organization_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_settings_user_key ON public.app_settings(user_id, key) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_settings_org_key ON public.app_settings(organization_id, key) WHERE organization_id IS NOT NULL;

-- AUDIT LOGS
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity TEXT NOT NULL,
    entity_id UUID,
    details JSONB DEFAULT '{}'::jsonb,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- GAP CATEGORIES (Modules/Features area where gaps exist)
CREATE TABLE IF NOT EXISTS public.gap_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- GAP ANALYSIS REPORTS
CREATE TABLE IF NOT EXISTS public.gap_analysis_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    summary TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- MISSING ITEMS / GAPS
CREATE TABLE IF NOT EXISTS public.missing_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID REFERENCES public.gap_analysis_reports(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.gap_categories(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    severity public.gap_severity DEFAULT 'medium'::public.gap_severity NOT NULL,
    status public.gap_status DEFAULT 'identified'::public.gap_status NOT NULL,
    affected_component TEXT,
    recommended_fix TEXT,
    assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- GAP REMEDIATION STEPS
CREATE TABLE IF NOT EXISTS public.gap_remediation_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    missing_item_id UUID REFERENCES public.missing_items(id) ON DELETE CASCADE NOT NULL,
    step_number INT NOT NULL,
    task_description TEXT NOT NULL,
    is_completed BOOLEAN DEFAULT false NOT NULL,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT step_number_positive CHECK (step_number > 0),
    CONSTRAINT remediation_step_completion_check CHECK (
        (is_completed = false AND completed_at IS NULL) OR
        (is_completed = true AND completed_at IS NOT NULL)
    ),
    UNIQUE(missing_item_id, step_number)
);

-- --------------------------------------------------------------------
-- 5. INDEXES
-- --------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);

CREATE INDEX IF NOT EXISTS idx_organizations_owner_id ON public.organizations(owner_id);

CREATE INDEX IF NOT EXISTS idx_org_members_user_id ON public.organization_members(user_id);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_org_id ON public.subscriptions(organization_id);

CREATE INDEX IF NOT EXISTS idx_app_settings_user_id ON public.app_settings(user_id);
CREATE INDEX IF NOT EXISTS idx_app_settings_org_id ON public.app_settings(organization_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id_read ON public.notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);

CREATE INDEX IF NOT EXISTS idx_gap_reports_created_by ON public.gap_analysis_reports(created_by);
CREATE INDEX IF NOT EXISTS idx_missing_items_report_id ON public.missing_items(report_id);
CREATE INDEX IF NOT EXISTS idx_missing_items_category_id ON public.missing_items(category_id);
CREATE INDEX IF NOT EXISTS idx_missing_items_assigned_to ON public.missing_items(assigned_to);
CREATE INDEX IF NOT EXISTS idx_missing_items_status ON public.missing_items(status);
CREATE INDEX IF NOT EXISTS idx_missing_items_severity ON public.missing_items(severity);
CREATE INDEX IF NOT EXISTS idx_remediation_steps_item_id ON public.gap_remediation_steps(missing_item_id);

-- Clean up obsolete / redundant indexes if present from earlier schema versions
DROP INDEX IF EXISTS public.idx_profiles_username;
DROP INDEX IF EXISTS public.idx_organizations_slug;
DROP INDEX IF EXISTS public.idx_org_members_org_id;

-- --------------------------------------------------------------------
-- 6. PRIVATE SECURITY DEFINER HELPER FUNCTIONS
-- --------------------------------------------------------------------

-- Check if a given user is a member of an organization
CREATE OR REPLACE FUNCTION private.is_org_member(p_org_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.organization_members
        WHERE organization_id = p_org_id AND user_id = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Check if a given user is the owner of an organization
CREATE OR REPLACE FUNCTION private.is_org_owner(p_org_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.organizations
        WHERE id = p_org_id AND owner_id = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Check user role in public.profiles safely
CREATE OR REPLACE FUNCTION private.get_user_role(p_user_id UUID)
RETURNS public.app_role AS $$
DECLARE
    v_role public.app_role;
BEGIN
    SELECT role INTO v_role FROM public.profiles WHERE id = p_user_id;
    RETURN v_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

GRANT USAGE ON SCHEMA private TO authenticated;

GRANT EXECUTE ON FUNCTION private.is_org_member(UUID, UUID) TO postgres, service_role, authenticated;
GRANT EXECUTE ON FUNCTION private.is_org_owner(UUID, UUID) TO postgres, service_role, authenticated;
GRANT EXECUTE ON FUNCTION private.get_user_role(UUID) TO postgres, service_role, authenticated;

-- --------------------------------------------------------------------
-- 7. TRIGGER FUNCTIONS & TRIGGERS
-- --------------------------------------------------------------------

-- Automatic Updated_At Timestamp Function (Invoker execution, no SECURITY DEFINER required)
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_organizations_updated_at ON public.organizations;
CREATE TRIGGER set_organizations_updated_at
    BEFORE UPDATE ON public.organizations
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_subscriptions_updated_at ON public.subscriptions;
CREATE TRIGGER set_subscriptions_updated_at
    BEFORE UPDATE ON public.subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_app_settings_updated_at ON public.app_settings;
CREATE TRIGGER set_app_settings_updated_at
    BEFORE UPDATE ON public.app_settings
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_gap_reports_updated_at ON public.gap_analysis_reports;
CREATE TRIGGER set_gap_reports_updated_at
    BEFORE UPDATE ON public.gap_analysis_reports
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_missing_items_updated_at ON public.missing_items;
CREATE TRIGGER set_missing_items_updated_at
    BEFORE UPDATE ON public.missing_items
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Automatic Profile Creation Handler on Auth Signup (Privileged, secured with pinned search_path & collision handling)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    base_username TEXT;
    candidate_username TEXT;
    suffix INT := 0;
    inserted BOOLEAN := FALSE;
BEGIN
    base_username := COALESCE(
        NEW.raw_user_meta_data->>'username',
        split_part(NEW.email, '@', 1)
    );

    IF base_username IS NULL OR base_username = '' THEN
        base_username := 'user';
    END IF;

    candidate_username := base_username;

    WHILE NOT inserted LOOP
        BEGIN
            INSERT INTO public.profiles (id, full_name, avatar_url, username, role)
            VALUES (
                NEW.id,
                COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
                COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
                candidate_username,
                'user'::public.app_role
            )
            ON CONFLICT (id) DO NOTHING;

            inserted := TRUE;
        EXCEPTION WHEN unique_violation THEN
            suffix := suffix + 1;
            candidate_username := base_username || '_' || suffix::text || '_' || substr(replace(NEW.id::text, '-', ''), 1, 4);
        END;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres, service_role;

-- Trigger on auth.users for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Automatic Workspace/Organization Owner Membership Provisioning Handler
CREATE OR REPLACE FUNCTION public.handle_new_organization()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.organization_members (organization_id, user_id, role)
    VALUES (NEW.id, NEW.owner_id, 'admin'::public.app_role)
    ON CONFLICT (organization_id, user_id) DO UPDATE SET role = 'admin'::public.app_role;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.handle_new_organization() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_organization() TO postgres, service_role;

-- Trigger on public.organizations when a new organization is created
DROP TRIGGER IF EXISTS on_organization_created ON public.organizations;
CREATE TRIGGER on_organization_created
    AFTER INSERT ON public.organizations
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_organization();

-- --------------------------------------------------------------------
-- 8. ROW LEVEL SECURITY (RLS) POLICIES (IDEMPOTENT CREATION)
-- --------------------------------------------------------------------

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.gap_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gap_analysis_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.missing_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gap_remediation_steps ENABLE ROW LEVEL SECURITY;

-- PROFILES POLICIES
DROP POLICY IF EXISTS "Public profiles are viewable by authenticated users" ON public.profiles;
CREATE POLICY "Public profiles are viewable by authenticated users"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

-- User profile updates cannot change role (role escalation prevention)
DROP POLICY IF EXISTS "Users can update their own non-role profile fields" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own non-role profile fields"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (
        auth.uid() = id AND
        role = private.get_user_role(auth.uid())
    );

-- ORGANIZATIONS POLICIES
DROP POLICY IF EXISTS "Users can view organizations they belong to or own" ON public.organizations;
CREATE POLICY "Users can view organizations they belong to or own"
    ON public.organizations FOR SELECT
    TO authenticated
    USING (
        owner_id = auth.uid() OR
        private.is_org_member(id, auth.uid())
    );

DROP POLICY IF EXISTS "Authenticated users can create an organization" ON public.organizations;
CREATE POLICY "Authenticated users can create an organization"
    ON public.organizations FOR INSERT
    TO authenticated
    WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Organization owners can update their organization" ON public.organizations;
CREATE POLICY "Organization owners can update their organization"
    ON public.organizations FOR UPDATE
    TO authenticated
    USING (owner_id = auth.uid())
    WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Organization owners can delete their organization" ON public.organizations;
CREATE POLICY "Organization owners can delete their organization"
    ON public.organizations FOR DELETE
    TO authenticated
    USING (owner_id = auth.uid());

-- ORGANIZATION MEMBERS POLICIES
DROP POLICY IF EXISTS "Members can view membership of their organization" ON public.organization_members;
CREATE POLICY "Members can view membership of their organization"
    ON public.organization_members FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR
        private.is_org_owner(organization_id, auth.uid())
    );

DROP POLICY IF EXISTS "Org owners can manage organization members" ON public.organization_members;
CREATE POLICY "Org owners can manage organization members"
    ON public.organization_members FOR ALL
    TO authenticated
    USING (private.is_org_owner(organization_id, auth.uid()))
    WITH CHECK (private.is_org_owner(organization_id, auth.uid()));

-- SUBSCRIPTIONS POLICIES
DROP POLICY IF EXISTS "Users can view their own or org subscription" ON public.subscriptions;
CREATE POLICY "Users can view their own or org subscription"
    ON public.subscriptions FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR
        private.is_org_member(organization_id, auth.uid())
    );

-- NOTIFICATIONS POLICIES
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
CREATE POLICY "Users can view their own notifications"
    ON public.notifications FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
CREATE POLICY "Users can update their own notifications"
    ON public.notifications FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- APP SETTINGS POLICIES
DROP POLICY IF EXISTS "Users can view public settings or their own settings" ON public.app_settings;
CREATE POLICY "Users can view public settings or their own settings"
    ON public.app_settings FOR SELECT
    TO authenticated
    USING (
        is_public OR
        user_id = auth.uid() OR
        private.is_org_member(organization_id, auth.uid())
    );

DROP POLICY IF EXISTS "Users can manage their own settings" ON public.app_settings;
CREATE POLICY "Users can manage their own settings"
    ON public.app_settings FOR ALL
    TO authenticated
    USING (
        user_id = auth.uid() OR
        private.is_org_owner(organization_id, auth.uid())
    )
    WITH CHECK (
        user_id = auth.uid() OR
        private.is_org_owner(organization_id, auth.uid())
    );

-- AUDIT LOGS POLICIES
DROP POLICY IF EXISTS "Users can view their own audit logs" ON public.audit_logs;
CREATE POLICY "Users can view their own audit logs"
    ON public.audit_logs FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR
        private.get_user_role(auth.uid()) = 'admin'::public.app_role
    );

-- GAP ANALYSIS POLICIES
DROP POLICY IF EXISTS "Authenticated users can view gap categories" ON public.gap_categories;
CREATE POLICY "Authenticated users can view gap categories"
    ON public.gap_categories FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can view gap reports" ON public.gap_analysis_reports;
CREATE POLICY "Authenticated users can view gap reports"
    ON public.gap_analysis_reports FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can view missing items" ON public.missing_items;
CREATE POLICY "Authenticated users can view missing items"
    ON public.missing_items FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can view remediation steps" ON public.gap_remediation_steps;
CREATE POLICY "Authenticated users can view remediation steps"
    ON public.gap_remediation_steps FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can create gap reports" ON public.gap_analysis_reports;
CREATE POLICY "Users can create gap reports"
    ON public.gap_analysis_reports FOR INSERT TO authenticated WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "Assigned users or admins can update missing items" ON public.missing_items;
CREATE POLICY "Assigned users or admins can update missing items"
    ON public.missing_items FOR UPDATE TO authenticated
    USING (
        auth.uid() = assigned_to OR
        private.get_user_role(auth.uid()) IN ('admin'::public.app_role, 'manager'::public.app_role)
    );

DROP POLICY IF EXISTS "Assigned users or admins can manage remediation steps" ON public.gap_remediation_steps;
CREATE POLICY "Assigned users or admins can manage remediation steps"
    ON public.gap_remediation_steps FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.missing_items mi
            WHERE mi.id = public.gap_remediation_steps.missing_item_id
            AND (mi.assigned_to = auth.uid() OR private.get_user_role(auth.uid()) IN ('admin'::public.app_role, 'manager'::public.app_role))
        )
    );

-- --------------------------------------------------------------------
-- 9. LEAST-PRIVILEGE TABLE GRANTS
-- --------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (username, full_name, avatar_url, website, bio, metadata) ON public.profiles TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.organizations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.organization_members TO authenticated;
GRANT SELECT ON public.subscriptions TO authenticated;
GRANT SELECT, UPDATE (is_read) ON public.notifications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_settings TO authenticated;
GRANT SELECT ON public.audit_logs TO authenticated;

GRANT SELECT ON public.gap_categories TO authenticated;
GRANT SELECT, INSERT ON public.gap_analysis_reports TO authenticated;
GRANT SELECT, UPDATE ON public.missing_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gap_remediation_steps TO authenticated;
