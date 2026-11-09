-- Clean up after a user is deleted.

-- Deleting a user from Auth also deletes their profile, which cascades to
-- their posts, comments, follows and pet ownership rows.
alter table public.profiles drop constraint profiles_id_fkey;

alter table public.profiles
  add constraint profiles_id_fkey
    foreign key (id) references auth.users (id) on delete cascade;

-- Pets are linked to users only through pet_owners. When a pet loses its last
-- owner (the owner was deleted or left), delete the pet too, which cascades to
-- its posts and followers. Otherwise nobody could edit or delete it.
create function public.delete_pet_if_ownerless()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.pet_owners where pet_id = OLD.pet_id) then
    delete from public.pets where id = OLD.pet_id;
  end if;
  return null;
end;
$$;

revoke execute on function public.delete_pet_if_ownerless() from public, anon, authenticated;

create trigger tr_delete_ownerless_pet
  after delete on public.pet_owners
  for each row execute function public.delete_pet_if_ownerless();
