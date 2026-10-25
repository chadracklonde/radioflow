-- Radio Flow : statistiques de production pour le tableau de bord
--
-- Définition d'une « production » : un fichier audio publié dans un fil du conducteur.
-- On y ajoute les sujets validés au forum et les tâches terminées pour le bilan.
-- Exécutée avec les droits de l'appelant (security invoker) : la RLS s'applique.
create or replace function public.production_stats(p_from date, p_to date)
returns table (
  user_id            uuid,
  full_name          text,
  role               public.user_role,
  audio_count        bigint,
  approved_proposals bigint,
  tasks_done         bigint,
  tasks_open         bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    u.id,
    u.full_name,
    u.role,
    (select count(*) from public.messages m
      where m.user_id = u.id and m.audio_file_url is not null
        and m.created_at >= p_from and m.created_at < p_to + 1),
    (select count(*) from public.forum_proposals f
      where f.author_id = u.id and f.status = 'approved'
        and f.decided_at >= p_from and f.decided_at < p_to + 1),
    (select count(*) from public.tasks t
      where t.user_id = u.id and t.status = 'done'
        and t.completed_at >= p_from and t.completed_at < p_to + 1),
    (select count(*) from public.tasks t
      where t.user_id = u.id and t.status <> 'done')
  from public.users u
  where u.role <> 'technician'
  order by 4 desc, 5 desc, 6 desc, u.full_name;
$$;

revoke execute on function public.production_stats(date, date) from public, anon;
