-- Migration 004: protect case fields that must not be edited freely.
-- Run once, after 003_rls_policies.sql.

-- ---------------------------------------------------------------------------
-- guard_case_update()
-- RLS decides WHICH rows a user may update, but it cannot restrict WHICH
-- COLUMNS they change. Without this guard, anyone allowed to edit a case
-- could rewrite who logged it, when it was created, or fake its resolution
-- time, which would make the audit trail and "time to resolve" analytics
-- untrustworthy. A trigger sees both the old and new row, so it can enforce
-- those rules.
--
-- Not SECURITY DEFINER on purpose: it must run as the signed-in user so that
-- auth.uid() and public.is_admin() describe the person making the edit.
-- search_path is empty so nothing can be hijacked by a look-alike object;
-- that is why every name is schema-qualified.
--
-- When auth.uid() is null the change is not coming from a signed-in app user
-- (it is the SQL editor or the service role), so the guard steps aside. That
-- keeps an escape hatch for data fixes by whoever holds those keys.
-- ---------------------------------------------------------------------------
create function public.guard_case_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;

  -- Identity and history fields: fixed once the case exists, for everyone,
  -- admins included.
  if new.id is distinct from old.id then
    raise exception 'cases.id cannot be changed';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'cases.created_by cannot be changed';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'cases.created_at cannot be changed';
  end if;
  if new.received_at is distinct from old.received_at then
    raise exception 'cases.received_at cannot be changed';
  end if;

  -- Assignment is an admin decision; agents may work a case but not hand it
  -- off or pick up someone else's.
  if new.assigned_to is distinct from old.assigned_to
     and not public.is_admin() then
    raise exception 'cases.assigned_to can only be changed by an admin';
  end if;

  -- resolved_at is managed here, never typed in by the app, so it always
  -- reflects the real moment the case was resolved.
  if new.status = 'Resolved' and old.status is distinct from 'Resolved' then
    new.resolved_at := now();
  elsif old.status = 'Resolved' and new.status is distinct from 'Resolved' then
    -- Business rule: a case is marked Resolved only after the client has
    -- confirmed, so Resolved is final. Blocking reopening keeps the history
    -- clean; a returning issue becomes a new case instead.
    raise exception 'Resolved cases cannot be reopened. Create a new case instead.';
  elsif new.resolved_at is distinct from old.resolved_at then
    raise exception 'cases.resolved_at is set automatically when status becomes Resolved and cannot be changed directly';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- cases_guard_update
-- Runs before every update so the checks happen before anything is saved.
-- ---------------------------------------------------------------------------
create trigger cases_guard_update
  before update on public.cases
  for each row
  execute function public.guard_case_update();

-- ---------------------------------------------------------------------------
-- INSERT policy on cases (replaces the one from 003)
-- Business rule: any active user can log a case in their own name, but a new
-- case from an agent always starts unassigned and 'New'. Otherwise an agent
-- could skip the assignment step the update guard reserves for admins, or
-- create a case that is already 'In Progress'. Admins may create a case with
-- any assignee, so they can log and assign in one step.
-- ---------------------------------------------------------------------------
drop policy "Active users can create cases as themselves" on public.cases;

create policy "Active users can create cases as themselves"
  on public.cases
  for insert
  to authenticated
  with check (
    public.is_active_user()
    and created_by = (select auth.uid())
    and (
      public.is_admin()
      or (assigned_to is null and status = 'New')
    )
  );
