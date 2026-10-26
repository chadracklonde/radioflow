-- Radio Flow : ajout de ligne rejouable (mode hors ligne)
--
-- L'application génère l'identifiant de la ligne avant l'envoi. Si la réponse du serveur se perd
-- et que l'envoi est rejoué au retour du réseau, la ligne existante est renvoyée : aucun doublon.
-- (Surcharge : l'ancienne fonction à 4 paramètres reste disponible.)

create or replace function public.add_conductor_line(
  p_conductor_id uuid,
  p_title text,
  p_item_type public.line_item_type,
  p_planned_duration integer,
  p_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- déjà créée par un envoi précédent
  select id into v_id from public.conductor_lines where id = p_id and conductor_id = p_conductor_id;
  if v_id is not null then
    return v_id;
  end if;

  perform 1 from public.conductors where id = p_conductor_id for update;
  insert into public.conductor_lines (id, conductor_id, position_index, title, item_type, planned_duration)
  select p_id,
         p_conductor_id,
         coalesce(max(position_index), 0) + 1,
         p_title, p_item_type, p_planned_duration
  from public.conductor_lines
  where conductor_id = p_conductor_id
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function public.add_conductor_line(uuid, text, public.line_item_type, integer, uuid) from public, anon;
