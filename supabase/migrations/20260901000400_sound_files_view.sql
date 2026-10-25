-- Radio Flow : Espace Son (fichiers audio classés par édition et par position)

-- security_invoker : la vue applique les politiques RLS de l'utilisateur qui l'interroge
create or replace view public.sound_files
with (security_invoker = true)
as
select
  m.id                   as message_id,
  c.id                   as conductor_id,
  c.title                as conductor_title,
  c.broadcast_date,
  c.broadcast_time,
  c.status               as conductor_status,
  l.id                   as line_id,
  l.position_index,
  l.title                as line_title,
  m.audio_file_url       as storage_path,
  m.audio_original_name  as original_name,
  m.audio_duration,
  m.user_id              as uploaded_by,
  m.created_at           as uploaded_at
from public.messages m
join public.discussion_threads t on t.id = m.thread_id
join public.conductor_lines l on l.id = t.conductor_line_id
join public.conductors c on c.id = l.conductor_id
where m.audio_file_url is not null;

revoke all on public.sound_files from anon;
grant select on public.sound_files to authenticated;
