-- Radio Flow : Forum (propositions de sujets) et verrouillage des conducteurs

-- ---------------------------------------------------------------------------
-- Forum
-- ---------------------------------------------------------------------------
create type public.proposal_format as enum ('article', 'interview', 'brief');
create type public.proposal_status as enum ('pending', 'approved', 'rejected', 'changes_requested');

create table public.forum_proposals (
  id                uuid primary key default gen_random_uuid(),
  author_id         uuid not null references public.users (id) on delete cascade,
  title             text not null,
  angle             text not null,
  format            public.proposal_format not null,
  source            text,
  status            public.proposal_status not null default 'pending',
  decision_note     text,
  decided_by        uuid references public.users (id) on delete set null,
  decided_at        timestamptz,
  conductor_line_id uuid unique references public.conductor_lines (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index forum_proposals_status_idx on public.forum_proposals (status, created_at desc);
create index forum_proposals_author_idx on public.forum_proposals (author_id);

create trigger forum_proposals_set_updated_at
  before update on public.forum_proposals
  for each row execute function public.set_updated_at();

-- Seul l'admin décide; l'auteur ne peut modifier que le contenu d'une proposition en attente
create or replace function public.guard_forum_proposal_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.app_role() = 'admin' then
    if new.status is distinct from old.status then
      new.decided_by = auth.uid();
      new.decided_at = now();
    end if;
    return new;
  end if;

  if old.status <> 'pending' and old.status <> 'changes_requested' then
    raise exception 'Une proposition décidée ne peut plus être modifiée';
  end if;
  if new.status is distinct from old.status
     or new.decision_note is distinct from old.decision_note
     or new.decided_by is distinct from old.decided_by
     or new.decided_at is distinct from old.decided_at
     or new.conductor_line_id is distinct from old.conductor_line_id
     or new.author_id is distinct from old.author_id then
    raise exception 'Seul le rédacteur en chef peut décider d''une proposition';
  end if;
  return new;
end;
$$;

create trigger forum_proposals_guard_update
  before update on public.forum_proposals
  for each row execute function public.guard_forum_proposal_update();

alter table public.forum_proposals enable row level security;

create policy forum_proposals_select on public.forum_proposals
  for select to authenticated using (true);
create policy forum_proposals_insert on public.forum_proposals
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and status = 'pending'
    and public.app_role() in ('admin', 'journalist')
  );
create policy forum_proposals_update on public.forum_proposals
  for update to authenticated
  using (author_id = auth.uid() or public.app_role() = 'admin')
  with check (author_id = auth.uid() or public.app_role() = 'admin');
create policy forum_proposals_delete on public.forum_proposals
  for delete to authenticated
  using ((author_id = auth.uid() and status = 'pending') or public.app_role() = 'admin');

alter publication supabase_realtime add table public.forum_proposals;

-- ---------------------------------------------------------------------------
-- Verrouillage des conducteurs
-- Un conducteur « locked » ou « aired » n'accepte plus de nouvel audio (sauf admin).
-- ---------------------------------------------------------------------------
create or replace function public.conductor_is_locked(p_conductor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select status in ('locked', 'aired') from public.conductors where id = p_conductor_id),
    false
  );
$$;

create or replace function public.guard_locked_conductor_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conductor uuid;
begin
  if new.audio_file_url is null or public.app_role() = 'admin' then
    return new;
  end if;
  select l.conductor_id into v_conductor
  from public.discussion_threads t
  join public.conductor_lines l on l.id = t.conductor_line_id
  where t.id = new.thread_id;

  if public.conductor_is_locked(v_conductor) then
    raise exception 'Ce conducteur est verrouillé : plus d''upload audio';
  end if;
  return new;
end;
$$;

create trigger messages_guard_locked_conductor
  before insert on public.messages
  for each row execute function public.guard_locked_conductor_message();

-- Même règle côté stockage : le premier dossier du chemin est l'identifiant du conducteur
alter policy conductor_audio_upload on storage.objects
  with check (
    bucket_id = 'conductor-audio'
    and public.app_role() in ('admin', 'journalist')
    and (
      public.app_role() = 'admin'
      or not public.conductor_is_locked(((storage.foldername(name))[1])::uuid)
    )
  );
