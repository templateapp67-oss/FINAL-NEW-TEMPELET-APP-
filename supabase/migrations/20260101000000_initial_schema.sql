-- ====================================================================
-- SUPABASE COMPLETE DATABASE SCHEMA
-- ====================================================================
-- Description: Production-ready database schema for Supabase
-- Includes: Extensions, Enums, Tables, Foreign Keys, Triggers, RLS Policies, Indexes, Grants
-- Modules: Core Auth Profiles, Organizations, Subscriptions, Notifications,
--          App Settings, Audit Logs, and Gap Analysis / Missing Items Tracking.
-- ====================================================================

-- --------------------------------------------------------------------
-- 1. EXTENSIONS
-- --------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- --------------------------------------------------------------------
-- 2. CUSTOM TYPES & ENUMS
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
-- 3. TABLES & CONSTRAINTS
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
    CONSTRAINT sub_owner_xor_check CHECK (
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
    CONSTRAINT settings_owner_check CHECK (
        (user_id IS NOT NULL AND organization_id IS NULL) OR
        (user_id IS NULL AND organization_id IS NOT NULL) OR
        (user_id IS NULL AND organization_id IS NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_user_setting ON public.app_settings(key, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_org_setting ON public.app_settings(key, organization_id) WHERE organization_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_global_setting ON public.app_settings(key) WHERE user_id IS NULL AND organization_id IS NULL;

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

-- GAP CATEGORIES
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
    UNIQUE(missing_item_id, step_number),
    CONSTRAINT check_completion_consistency CHECK (
        (is_completed = true AND completed_at IS NOT NULL) OR
        (is_completed = false AND completed_at IS NULL)
    )
);

-- --------------------------------------------------------------------
-- 4. INDEXES
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

-- --------------------------------------------------------------------
-- 5. HELPER FUNCTIONS & TRIGGERS
-- --------------------------------------------------------------------

-- Automatic Updated_At Timestamp Function
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER SET search_path = '';

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

-- SECURITY HELPER FUNCTIONS (Avoid RLS Circular Dependencies)
CREATE OR REPLACE FUNCTION public.is_org_owner(check_org_id UUID, check_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.organizations
        WHERE id = check_org_id AND owner_id = check_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.is_org_member(check_org_id UUID, check_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.organization_members
        WHERE organization_id = check_org_id AND user_id = check_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.is_admin_or_manager(check_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = check_user_id AND role IN ('admin'::public.app_role, 'manager'::public.app_role)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Profile Role Privilege Protection Trigger
CREATE OR REPLACE FUNCTION public.protect_profile_role()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        IF NOT public.is_admin_or_manager(auth.uid()) AND current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
            RAISE EXCEPTION 'Only administrators or managers can alter user roles.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS check_profile_role_update ON public.profiles;
CREATE TRIGGER check_profile_role_update
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.protect_profile_role();

-- Automatic Profile Creation Handler on Auth Signup (Race Condition & Collision Safe)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    base_username TEXT;
    final_username TEXT;
    attempt INT := 0;
BEGIN
    base_username := COALESCE(
        NEW.raw_user_meta_data->>'username',
        split_part(NEW.email, '@', 1)
    );

    IF base_username IS NULL OR base_username = '' THEN
        base_username := 'user';
    END IF;

    final_username := base_username;

    LOOP
        BEGIN
            INSERT INTO public.profiles (id, full_name, avatar_url, username, role)
            VALUES (
                NEW.id,
                COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
                COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
                final_username,
                'user'::public.app_role
            )
            ON CONFLICT (id) DO NOTHING;
            EXIT;
        EXCEPTION WHEN unique_violation THEN
            attempt := attempt + 1;
            final_username := base_username || '_' || substr(replace(NEW.id::text, '-', ''), 1, 6) || '_' || attempt;
            IF attempt > 5 THEN
                final_username := 'user_' || replace(NEW.id::text, '-', '');
            END IF;
        END;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Trigger on auth.users for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- --------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
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

-- PROFILES Policies
DROP POLICY IF EXISTS "Public profiles are viewable by authenticated users" ON public.profiles;
CREATE POLICY "Public profiles are viewable by authenticated users"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile"
    ON public.profiles FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = id AND
        (role IS NULL OR role = 'user'::public.app_role OR public.is_admin_or_manager(auth.uid()))
    );

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (auth.uid() = id OR public.is_admin_or_manager(auth.uid()))
    WITH CHECK (auth.uid() = id OR public.is_admin_or_manager(auth.uid()));

-- ORGANIZATIONS Policies
DROP POLICY IF EXISTS "Users can view organizations they belong to or own" ON public.organizations;
CREATE POLICY "Users can view organizations they belong to or own"
    ON public.organizations FOR SELECT
    TO authenticated
    USING (
        owner_id = auth.uid() OR
        public.is_org_member(id, auth.uid())
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

-- ORGANIZATION MEMBERS Policies
DROP POLICY IF EXISTS "Members can view membership of their organization" ON public.organization_members;
CREATE POLICY "Members can view membership of their organization"
    ON public.organization_members FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR
        public.is_org_owner(organization_id, auth.uid())
    );

DROP POLICY IF EXISTS "Org owners can manage organization members" ON public.organization_members;
CREATE POLICY "Org owners can manage organization members"
    ON public.organization_members FOR ALL
    TO authenticated
    USING (public.is_org_owner(organization_id, auth.uid()))
    WITH CHECK (public.is_org_owner(organization_id, auth.uid()));

-- SUBSCRIPTIONS Policies
DROP POLICY IF EXISTS "Users can view their own or org subscription" ON public.subscriptions;
CREATE POLICY "Users can view their own or org subscription"
    ON public.subscriptions FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR
        (organization_id IS NOT NULL AND public.is_org_member(organization_id, auth.uid()))
    );

-- NOTIFICATIONS Policies
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

-- APP SETTINGS Policies
DROP POLICY IF EXISTS "Users can view public settings or their own settings" ON public.app_settings;
CREATE POLICY "Users can view public settings or their own settings"
    ON public.app_settings FOR SELECT
    TO authenticated
    USING (
        is_public OR
        user_id = auth.uid() OR
        (organization_id IS NOT NULL AND public.is_org_member(organization_id, auth.uid()))
    );

DROP POLICY IF EXISTS "Users can manage their own settings" ON public.app_settings;
CREATE POLICY "Users can manage their own settings"
    ON public.app_settings FOR ALL
    TO authenticated
    USING (
        user_id = auth.uid() OR
        (organization_id IS NOT NULL AND public.is_org_owner(organization_id, auth.uid()))
    )
    WITH CHECK (
        user_id = auth.uid() OR
        (organization_id IS NOT NULL AND public.is_org_owner(organization_id, auth.uid()))
    );

-- AUDIT LOGS Policies
DROP POLICY IF EXISTS "Users can view their own audit logs" ON public.audit_logs;
CREATE POLICY "Users can view their own audit logs"
    ON public.audit_logs FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR
        public.is_admin_or_manager(auth.uid())
    );

DROP POLICY IF EXISTS "Authenticated users can create audit log entries" ON public.audit_logs;
CREATE POLICY "Authenticated users can create audit log entries"
    ON public.audit_logs FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- GAP ANALYSIS Policies
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
    USING (auth.uid() = assigned_to OR public.is_admin_or_manager(auth.uid()))
    WITH CHECK (auth.uid() = assigned_to OR public.is_admin_or_manager(auth.uid()));

-- --------------------------------------------------------------------
-- 7. EXPLICIT DATA API GRANTS
-- --------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;

-- Revoke execute on helper functions from PUBLIC/anon to restrict direct execution where applicable
REVOKE EXECUTE ON FUNCTION public.is_org_owner(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_org_member(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_admin_or_manager(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_org_owner(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_org_member(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_admin_or_manager(UUID) TO authenticated, service_role;
