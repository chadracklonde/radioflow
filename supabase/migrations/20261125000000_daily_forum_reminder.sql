-- Radio Flow : rappel quotidien « n'oubliez pas de poster vos sujets »
-- Appelée une fois par jour par GitHub Actions (clé de service). Crée une notification
-- pour chaque membre ; le déclencheur notifications_push l'envoie ensuite en push.
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
    select 1 from public.notifications
    where kind = 'forum_reminder'
      and created_at >= date_trunc('day', now() at time zone 'Africa/Lubumbashi') at time zone 'Africa/Lubumbashi'
  ) then
    return 0;
  end if;

  insert into public.notifications (user_id, kind, title, body, ref_type)
  select u.id,
         'forum_reminder',
         'Bonjour à tous',
         'N''oubliez pas de poster vos sujets dans le forum.',
         'forum'
  from public.users u;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Réservée à la clé de service (service_role garde son droit par défaut sur Supabase)
revoke execute on function public.send_daily_forum_reminder() from public, anon, authenticated;
