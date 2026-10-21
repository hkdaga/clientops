-- Migration 002: create a profiles row automatically when someone signs up.
-- Run once, after schema.sql.

-- ---------------------------------------------------------------------------
-- handle_new_user()
-- Every login in auth.users needs a matching profiles row, because cases
-- point at profiles and the app reads names and roles from there. Doing it in
-- the database means no signup path can forget to create the profile.
--
-- SECURITY DEFINER: the new user has no permission to write to profiles (RLS
-- is on, with no insert policy), so the function runs with its owner's rights.
-- search_path is set to empty so nothing can be hijacked by a look-alike
-- object; that is why every table is written as public.profiles.
--
-- full_name comes from the signup metadata; if it is missing or blank, the
-- part of the email before the @ is used, since full_name is required.
--
-- role is hardcoded to 'agent' on purpose. Signup metadata is supplied by the
-- person signing up, so reading a role from it would let anyone make
-- themselves an admin. Admins must be promoted deliberately after signup.
-- ---------------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      split_part(new.email, '@', 1)
    ),
    'agent'
  );
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- on_auth_user_created
-- Calls handle_new_user() once for each newly created login. It runs AFTER
-- the insert so the auth.users row already exists when the profile row
-- references it.
-- ---------------------------------------------------------------------------
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();
