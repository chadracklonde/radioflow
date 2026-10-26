-- Radio Flow : améliorations du travail quotidien de la rédaction
--
--   1. Notifications dans l'application (cloche) + jetons d'appareil pour de futures notifications push
--   3. La suppression d'un son suit la même règle de verrouillage que son envoi
--   4. Les sons peuvent être déplacés (renommage automatique quand les lignes sont réordonnées)
--   5. Les techniciens peuvent envoyer des sons
--   6. Durée cible d'une émission (créneau de la grille -> conducteur)
--   7. Texte à lire à l'antenne sur chaque ligne
--   8. Modèles de conducteur (lignes types d'un créneau)
--  12. Historique des modifications d'un conducteur
--  13. Suppléance temporaire du rédacteur en chef

-- ===========================================================================
-- 3. Suppression d'un son : refusée sur un conducteur verrouillé (sauf rédacteur en chef)
-- ===========================================================================
create or replace function public.guard_locked_audio_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conductor uuid;
begin
  -- pas d'utilisateur (serveur / éditeur SQL), pas de son, ou rédacteur en chef : autorisé
  if old.audio_file_url is null or auth.uid() is null or public.app_role() = 'admin' then
    return old;
  end if;
  select l.conductor_id into v_conductor
  from public.discussion_threads t
  join public.conductor_lines l on l.id = t.conductor_line_id
  where t.id = old.thread_id;
  if v_conductor is not null and public.conductor_is_locked(v_conductor) then
    raise exception 'Ce conducteur est verrouillé : plus de suppression de son';
  end if;
  return old;
end;
$$;

create trigger messages_guard_audio_delete
  before delete on public.messages
  for each row execute function public.guard_locked_audio_delete();

revoke execute on function public.guard_locked_audio_delete() from public, anon, authenticated;

alter policy conductor_audio_delete on storage.objects
  using (
    bucket_id = 'conductor-audio'
    and (
      public.app_role() = 'admin'
      or (
        owner = auth.uid()
        and not public.conductor_is_locked(((storage.foldername(name))[1])::uuid)
      )
    )
  );

-- ===========================================================================
-- 5. Les techniciens peuvent envoyer des sons (la règle de verrouillage reste la même)
-- ===========================================================================
alter policy conductor_audio_upload on storage.objects
  with check (
    bucket_id = 'conductor-audio'
    and public.app_role() in ('admin', 'journalist', 'technician')
    and (
      public.app_role() = 'admin'
      or not public.conductor_is_locked(((storage.foldername(name))[1])::uuid)
    )
  );

-- ===========================================================================
-- 4. Renommage des sons quand les lignes sont réordonnées (rédacteur en chef seulement)
-- ===========================================================================
create policy conductor_audio_move on storage.objects
  for update to authenticated
  using (bucket_id = 'conductor-audio' and public.app_role() = 'admin')
  with check (bucket_id = 'conductor-audio' and public.app_role() = 'admin');

-- ===========================================================================
-- 6 + 8. Durée cible, lien conducteur -> créneau, modèles de conducteur
-- ===========================================================================
alter table public.broadcast_slots
  add column duration_seconds integer check (duration_seconds is null or duration_seconds > 0);

alter table public.conductors
  add column target_duration integer check (target_duration is null or target_duration > 0),
  add column slot_id uuid references public.broadcast_slots (id) on delete set null;

update public.conductors c
set slot_id = s.id, target_duration = s.duration_seconds
from public.broadcast_slots s
where s.title = c.title and s.broadcast_time = c.broadcast_time and c.slot_id is null;

create table public.slot_template_lines (
  id               uuid primary key default gen_random_uuid(),
  slot_id          uuid not null references public.broadcast_slots (id) on delete cascade,
  position_index   integer not null check (position_index >= 1),
  item_type        public.line_item_type not null default 'other',
  title            text not null,
  planned_duration integer check (planned_duration is null or planned_duration >= 0),
  unique (slot_id, position_index)
);

alter table public.slot_template_lines enable row level security;
create policy slot_template_lines_select on public.slot_template_lines
  for select to authenticated using (true);
create policy slot_template_lines_admin_write on public.slot_template_lines
  for all to authenticated
  using ((select public.app_role()) = 'admin') with check ((select public.app_role()) = 'admin');

-- Les conducteurs générés reprennent la durée cible et les lignes types de leur créneau.
create or replace function public.generate_conductors(p_date date)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer;
begin
  with new_c as (
    insert into public.conductors (title, broadcast_date, broadcast_time, created_by, slot_id, target_duration)
    select s.title, p_date, s.broadcast_time, auth.uid(), s.id, s.duration_seconds
    from public.broadcast_slots s
    where s.active
      and extract(isodow from p_date)::smallint = any (s.weekdays)
    on conflict (broadcast_date, title) do nothing
    returning id, slot_id
  ),
  new_lines as (
    insert into public.conductor_lines (conductor_id, position_index, title, item_type, planned_duration)
    select n.id, t.position_index, t.title, t.item_type, t.planned_duration
    from new_c n
    join public.slot_template_lines t on t.slot_id = n.slot_id
    returning 1
  )
  select count(*) into v_count from new_c;
  return v_count;
end;
$$;

-- Enregistre les lignes d'un conducteur comme modèle de son créneau (remplace le modèle précédent).
create or replace function public.save_conductor_as_template(p_conductor_id uuid)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_slot uuid;
  v_count integer;
begin
  if public.app_role() is distinct from 'admin' then
    raise exception 'Réservé au rédacteur en chef';
  end if;
  select slot_id into v_slot from public.conductors where id = p_conductor_id;
  if v_slot is null then
    raise exception 'Ce conducteur n''est pas rattaché à un créneau de la grille';
  end if;

  delete from public.slot_template_lines where slot_id = v_slot;
  insert into public.slot_template_lines (slot_id, position_index, item_type, title, planned_duration)
  select v_slot,
         row_number() over (order by position_index),
         item_type, title, planned_duration
  from public.conductor_lines
  where conductor_id = p_conductor_id and status <> 'dropped';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.save_conductor_as_template(uuid) from public, anon;

-- ===========================================================================
-- 7. Texte à lire à l'antenne
-- ===========================================================================
alter table public.conductor_lines
  add column script text check (script is null or char_length(script) <= 20000);

-- Journalistes et rédacteur en chef écrivent le texte; après verrouillage, seul le rédacteur en chef.
create or replace function public.set_line_script(p_line_id uuid, p_script text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conductor uuid;
begin
  if public.app_role() not in ('admin', 'journalist') then
    raise exception 'Réservé aux journalistes et au rédacteur en chef';
  end if;
  select conductor_id into v_conductor from public.conductor_lines where id = p_line_id;
  if v_conductor is null then raise exception 'Ligne introuvable'; end if;
  if public.app_role() <> 'admin' and public.conductor_is_locked(v_conductor) then
    raise exception 'Ce conducteur est verrouillé : le texte ne se modifie plus';
  end if;
  update public.conductor_lines
  set script = nullif(btrim(p_script), '')
  where id = p_line_id;
end;
$$;

revoke execute on function public.set_line_script(uuid, text) from public, anon;

-- ===========================================================================
-- 12. Historique des modifications d'un conducteur
-- ===========================================================================
create table public.conductor_history (
  id           bigint generated always as identity primary key,
  conductor_id uuid not null,
  line_id      uuid,
  user_id      uuid,
  summary      text not null,
  created_at   timestamptz not null default now()
);

create index conductor_history_conductor_idx on public.conductor_history (conductor_id, created_at desc);

alter table public.conductor_history enable row level security;
create policy conductor_history_select on public.conductor_history
  for select to authenticated using (true);
-- aucune politique d'écriture : seuls les déclencheurs ci-dessous écrivent

create or replace function public.log_conductor_history(p_conductor uuid, p_line uuid, p_summary text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- suppression en cascade d'un conducteur : plus rien à historiser
  if exists (select 1 from public.conductors where id = p_conductor) then
    insert into public.conductor_history (conductor_id, line_id, user_id, summary)
    values (p_conductor, p_line, auth.uid(), p_summary);
  end if;
end;
$$;

create or replace function public.log_line_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_conductor_history(new.conductor_id, new.id,
      format('Ligne %s ajoutée : %s', new.position_index, new.title));
  elsif tg_op = 'DELETE' then
    perform public.log_conductor_history(old.conductor_id, null,
      format('Ligne %s supprimée : %s', old.position_index, old.title));
  else
    if new.position_index is distinct from old.position_index then
      perform public.log_conductor_history(new.conductor_id, new.id,
        format('« %s » déplacée : position %s → %s', new.title, old.position_index, new.position_index));
    end if;
    if new.status is distinct from old.status then
      perform public.log_conductor_history(new.conductor_id, new.id,
        format('« %s » : statut %s → %s', new.title, old.status, new.status));
    end if;
    if new.title is distinct from old.title or new.planned_duration is distinct from old.planned_duration
       or new.item_type is distinct from old.item_type then
      perform public.log_conductor_history(new.conductor_id, new.id,
        format('Ligne %s modifiée : %s', new.position_index, new.title));
    end if;
    if new.script is distinct from old.script then
      perform public.log_conductor_history(new.conductor_id, new.id,
        format('Texte de « %s » modifié', new.title));
    end if;
  end if;
  return null;
end;
$$;

create trigger conductor_lines_log_history
  after insert or update or delete on public.conductor_lines
  for each row execute function public.log_line_change();

create or replace function public.log_conductor_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    perform public.log_conductor_history(new.id, null,
      format('Conducteur : statut %s → %s', old.status, new.status));
  end if;
  return null;
end;
$$;

create trigger conductors_log_history
  after update on public.conductors
  for each row execute function public.log_conductor_change();

create or replace function public.log_sound_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conductor uuid;
  v_thread uuid;
  v_path text;
  v_name text;
begin
  v_path := case when tg_op = 'DELETE' then old.audio_file_url else new.audio_file_url end;
  if v_path is null then return null; end if;
  v_thread := case when tg_op = 'DELETE' then old.thread_id else new.thread_id end;
  select l.conductor_id into v_conductor
  from public.discussion_threads t
  join public.conductor_lines l on l.id = t.conductor_line_id
  where t.id = v_thread;
  if v_conductor is null then return null; end if;
  v_name := regexp_replace(v_path, '^.*/', '');
  if tg_op = 'INSERT' then
    perform public.log_conductor_history(v_conductor, null, format('Son ajouté : %s', v_name));
  elsif tg_op = 'DELETE' then
    perform public.log_conductor_history(v_conductor, null, format('Son supprimé : %s', v_name));
  end if;
  return null;
end;
$$;

create trigger messages_log_sound_history
  after insert or delete on public.messages
  for each row execute function public.log_sound_change();

revoke execute on function public.log_conductor_history(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.log_line_change() from public, anon, authenticated;
revoke execute on function public.log_conductor_change() from public, anon, authenticated;
revoke execute on function public.log_sound_change() from public, anon, authenticated;

-- ===========================================================================
-- 13. Suppléance temporaire : le super administrateur désigne un suppléant jusqu'à une date.
--     Pendant ce temps, le suppléant a les droits du rédacteur en chef (hors gestion de l'équipe).
-- ===========================================================================
alter table public.users add column deputy_until timestamptz;

create or replace function public.app_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select case
    when deputy_until is not null and deputy_until > now() and active then 'admin'::public.user_role
    else role
  end
  from public.users where id = auth.uid();
$$;

-- Seul set_deputy peut écrire la suppléance (la mise à jour de son propre profil ne la touche pas).
create or replace function public.protect_deputy_column()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and new.deputy_until is distinct from old.deputy_until
     and current_setting('app.deputy_write', true) is distinct from 'on' then
    raise exception 'La suppléance se désigne depuis l''écran Équipe';
  end if;
  return new;
end;
$$;

create trigger users_protect_deputy
  before update on public.users
  for each row execute function public.protect_deputy_column();

revoke execute on function public.protect_deputy_column() from public, anon, authenticated;

create or replace function public.set_deputy(p_user uuid, p_until timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Réservé au super administrateur';
  end if;
  if p_until is not null and (p_until <= now() or p_until > now() + interval '90 days') then
    raise exception 'La suppléance doit se terminer dans les 90 prochains jours';
  end if;
  if not exists (select 1 from public.users where id = p_user and active and role <> 'admin') then
    raise exception 'Choisissez un membre actif qui n''est pas déjà rédacteur en chef';
  end if;
  perform set_config('app.deputy_write', 'on', true);
  update public.users set deputy_until = p_until where id = p_user;
end;
$$;

revoke execute on function public.set_deputy(uuid, timestamptz) from public, anon;

-- ===========================================================================
-- 1. Notifications dans l'application
-- ===========================================================================
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users (id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text,
  ref_type   text,
  ref_id     uuid,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;
create policy notifications_select_own on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
-- lecture : uniquement via mark_notifications_read (pas d'écriture directe)

create or replace function public.mark_notifications_read()
returns void
language sql
security definer
set search_path = public
as $$
  update public.notifications set read_at = now()
  where user_id = auth.uid() and read_at is null;
$$;

revoke execute on function public.mark_notifications_read() from public, anon;

create or replace function public.notify_admins(p_except uuid, p_kind text, p_title text, p_body text, p_ref_type text, p_ref uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, kind, title, body, ref_type, ref_id)
  select u.id, p_kind, p_title, p_body, p_ref_type, p_ref
  from public.users u
  where u.active
    and (u.role = 'admin' or (u.deputy_until is not null and u.deputy_until > now()))
    and u.id is distinct from p_except;
$$;

create or replace function public.notify_proposal_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.notify_admins(new.author_id, 'proposal.new', 'Nouveau sujet proposé', new.title, 'proposal', new.id);
  elsif new.status is distinct from old.status and new.status in ('approved', 'rejected') then
    insert into public.notifications (user_id, kind, title, body, ref_type, ref_id)
    values (
      new.author_id,
      'proposal.' || new.status,
      case new.status when 'approved' then 'Sujet validé' else 'Sujet refusé' end,
      new.title, 'proposal', new.id
    );
  end if;
  return null;
end;
$$;

create trigger forum_proposals_notify
  after insert or update of status on public.forum_proposals
  for each row execute function public.notify_proposal_events();

create or replace function public.notify_new_sound()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.audio_file_url is not null then
    perform public.notify_admins(new.user_id, 'sound.new', 'Nouveau son reçu',
      regexp_replace(new.audio_file_url, '^.*/', ''), 'message', new.id);
  end if;
  return null;
end;
$$;

create trigger messages_notify_sound
  after insert on public.messages
  for each row execute function public.notify_new_sound();

revoke execute on function public.notify_admins(uuid, text, text, text, text, uuid) from public, anon, authenticated;
revoke execute on function public.notify_proposal_events() from public, anon, authenticated;
revoke execute on function public.notify_new_sound() from public, anon, authenticated;

-- Jetons d'appareil (préparation des notifications push FCM / APNs)
create table public.device_tokens (
  token      text primary key,
  user_id    uuid not null references public.users (id) on delete cascade,
  platform   text not null check (platform in ('android', 'ios', 'macos', 'windows', 'web')),
  updated_at timestamptz not null default now()
);

alter table public.device_tokens enable row level security;
create policy device_tokens_own on public.device_tokens
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.notifications;
