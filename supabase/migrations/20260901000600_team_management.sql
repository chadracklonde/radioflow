-- Radio Flow : gestion de l'équipe (membres actifs / désactivés, garde-fous sur les administrateurs)

alter table public.users add column active boolean not null default true;

-- Seul le serveur (fonction avec clé de service, auth.uid() nul) peut changer l'état « actif »,
-- et un seul administrateur ne peut pas être rétrogradé ou désactivé s'il est le dernier.
create or replace function public.prevent_role_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_other_admins integer;
begin
  -- auth.uid() nul = éditeur SQL / service role : autorisé (promotion du premier admin, fonctions serveur)
  if auth.uid() is not null then
    if new.role is distinct from old.role
       and coalesce(public.app_role(), 'technician') <> 'admin' then
      raise exception 'Seul un administrateur peut modifier un rôle';
    end if;
    if new.active is distinct from old.active then
      raise exception 'L''état actif d''un compte ne se modifie que depuis le serveur';
    end if;
  end if;

  if old.role = 'admin' and old.active
     and (new.role <> 'admin' or not new.active) then
    select count(*) into v_other_admins
    from public.users
    where role = 'admin' and active and id <> old.id;
    if v_other_admins = 0 then
      raise exception 'Il doit rester au moins un administrateur actif';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.prevent_role_escalation() from public, anon, authenticated;
