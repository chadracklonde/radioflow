-- Radio Flow : un fil de discussion dès la validation d'un sujet
--
-- Avant : un fil n'existait que pour une ligne du conducteur. Un sujet validé n'avait donc aucun
-- espace de discussion tant que le rédacteur en chef ne l'avait pas placé dans un conducteur.
-- Désormais : la validation crée le fil (texte, ouvert à toute l'équipe). Quand le sujet est placé
-- dans un conducteur, ce même fil se rattache à la ligne (historique conservé) et l'envoi de sons
-- devient possible.
--
-- Les règles d'accès sur les messages ne changent pas : tout utilisateur connecté peut écrire,
-- et modifier ses propres messages; aucune règle ne dépend du statut du sujet.

-- ---------------------------------------------------------------------------
-- Un fil appartient à une ligne du conducteur et/ou à un sujet du forum
-- ---------------------------------------------------------------------------
alter table public.discussion_threads
  alter column conductor_line_id drop not null,
  add column proposal_id uuid references public.forum_proposals (id) on delete cascade;

create unique index discussion_threads_proposal_idx on public.discussion_threads (proposal_id);

alter table public.discussion_threads
  add constraint discussion_threads_has_owner
  check (conductor_line_id is not null or proposal_id is not null);

-- La structure des fils reste réservée au rédacteur en chef (les messages, eux, sont ouverts à tous).
create policy discussion_threads_admin_write on public.discussion_threads
  for all to authenticated
  using (public.app_role() = 'admin') with check (public.app_role() = 'admin');

-- ---------------------------------------------------------------------------
-- Création du fil (idempotente) : à la validation d'un sujet
-- ---------------------------------------------------------------------------
create or replace function public.attach_proposal_thread(p_proposal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_thread uuid;
  v_line uuid;
begin
  select id into v_thread from public.discussion_threads where proposal_id = p_proposal_id;
  if v_thread is not null then
    return v_thread;
  end if;

  -- Sujet déjà placé sur une ligne (cas des données existantes) : on reprend le fil de la ligne.
  select conductor_line_id into v_line from public.forum_proposals where id = p_proposal_id;
  if v_line is not null then
    update public.discussion_threads set proposal_id = p_proposal_id
    where conductor_line_id = v_line and proposal_id is null
    returning id into v_thread;
  end if;

  if v_thread is null then
    insert into public.discussion_threads (proposal_id, conductor_line_id)
    values (
      p_proposal_id,
      case when v_line is not null
                and not exists (select 1 from public.discussion_threads where conductor_line_id = v_line)
           then v_line end
    )
    returning id into v_thread;
  end if;
  return v_thread;
end;
$$;

create or replace function public.create_thread_for_approved_proposal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'approved' and (tg_op = 'INSERT' or old.status is distinct from 'approved') then
    perform public.attach_proposal_thread(new.id);
  end if;
  return new;
end;
$$;

create trigger forum_proposals_create_thread
  after insert or update of status on public.forum_proposals
  for each row execute function public.create_thread_for_approved_proposal();

revoke execute on function public.attach_proposal_thread(uuid) from public, anon, authenticated;
revoke execute on function public.create_thread_for_approved_proposal() from public, anon, authenticated;

-- Sujets déjà validés avant cette migration
select public.attach_proposal_thread(id) from public.forum_proposals where status = 'approved';

-- ---------------------------------------------------------------------------
-- Supprimer une ligne du conducteur ne supprime pas la discussion d'un sujet
-- ---------------------------------------------------------------------------
create or replace function public.keep_proposal_thread_on_line_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.discussion_threads set conductor_line_id = null
  where conductor_line_id = old.id and proposal_id is not null;
  return old;
end;
$$;

create trigger conductor_lines_keep_proposal_thread
  before delete on public.conductor_lines
  for each row execute function public.keep_proposal_thread_on_line_delete();

revoke execute on function public.keep_proposal_thread_on_line_delete() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Placer un sujet validé dans le conducteur : le fil du sujet devient celui de la ligne
-- (les messages déjà écrits sur la ligne rejoignent le fil du sujet; rien n'est perdu)
-- ---------------------------------------------------------------------------
create or replace function public.link_proposal_to_line(p_proposal_id uuid, p_line_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.proposal_status;
  v_current_line uuid;
  v_proposal_thread uuid;
  v_line_thread uuid;
begin
  -- Contrôle explicite : sans lui, les règles d'accès feraient échouer les écritures en silence.
  if public.app_role() is distinct from 'admin' then
    raise exception 'Réservé au rédacteur en chef';
  end if;

  select status, conductor_line_id into v_status, v_current_line
  from public.forum_proposals where id = p_proposal_id;
  if not found then raise exception 'Sujet introuvable'; end if;
  if v_status <> 'approved' then raise exception 'Seul un sujet validé peut être placé au conducteur'; end if;
  if v_current_line is not null then raise exception 'Ce sujet est déjà placé au conducteur'; end if;

  select id into v_proposal_thread from public.discussion_threads where proposal_id = p_proposal_id;
  if v_proposal_thread is null then raise exception 'Fil du sujet introuvable'; end if;

  select id into v_line_thread from public.discussion_threads
  where conductor_line_id = p_line_id and proposal_id is null;
  if v_line_thread is null then raise exception 'Ligne introuvable ou déjà liée à un autre sujet'; end if;

  update public.messages set thread_id = v_proposal_thread where thread_id = v_line_thread;
  delete from public.discussion_threads where id = v_line_thread;
  update public.discussion_threads set conductor_line_id = p_line_id where id = v_proposal_thread;
  update public.forum_proposals set conductor_line_id = p_line_id where id = p_proposal_id;
  return v_proposal_thread;
end;
$$;

revoke execute on function public.link_proposal_to_line(uuid, uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- Les sons se rangent par conducteur : pas d'envoi tant que le sujet n'est pas placé dans un
-- conducteur. Le texte, lui, est libre dès la validation.
-- ---------------------------------------------------------------------------
create or replace function public.guard_locked_conductor_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conductor uuid;
begin
  if new.audio_file_url is null then
    return new;
  end if;

  select l.conductor_id into v_conductor
  from public.discussion_threads t
  join public.conductor_lines l on l.id = t.conductor_line_id
  where t.id = new.thread_id;

  if v_conductor is null then
    raise exception 'Ce sujet n''est pas encore placé dans un conducteur : l''envoi d''un son sera possible ensuite';
  end if;
  if public.app_role() = 'admin' then
    return new;
  end if;
  if public.conductor_is_locked(v_conductor) then
    raise exception 'Ce conducteur est verrouillé : plus d''upload audio';
  end if;
  return new;
end;
$$;
