-- Radio Flow : notifications push
--
-- pushed_at : date d'envoi de la notification push. Posée de façon atomique par la fonction
-- serveur « send-push » : une notification n'est poussée qu'une seule fois.
-- (Le déclencheur qui appelle cette fonction se pose avec supabase/push_setup.sql : il demande
-- l'extension pg_net, propre à Supabase.)

alter table public.notifications add column pushed_at timestamptz;

-- Les notifications existantes ne seront pas poussées rétroactivement.
update public.notifications set pushed_at = now() where pushed_at is null;

-- Enregistrement d'un appareil : un même téléphone peut changer de compte. Le jeton passe au
-- compte connecté (une mise à jour directe serait refusée par les règles d'accès : le jeton
-- appartient encore à l'ancien compte).
create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), p_platform, now())
  on conflict (token) do update
    set user_id = auth.uid(), platform = excluded.platform, updated_at = now();
end;
$$;

revoke execute on function public.register_device_token(text, text) from public, anon;
