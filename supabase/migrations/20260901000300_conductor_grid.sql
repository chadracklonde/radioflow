-- Radio Flow : grille de la station et fonctions du conducteur

-- ---------------------------------------------------------------------------
-- broadcast_slots : grille de la station (Flash de 07h, Journal de 12h...)
-- weekdays : jours ISO (1 = lundi ... 7 = dimanche)
-- ---------------------------------------------------------------------------
create table public.broadcast_slots (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  broadcast_time time not null,
  weekdays       smallint[] not null default '{1,2,3,4,5,6,7}'
                 check (weekdays <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(weekdays) > 0),
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (title, broadcast_time)
);

alter table public.broadcast_slots enable row level security;

create policy broadcast_slots_select on public.broadcast_slots
  for select to authenticated using (true);
create policy broadcast_slots_admin_write on public.broadcast_slots
  for all to authenticated
  using (public.app_role() = 'admin') with check (public.app_role() = 'admin');

-- ---------------------------------------------------------------------------
-- Génère les conducteurs d'une date d'après la grille (sans doublon).
-- Renvoie le nombre de conducteurs créés. Exécutée avec les droits de l'appelant (RLS : admin).
-- ---------------------------------------------------------------------------
create or replace function public.generate_conductors(p_date date)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into public.conductors (title, broadcast_date, broadcast_time, created_by)
  select s.title, p_date, s.broadcast_time, auth.uid()
  from public.broadcast_slots s
  where s.active
    and extract(isodow from p_date)::smallint = any (s.weekdays)
  on conflict (broadcast_date, title) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Ajoute une ligne en fin de conducteur (la position est calculée côté base)
-- ---------------------------------------------------------------------------
create or replace function public.add_conductor_line(
  p_conductor_id uuid,
  p_title text,
  p_item_type public.line_item_type default 'other',
  p_planned_duration integer default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- verrou sur le conducteur : deux ajouts simultanés ne prennent pas la même position
  perform 1 from public.conductors where id = p_conductor_id for update;
  insert into public.conductor_lines (conductor_id, position_index, title, item_type, planned_duration)
  select p_conductor_id,
         coalesce(max(position_index), 0) + 1,
         p_title, p_item_type, p_planned_duration
  from public.conductor_lines
  where conductor_id = p_conductor_id
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Échange la position de deux lignes du même conducteur
-- (la contrainte d'unicité est différée : l'échange passe en une seule instruction)
-- ---------------------------------------------------------------------------
create or replace function public.swap_conductor_lines(p_a uuid, p_b uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_same integer;
  v_updated integer;
begin
  select count(distinct conductor_id) into v_same
  from public.conductor_lines where id in (p_a, p_b);
  if v_same <> 1 then
    raise exception 'Les deux lignes doivent appartenir au même conducteur';
  end if;

  update public.conductor_lines l
  set position_index = o.position_index
  from public.conductor_lines o
  where l.id in (p_a, p_b) and o.id in (p_a, p_b) and o.id <> l.id;
  get diagnostics v_updated = row_count;
  if v_updated <> 2 then
    raise exception 'Échange refusé';
  end if;
end;
$$;

revoke execute on function public.generate_conductors(date) from public, anon;
revoke execute on function public.add_conductor_line(uuid, text, public.line_item_type, integer) from public, anon;
revoke execute on function public.swap_conductor_lines(uuid, uuid) from public, anon;
