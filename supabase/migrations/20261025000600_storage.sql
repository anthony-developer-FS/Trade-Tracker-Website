-- =============================================================================
-- File storage. Files live under "<user id>/..." in each bucket, and users can
-- only touch their own folder.
--   trade-attachments: chart screenshots attached to trades
--   imports:           original broker files, kept so imports can be re-run
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('trade-attachments', 'trade-attachments', false, 10485760,
    array['image/png', 'image/jpeg', 'image/webp', 'image/gif']),
  ('imports', 'imports', false, 20971520,
    array['text/csv', 'text/plain', 'application/vnd.ms-excel',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do nothing;

create policy "Users manage files in their own folder"
  on storage.objects for all to authenticated
  using (
    bucket_id in ('trade-attachments', 'imports')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id in ('trade-attachments', 'imports')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
