-- Usernames can only be changed once every 30 days.
--
-- username_changed_at records the last change. A trigger sets it and enforces
-- the 30-day limit, so the rule holds even if a client skips the app's check.
-- Clients can't set username_changed_at themselves.

alter table public.profiles add column username_changed_at timestamptz;

create function public.enforce_username_change_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if NEW.username is distinct from OLD.username then
    if OLD.username_changed_at > now() - interval '30 days' then
      raise exception 'You can only change your username once every 30 days.';
    end if;
    NEW.username_changed_at := now();
  else
    NEW.username_changed_at := OLD.username_changed_at;
  end if;
  return NEW;
end;
$$;

revoke execute on function public.enforce_username_change_limit() from public, anon, authenticated;

create trigger tr_enforce_username_change_limit
  before update on public.profiles
  for each row execute function public.enforce_username_change_limit();
