-- Radio Flow : schéma initial
-- Tables : users, conductors, conductor_lines, discussion_threads, messages, tasks
-- Le Forum (propositions de sujets) n'est pas dans ce lot : il fera l'objet d'une migration dédiée.

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('admin', 'journalist', 'technician');
create type public.conductor_status as enum ('draft', 'open', 'locked', 'aired');
create type public.line_item_type as enum (
  'jingle', 'intro', 'reportage', 'interview', 'brief', 'chronicle', 'weather', 'ad', 'outro', 'other'
);
create type public.line_status as enum ('planned', 'in_progress', 'ready', 'aired', 'dropped');
create type public.task_status as enum ('todo', 'reporting', 'writing', 'editing', 'review', 'done');

-- ---------------------------------------------------------------------------
-- Fonctions utilitaires
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- users : profil applicatif lié à auth.users
-- ---------------------------------------------------------------------------
create table public.users (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null,
  email       text not null unique,
  role        public.user_role not null default 'journalist',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger users_set_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();

-- Rôle de l'utilisateur courant (security definer pour éviter la récursion RLS)
create or replace function public.app_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.users where id = auth.uid();
$$;

-- Création automatique du profil à l'inscription (rôle par défaut : journalist)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, full_name, email)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(new.email, '@', 1)),
    new.email
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Seul un admin peut modifier un rôle (empêche l'auto-promotion)
create or replace function public.prevent_role_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() nul = éditeur SQL / service role : autorisé (promotion du premier admin)
  if new.role is distinct from old.role and auth.uid() is not null
     and coalesce(public.app_role(), 'technician') <> 'admin' then
    raise exception 'Seul un administrateur peut modifier un rôle';
  end if;
  return new;
end;
$$;

create trigger users_prevent_role_escalation
  before update on public.users
  for each row execute function public.prevent_role_escalation();

-- ---------------------------------------------------------------------------
-- conductors : éditions quotidiennes (Flash de 07h, Journal de 12h...)
-- ---------------------------------------------------------------------------
create table public.conductors (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  broadcast_date date not null,
  broadcast_time time,
  status         public.conductor_status not null default 'draft',
  created_by     uuid references public.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (broadcast_date, title)
);

create index conductors_broadcast_date_idx on public.conductors (broadcast_date desc);

create trigger conductors_set_updated_at
  before update on public.conductors
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- conductor_lines : blocs du conducteur, minute par minute
-- ---------------------------------------------------------------------------
create table public.conductor_lines (
  id                uuid primary key default gen_random_uuid(),
  conductor_id      uuid not null references public.conductors (id) on delete cascade,
  position_index    integer not null check (position_index >= 0),
  item_type         public.line_item_type not null default 'other',
  title             text not null,
  status            public.line_status not null default 'planned',
  assigned_to       uuid references public.users (id) on delete set null,
  planned_duration  integer check (planned_duration is null or planned_duration >= 0), -- secondes
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (conductor_id, position_index) deferrable initially deferred
);

create index conductor_lines_conductor_idx on public.conductor_lines (conductor_id, position_index);
create index conductor_lines_assigned_idx on public.conductor_lines (assigned_to);

create trigger conductor_lines_set_updated_at
  before update on public.conductor_lines
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- discussion_threads : un fil (style Teams) par ligne du conducteur
-- ---------------------------------------------------------------------------
create table public.discussion_threads (
  id                 uuid primary key default gen_random_uuid(),
  conductor_line_id  uuid not null unique references public.conductor_lines (id) on delete cascade,
  created_at         timestamptz not null default now()
);

-- Création automatique du fil à l'insertion d'une ligne
create or replace function public.create_thread_for_line()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.discussion_threads (conductor_line_id) values (new.id);
  return new;
end;
$$;

create trigger conductor_lines_create_thread
  after insert on public.conductor_lines
  for each row execute function public.create_thread_for_line();

-- ---------------------------------------------------------------------------
-- messages : texte et/ou audio uploadé dans un fil
-- ---------------------------------------------------------------------------
create table public.messages (
  id                 uuid primary key default gen_random_uuid(),
  thread_id          uuid not null references public.discussion_threads (id) on delete cascade,
  user_id            uuid not null references public.users (id) on delete cascade,
  content            text,
  audio_file_url     text,      -- chemin dans le bucket « conductor-audio »
  audio_original_name text,     -- nom d'origine avant renommage
  audio_duration     integer check (audio_duration is null or audio_duration >= 0), -- secondes
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (content is not null or audio_file_url is not null)
);

create index messages_thread_idx on public.messages (thread_id, created_at);
create index messages_user_idx on public.messages (user_id);

create trigger messages_set_updated_at
  before update on public.messages
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- tasks : tâches individuelles, visibles par toute l'équipe
-- ---------------------------------------------------------------------------
create table public.tasks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  title       text not null,
  status      public.task_status not null default 'todo',
  due_date    date,
  completed_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index tasks_user_status_idx on public.tasks (user_id, status);
create index tasks_due_date_idx on public.tasks (due_date);

create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function public.set_updated_at();

create or replace function public.set_task_completed_at()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'done' and old.status is distinct from 'done' then
    new.completed_at = now();
  elsif new.status <> 'done' then
    new.completed_at = null;
  end if;
  return new;
end;
$$;

create trigger tasks_set_completed_at
  before update on public.tasks
  for each row execute function public.set_task_completed_at();

-- ---------------------------------------------------------------------------
-- Nommage automatique des fichiers audio
-- Format : [Position]_[Nom_Original]_[Date_Du_Jour].[ext]
-- Exemple : 03_Reportage_Marche_2026-09-09.mp3
-- ---------------------------------------------------------------------------
create or replace function public.audio_stored_name(
  p_position integer,
  p_original_name text,
  p_date date default current_date
)
returns text
language plpgsql
immutable
as $$
declare
  v_ext  text := lower(substring(p_original_name from '\.([A-Za-z0-9]+)$'));
  v_base text := regexp_replace(p_original_name, '\.[A-Za-z0-9]+$', '');
begin
  -- retire les accents, remplace tout caractère non alphanumérique par « _ »
  v_base := translate(v_base,
    'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ',
    'aaaeeeeiioouuucAAAEEEEIIOOUUUC');
  v_base := trim(both '_' from regexp_replace(v_base, '[^A-Za-z0-9]+', '_', 'g'));
  if v_base = '' then
    v_base := 'audio';
  end if;
  return lpad(p_position::text, 2, '0') || '_' || v_base || '_' || to_char(p_date, 'YYYY-MM-DD')
         || case when v_ext is null then '' else '.' || v_ext end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.users              enable row level security;
alter table public.conductors         enable row level security;
alter table public.conductor_lines    enable row level security;
alter table public.discussion_threads enable row level security;
alter table public.messages           enable row level security;
alter table public.tasks              enable row level security;

-- users
create policy users_select on public.users
  for select to authenticated using (true);
create policy users_update_self on public.users
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy users_update_admin on public.users
  for update to authenticated using (public.app_role() = 'admin') with check (true);

-- conductors : lecture pour tous, écriture admin
create policy conductors_select on public.conductors
  for select to authenticated using (true);
create policy conductors_admin_write on public.conductors
  for all to authenticated
  using (public.app_role() = 'admin') with check (public.app_role() = 'admin');

-- conductor_lines : lecture pour tous, écriture admin
create policy conductor_lines_select on public.conductor_lines
  for select to authenticated using (true);
create policy conductor_lines_admin_write on public.conductor_lines
  for all to authenticated
  using (public.app_role() = 'admin') with check (public.app_role() = 'admin');

-- discussion_threads : lecture pour tous (création par trigger)
create policy discussion_threads_select on public.discussion_threads
  for select to authenticated using (true);

-- messages : toute l'équipe lit et écrit ; modification/suppression par l'auteur ou un admin
create policy messages_select on public.messages
  for select to authenticated using (true);
create policy messages_insert on public.messages
  for insert to authenticated with check (user_id = auth.uid());
create policy messages_update on public.messages
  for update to authenticated
  using (user_id = auth.uid() or public.app_role() = 'admin')
  with check (user_id = auth.uid() or public.app_role() = 'admin');
create policy messages_delete on public.messages
  for delete to authenticated
  using (user_id = auth.uid() or public.app_role() = 'admin');

-- tasks : visibles par tous ; chacun gère les siennes, l'admin gère toutes
create policy tasks_select on public.tasks
  for select to authenticated using (true);
create policy tasks_insert on public.tasks
  for insert to authenticated with check (user_id = auth.uid() or public.app_role() = 'admin');
create policy tasks_update on public.tasks
  for update to authenticated
  using (user_id = auth.uid() or public.app_role() = 'admin')
  with check (user_id = auth.uid() or public.app_role() = 'admin');
create policy tasks_delete on public.tasks
  for delete to authenticated
  using (user_id = auth.uid() or public.app_role() = 'admin');

-- ---------------------------------------------------------------------------
-- Temps réel (WebSockets)
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table
  public.conductors, public.conductor_lines, public.messages, public.tasks;

-- ---------------------------------------------------------------------------
-- Stockage audio : bucket privé « conductor-audio »
-- Chemin attendu : {conductor_id}/{nom_renommé}
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('conductor-audio', 'conductor-audio', false, 52428800) -- 50 Mo (limite du plan gratuit)
on conflict (id) do nothing;

create policy conductor_audio_read on storage.objects
  for select to authenticated using (bucket_id = 'conductor-audio');
create policy conductor_audio_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'conductor-audio' and public.app_role() in ('admin', 'journalist'));
create policy conductor_audio_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'conductor-audio' and (owner = auth.uid() or public.app_role() = 'admin'));
