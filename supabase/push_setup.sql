-- Radio Flow : appel de la fonction « send-push » à chaque nouvelle notification.
-- À exécuter une fois sur le projet Supabase (pg_net est une extension propre à Supabase :
-- ce fichier n'est donc pas dans supabase/migrations, testées sur un PostgreSQL ordinaire).
--
-- La fonction send-push est déployée sans vérification de JWT (la passerelle Supabase refusait la
-- clé publique du projet). Elle ne risque rien : elle ne reçoit qu'un identifiant de notification
-- (uuid impossible à deviner, invisible sans compte), relit tout dans la base et n'envoie chaque
-- notification qu'une seule fois (colonne pushed_at).

create extension if not exists pg_net;

create or replace function public.push_new_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform net.http_post(
      url := 'https://yjzzgduvoirjvhfjfszz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object('id', new.id)
    );
  exception when others then
    -- une panne d'envoi ne doit jamais empêcher de créer la notification
    null;
  end;
  return null;
end;
$$;

revoke execute on function public.push_new_notification() from public, anon, authenticated;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
  after insert on public.notifications
  for each row execute function public.push_new_notification();
