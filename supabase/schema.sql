-- ClientOps schema, version 1.
-- Read top to bottom: tables first, then the trigger, then indexes, then RLS.

-- ---------------------------------------------------------------------------
-- profiles
-- One row per team member. Supabase keeps logins in auth.users, which the app
-- cannot query freely, so this table holds the app-level details (name, role)
-- that the app needs to display and to decide what each person may do.
-- ---------------------------------------------------------------------------
create table public.profiles (
  -- Same id as the login account. Deleting the login removes the profile too,
  -- so we never keep a profile for someone who can no longer sign in.
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null,
  email       text not null,
  -- Only two roles exist for now; a CHECK is simpler than a roles table.
  role        text not null default 'agent'
              check (role in ('agent', 'admin')),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- cases
-- One row per client issue. This replaces the rows in the team's spreadsheet.
-- ---------------------------------------------------------------------------
create table public.cases (
  id            bigint generated always as identity primary key,
  client_name   text not null,
  client_email  text not null,

  -- Fixed pick-lists are enforced here so bad values can't get in from any
  -- source (the app, the SQL editor, an import script).
  issue_type    text not null
                check (issue_type in (
                  'Client Account Login',
                  'Data Discrepancy',
                  'Add Location',
                  'Claim Discrepancy',
                  'Functionality',
                  'Other'
                )),
  priority      text not null
                check (priority in ('High', 'Medium', 'Low')),
  description   text not null,

  -- When the client raised the issue, which can differ from when someone
  -- typed it in (created_at).
  received_at   timestamptz not null default now(),

  status        text not null default 'New'
                check (status in (
                  'New',
                  'In Progress',
                  'Blocked',
                  'Awaiting Client Confirmation',
                  'Resolved'
                )),

  -- Who logged the case. Defaults to the signed-in user so the app does not
  -- have to send it (and cannot easily fake it).
  created_by    uuid not null default auth.uid() references public.profiles (id),

  -- Stays null until an admin assigns the case, so "unassigned" is simply
  -- assigned_to is null.
  assigned_to   uuid references public.profiles (id),

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- Stays null until the case is resolved.
  resolved_at   timestamptz,

  -- resolved_at must be set exactly when status is 'Resolved', never otherwise.
  -- This keeps "time to resolve" analytics trustworthy: no resolved case is
  -- missing a timestamp, and no open case carries a stale one.
  constraint cases_resolved_consistency
    check ((resolved_at is not null) = (status = 'Resolved'))
);

-- ---------------------------------------------------------------------------
-- updated_at trigger
-- Keeps updated_at accurate on every edit, so the app and users can trust it
-- without remembering to set it in each update query.
-- ---------------------------------------------------------------------------
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger cases_set_updated_at
  before update on public.cases
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes
-- The app filters the case list by status and by assignee, so these keep
-- those filters fast as the table grows.
-- ---------------------------------------------------------------------------
create index cases_status_idx      on public.cases (status);
create index cases_assigned_to_idx on public.cases (assigned_to);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- Turned on now so the tables are never exposed by accident. With RLS on and
-- no policies, regular users can read and write nothing until policies are
-- added in a later step. (The service role key bypasses RLS.)
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.cases    enable row level security;
