-- Storage buckets for images, and who can upload, replace or delete them.
--
-- All three buckets are public, so images load by public URL. The SELECT
-- policies are still needed because Storage's remove() requires SELECT access.
-- Users can only delete or replace files they uploaded.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',     'avatars',     true, null, '{image/*}'),
  ('pet_avatars', 'pet_avatars', true, null, null),
  ('posts',       'posts',       true, null, null)
on conflict (id) do nothing;

-- avatars: files live under "<user id>/<file>.jpg"
create policy "Avatar images are publicly readable" on storage.objects
  for select to public
  using (bucket_id = 'avatars');

create policy "Users can upload to their own avatar folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Users can delete their own avatars" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and owner_id = (select auth.uid())::text);

-- pet_avatars
create policy "Pet photos are publicly readable" on storage.objects
  for select to public
  using (bucket_id = 'pet_avatars');

create policy "Signed-in users can upload pet photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'pet_avatars');

create policy "Users can update their own pet photos" on storage.objects
  for update to authenticated
  using (bucket_id = 'pet_avatars' and owner_id = (select auth.uid())::text);

create policy "Users can delete their own pet photos" on storage.objects
  for delete to authenticated
  using (bucket_id = 'pet_avatars' and owner_id = (select auth.uid())::text);

-- posts
create policy "Post images are publicly readable" on storage.objects
  for select to public
  using (bucket_id = 'posts');

create policy "Signed-in users can upload post images" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'posts');

create policy "Users can delete their own post images" on storage.objects
  for delete to authenticated
  using (bucket_id = 'posts' and owner_id = (select auth.uid())::text);
