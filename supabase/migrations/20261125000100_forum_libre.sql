-- Radio Flow : le « Forum » devient l'espace de discussion libre ; les propositions de sujets
-- (table forum_proposals) vivent désormais dans la section « Rédaction » de l'application.
-- Le rappel quotidien est un vrai message du Forum, signé « Radio Flow » (message système),
-- accompagné d'une notification (donc d'un push) pour chaque membre.

create table public.forum_posts (
  id         uuid primary key default gen_random_uuid(),
  author_id  uuid references public.users (id) on delete cascade,
  is_system  boolean not null default false,
  content    text not null check (length(btrim(content)) > 0),
  created_at timestamptz not null default now(),
  -- un message a soit un auteur, soit il est un message système
  check (author_id is not null or is_system)
);

create index forum_posts_created_idx on public.forum_posts (created_at desc);

alter table public.forum_posts enable row level security;

create policy forum_posts_select on public.forum_posts
  for select to authenticated using (true);
-- Tout membre peut écrire sous son propre nom ; jamais de message système depuis l'application.
create policy forum_posts_insert on public.forum_posts
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and not is_system
    and public.app_role() is not null
  );
create policy forum_posts_delete on public.forum_posts
  for delete to authenticated
  using (author_id = (select auth.uid()) or public.app_role() = 'admin');

alter publication supabase_realtime add table public.forum_posts;

-- Rappel quotidien : remplace la version précédente (notification seule).
-- Idempotente : un second appel le même jour (heure de Kindu) ne fait rien.
create or replace function public.send_daily_forum_reminder()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if exists (
    select 1 from public.forum_posts
    where is_system
      and created_at >= date_trunc('day', now() at time zone 'Africa/Lubumbashi') at time zone 'Africa/Lubumbashi'
  ) then
    return 0;
  end if;

  insert into public.forum_posts (is_system, content)
  values (true, 'Bonjour à tous, n''oubliez pas de poster vos sujets dans la Rédaction.');

  insert into public.notifications (user_id, kind, title, body, ref_type)
  select u.id,
         'forum_reminder',
         'Bonjour à tous',
         'N''oubliez pas de poster vos sujets dans la Rédaction.',
         'forum'
  from public.users u;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.send_daily_forum_reminder() from public, anon, authenticated;
