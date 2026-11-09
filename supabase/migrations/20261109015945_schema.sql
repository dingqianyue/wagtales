-- Wagtales database schema: tables, functions, triggers and row level security.

------------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id),
  username text unique,
  full_name text,
  bio text,
  education text,
  workplace text,
  avatar_url text,
  updated_at timestamptz default timezone('utc', now())
);

create table public.pets (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  species text not null,
  gender text,
  breed text,
  birthday date,
  personality text,
  is_birthday_estimated boolean default false,
  is_memorial boolean default false,
  system_icon text default 'pawprint.circle.fill',
  created_at timestamptz default timezone('utc', now()),
  photo_url text
);

-- A pet can have several owners (co-ownership).
create table public.pet_owners (
  pet_id uuid not null references public.pets (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default timezone('utc', now()),
  primary key (pet_id, user_id)
);

create table public.pet_followers (
  user_id uuid not null references public.profiles (id) on delete cascade,
  pet_id uuid not null references public.pets (id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, pet_id)
);

create table public.user_follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now(),
  primary key (follower_id, following_id),
  constraint cannot_follow_self check (follower_id <> following_id)
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  user_id uuid not null references public.profiles (id) on delete cascade,
  pet_id uuid references public.pets (id) on delete cascade,
  title text not null,
  content text not null,
  image_url text,
  likes_count integer default 0,
  saves_count integer default 0,
  comments_count integer default 0,
  shares_count integer default 0,
  views_count integer default 0,
  tags text[] default '{}'
);

create table public.post_likes (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

create table public.post_saves (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

create table public.post_shares (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts (id) on delete cascade,
  user_id uuid references auth.users (id) on delete cascade,
  created_at timestamptz default now()
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete cascade,
  content text not null,
  created_at timestamptz default now(),
  parent_comment_id uuid references public.comments (id) on delete cascade,
  likes_count integer default 0
);

create table public.comment_likes (
  comment_id uuid not null references public.comments (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz default now(),
  primary key (comment_id, user_id)
);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references auth.users (id) on delete cascade,
  receiver_id uuid references auth.users (id) on delete cascade,
  text text not null,
  created_at timestamptz default now(),
  is_read boolean default false
);

------------------------------------------------------------------------------
-- Counter triggers
------------------------------------------------------------------------------
-- Keep likes_count / saves_count / comments_count in sync.
-- On delete, skip the update when the post or comment author no longer exists
-- (the row is being removed in the same cascade), and never go below zero.

create function public.update_likes_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts p set likes_count = p.likes_count + 1
    where p.id = NEW.post_id;
  elsif TG_OP = 'DELETE' then
    update public.posts p set likes_count = greatest(p.likes_count - 1, 0)
    where p.id = OLD.post_id
      and exists (select 1 from public.profiles pr where pr.id = p.user_id);
  end if;
  return null;
end;
$$;

create function public.update_saves_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts p set saves_count = p.saves_count + 1
    where p.id = NEW.post_id;
  elsif TG_OP = 'DELETE' then
    update public.posts p set saves_count = greatest(p.saves_count - 1, 0)
    where p.id = OLD.post_id
      and exists (select 1 from public.profiles pr where pr.id = p.user_id);
  end if;
  return null;
end;
$$;

create function public.update_post_comments_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts p set comments_count = p.comments_count + 1
    where p.id = NEW.post_id;
  elsif TG_OP = 'DELETE' then
    update public.posts p set comments_count = greatest(p.comments_count - 1, 0)
    where p.id = OLD.post_id
      and exists (select 1 from public.profiles pr where pr.id = p.user_id);
  end if;
  return null;
end;
$$;

create function public.update_comment_likes_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if TG_OP = 'INSERT' then
    update public.comments c set likes_count = c.likes_count + 1
    where c.id = NEW.comment_id;
  elsif TG_OP = 'DELETE' then
    update public.comments c set likes_count = greatest(c.likes_count - 1, 0)
    where c.id = OLD.comment_id
      and exists (select 1 from public.profiles pr where pr.id = c.user_id);
  end if;
  return null;
end;
$$;

create trigger tr_post_likes_changed
  after insert or delete on public.post_likes
  for each row execute function public.update_likes_count();

create trigger tr_post_saves_changed
  after insert or delete on public.post_saves
  for each row execute function public.update_saves_count();

create trigger tr_post_comments_changed
  after insert or delete on public.comments
  for each row execute function public.update_post_comments_count();

create trigger tr_comment_likes_changed
  after insert or delete on public.comment_likes
  for each row execute function public.update_comment_likes_count();

------------------------------------------------------------------------------
-- Inbox
------------------------------------------------------------------------------
-- Latest message per conversation for the signed-in user. Only callable for
-- your own user id.

create function public.get_user_inbox(target_user_id uuid)
returns table(
  other_user_id uuid,
  other_username text,
  last_message text,
  last_message_time timestamptz,
  is_unread boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if target_user_id is distinct from (select auth.uid()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  return query
  with conversations as (
    select
      case when m.sender_id = target_user_id then m.receiver_id else m.sender_id end as other_id,
      m.text,
      m.created_at,
      (m.receiver_id = target_user_id and m.is_read = false) as unread,
      row_number() over (
        partition by case when m.sender_id = target_user_id then m.receiver_id else m.sender_id end
        order by m.created_at desc
      ) as rn
    from public.chat_messages m
    where m.sender_id = target_user_id or m.receiver_id = target_user_id
  )
  select c.other_id, p.username, c.text, c.created_at, c.unread
  from conversations c
  join public.profiles p on p.id = c.other_id
  where c.rn = 1
  order by c.created_at desc;
end;
$$;

revoke execute on function public.get_user_inbox(uuid) from public, anon;
grant execute on function public.get_user_inbox(uuid) to authenticated;

------------------------------------------------------------------------------
-- Pet ownership helpers
------------------------------------------------------------------------------
-- SECURITY DEFINER so the pet_owners insert policy can check pet_owners
-- without recursing into its own RLS.

create function public.is_pet_owner(target_pet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.pet_owners
    where pet_id = target_pet_id and user_id = (select auth.uid())
  );
$$;

create function public.pet_has_owners(target_pet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.pet_owners where pet_id = target_pet_id);
$$;

revoke execute on function public.is_pet_owner(uuid) from public, anon;
revoke execute on function public.pet_has_owners(uuid) from public, anon;
grant execute on function public.is_pet_owner(uuid) to authenticated;
grant execute on function public.pet_has_owners(uuid) to authenticated;

------------------------------------------------------------------------------
-- Row level security
------------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.pets enable row level security;
alter table public.pet_owners enable row level security;
alter table public.pet_followers enable row level security;
alter table public.user_follows enable row level security;
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_saves enable row level security;
alter table public.post_shares enable row level security;
alter table public.comments enable row level security;
alter table public.comment_likes enable row level security;
alter table public.chat_messages enable row level security;

-- profiles
create policy "Public profiles are viewable by everyone." on public.profiles
  for select using (true);

create policy "Users can insert their own profile." on public.profiles
  for insert with check ((select auth.uid()) = id);

create policy "Users can update own profile" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- pets
create policy "Pets are viewable by everyone." on public.pets
  for select using (true);

create policy "Authenticated users can create pets." on public.pets
  for insert with check ((select auth.uid()) is not null);

create policy "Co-owners can update their pets." on public.pets
  for update using (
    exists (
      select 1 from public.pet_owners
      where pet_owners.pet_id = pets.id and pet_owners.user_id = (select auth.uid())
    )
  );

create policy "Owners can delete their pets" on public.pets
  for delete using (
    exists (
      select 1 from public.pet_owners
      where pet_owners.pet_id = pets.id and pet_owners.user_id = (select auth.uid())
    )
  );

-- pet_owners
create policy "Pet owners viewable by everyone." on public.pet_owners
  for select using (true);

-- Allowed: claiming a brand-new pet (no owners yet) for yourself,
-- or an existing owner adding another user as a co-owner.
create policy "Owners can add co-owners" on public.pet_owners
  for insert to authenticated
  with check (
    (user_id = (select auth.uid()) and not public.pet_has_owners(pet_id))
    or public.is_pet_owner(pet_id)
  );

create policy "Users can remove themselves from a pet" on public.pet_owners
  for delete using ((select auth.uid()) = user_id);

-- pet_followers
create policy "Anyone can see pet followers" on public.pet_followers
  for select using (true);

create policy "Users can follow pets" on public.pet_followers
  for insert with check ((select auth.uid()) = user_id);

create policy "Users can unfollow pets" on public.pet_followers
  for delete using ((select auth.uid()) = user_id);

-- user_follows
create policy "Anyone can see followers" on public.user_follows
  for select using (true);

create policy "Users can follow others" on public.user_follows
  for insert with check ((select auth.uid()) = follower_id);

create policy "Users can unfollow others" on public.user_follows
  for delete using ((select auth.uid()) = follower_id);

-- posts
create policy "Anyone can view posts" on public.posts
  for select using (true);

create policy "Users can create their own posts" on public.posts
  for insert with check ((select auth.uid()) = user_id);

create policy "Users can delete their own posts" on public.posts
  for delete using ((select auth.uid()) = user_id);

-- post_likes
create policy "Anyone can view likes" on public.post_likes
  for select using (true);

create policy "Users can like posts" on public.post_likes
  for insert to authenticated with check ((select auth.uid()) = user_id);

create policy "Users can unlike posts" on public.post_likes
  for delete to authenticated using ((select auth.uid()) = user_id);

-- post_saves
create policy "Users can view own saves" on public.post_saves
  for select to authenticated using ((select auth.uid()) = user_id);

create policy "Users can save posts" on public.post_saves
  for insert to authenticated with check ((select auth.uid()) = user_id);

create policy "Users can unsave posts" on public.post_saves
  for delete to authenticated using ((select auth.uid()) = user_id);

-- post_shares: no policies yet (the app doesn't record shares).

-- comments
create policy "Anyone can view comments" on public.comments
  for select using (true);

create policy "Users can insert comments" on public.comments
  for insert to authenticated with check ((select auth.uid()) = user_id);

create policy "Users and Post Owners can delete comments" on public.comments
  for delete to authenticated using (
    (select auth.uid()) = user_id
    or (select auth.uid()) = (select posts.user_id from public.posts where posts.id = comments.post_id)
  );

-- comment_likes
create policy "Anyone can view comment likes" on public.comment_likes
  for select using (true);

create policy "Users can like comments" on public.comment_likes
  for insert to authenticated with check ((select auth.uid()) = user_id);

create policy "Users can unlike comments" on public.comment_likes
  for delete to authenticated using ((select auth.uid()) = user_id);

-- chat_messages
create policy "Users can view their own chats" on public.chat_messages
  for select using ((select auth.uid()) = sender_id or (select auth.uid()) = receiver_id);

create policy "Users can send messages" on public.chat_messages
  for insert to authenticated with check ((select auth.uid()) = sender_id);

-- The receiver can mark messages as read, and can't change anything else.
create policy "Receivers can mark messages as read" on public.chat_messages
  for update to authenticated
  using (receiver_id = (select auth.uid()))
  with check (receiver_id = (select auth.uid()));

revoke update on public.chat_messages from anon, authenticated;
grant update (is_read) on public.chat_messages to authenticated;
