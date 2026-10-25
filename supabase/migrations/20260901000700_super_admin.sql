-- Radio Flow : super administrateur
--
-- Le super administrateur est le seul à créer des comptes, attribuer des rôles et
-- désactiver des membres. Un rédacteur en chef (admin) garde ses pouvoirs éditoriaux
-- (décisions du Forum, conducteurs...) mais ne gère pas l'équipe.
-- Le statut de super administrateur ne se modifie que depuis le serveur / l'éditeur SQL.

alter table public.users add column is_super_admin boolean not null default false;

-- Un super administrateur est forcément un administrateur actif.
alter table public.users add constraint super_admin_is_active_admin
  check (not is_super_admin or (role = 'admin' and active));

-- Un seul super administrateur à la fois.
create unique index users_single_super_admin on public.users (is_super_admin) where is_super_admin;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_super_admin and active from public.users where id = auth.uid()), false);
$$;

revoke execute on function public.is_super_admin() from public, anon;

create or replace function public.prevent_role_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_other_admins integer;
begin
  -- auth.uid() nul = éditeur SQL / fonction serveur (clé de service) : les règles
  -- propres au serveur sont appliquées par la fonction manage-team.
  if auth.uid() is not null then
    if new.id is distinct from old.id or new.email is distinct from old.email then
      raise exception 'L''identifiant et l''email ne se modifient pas ici';
    end if;
    if new.is_super_admin is distinct from old.is_super_admin then
      raise exception 'Le statut de super administrateur ne se modifie que depuis le serveur';
    end if;
    if new.active is distinct from old.active then
      raise exception 'L''état actif d''un compte ne se modifie que depuis le serveur';
    end if;
    if new.role is distinct from old.role then
      if old.is_super_admin then
        raise exception 'Le compte super administrateur ne peut pas être rétrogradé';
      end if;
      if not public.is_super_admin() then
        raise exception 'Seul le super administrateur peut modifier un rôle';
      end if;
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

-- Les rôles se changent par le super administrateur seulement (le déclencheur le garantit aussi).
-- (alter policy plutôt que drop/create : on ne supprime rien.)
alter policy users_update_admin on public.users rename to users_update_super_admin;
alter policy users_update_super_admin on public.users
  using (public.is_super_admin()) with check (public.is_super_admin());

-- Premier super administrateur
update public.users set is_super_admin = true, role = 'admin', active = true
where email = 'chadracktambwe@gmail.com';
