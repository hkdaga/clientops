-- Migration 003: Row Level Security policies and the is_active flag.
-- Run once, after schema.sql and 002_profile_on_signup.sql.

-- ---------------------------------------------------------------------------
-- profiles.is_active
-- Lets an admin switch a team member off without deleting them (cases keep
-- pointing at their profile, so history stays intact). Deactivated users can
-- still sign in, but the policies below give them no access to any data.
-- Existing and new profiles start active.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column is_active boolean not null default true;

-- ---------------------------------------------------------------------------
-- Helper functions
-- Policies need to ask "is this user active?" and "is this user an admin?",
-- and both answers live in profiles. A policy on profiles that queried
-- profiles directly would trigger the same policy again, which queries
-- profiles again, and so on: infinite recursion. These functions are SECURITY
-- DEFINER, so they read profiles with their owner's rights and skip RLS,
-- which breaks the loop. The same helpers are reused by the cases policies so
-- the rules are defined in one place.
--
-- STABLE: the answer cannot change within one statement, so Postgres may
-- reuse it. search_path is empty so nothing can be hijacked by a look-alike
-- object; every name is therefore schema-qualified.
-- ---------------------------------------------------------------------------

-- True if the signed-in user has a profile and that profile is active.
create function public.is_active_user()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and is_active
  );
$$;

-- True if the signed-in user is active AND has the admin role.
create function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and is_active
      and role = 'admin'
  );
$$;

-- Only signed-in users may call these; anonymous visitors may not.
revoke execute on function public.is_active_user() from public, anon;
revoke execute on function public.is_admin()       from public, anon;
grant  execute on function public.is_active_user() to authenticated;
grant  execute on function public.is_admin()       to authenticated;

-- ---------------------------------------------------------------------------
-- profiles policies
-- ---------------------------------------------------------------------------

-- Business rule: every active team member can see the team list (needed to
-- show names and to pick an assignee). Deactivated users see nothing.
-- There are deliberately no insert, update or delete policies: profiles are
-- created by the signup trigger, and roles / active status are changed only
-- by someone with the service role (e.g. the SQL editor), never from the app.
create policy "Active users can view profiles"
  on public.profiles
  for select
  to authenticated
  using (public.is_active_user());

-- ---------------------------------------------------------------------------
-- cases policies
-- ---------------------------------------------------------------------------

-- Business rule: admins see every case. An agent sees only the cases they
-- logged or that are assigned to them. Deactivated users see nothing.
create policy "Admins see all cases, agents see their own"
  on public.cases
  for select
  to authenticated
  using (
    public.is_admin()
    or (
      public.is_active_user()
      and (
        assigned_to = (select auth.uid())
        or created_by = (select auth.uid())
      )
    )
  );

-- Business rule: any active user can log a new case, but only in their own
-- name; nobody can log a case as someone else.
create policy "Active users can create cases as themselves"
  on public.cases
  for insert
  to authenticated
  with check (
    public.is_active_user()
    and created_by = (select auth.uid())
  );

-- Business rule: admins can edit any case (including assigning it). An agent
-- can edit only the cases currently assigned to them. The same test is applied
-- to the row after the edit, so an agent cannot hand their case to someone
-- else and lose track of it; reassignment is an admin action.
create policy "Admins edit all cases, agents edit assigned cases"
  on public.cases
  for update
  to authenticated
  using (
    public.is_admin()
    or (
      public.is_active_user()
      and assigned_to = (select auth.uid())
    )
  )
  with check (
    public.is_admin()
    or (
      public.is_active_user()
      and assigned_to = (select auth.uid())
    )
  );

-- Business rule: cases are never deleted, so the audit trail stays complete.
-- This is done by having no delete policy: with RLS on, that denies every
-- delete from the app.
