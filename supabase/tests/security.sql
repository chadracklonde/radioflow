-- Tests de sécurité et de comportement de la base. Toute attente non satisfaite lève une erreur.
-- Exécutés par supabase/tests/run.sh sur un PostgreSQL jetable.
\set ON_ERROR_STOP on
\set QUIET on

create schema t;
grant usage on schema t to public;

-- Cette instruction doit être refusée (erreur, ou règle d'accès qui la bloque).
create function t.refused(stmt text, label text) returns void language plpgsql as $$
declare ok boolean := false;
begin
  begin execute stmt; exception when others then ok := true; end;
  if not ok then raise exception 'ECHEC (aurait du etre refuse) : %', label; end if;
  raise notice 'ok : %', label;
end $$;

-- Cette instruction ne doit toucher aucune ligne (refus silencieux par RLS).
create function t.touches_nothing(stmt text, label text) returns void language plpgsql as $$
declare n int;
begin
  execute stmt; get diagnostics n = row_count;
  if n <> 0 then raise exception 'ECHEC (%s lignes modifiees) : %', n, label; end if;
  raise notice 'ok : %', label;
end $$;

create function t.eq(actual text, expected text, label text) returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'ECHEC : % (obtenu %, attendu %)', label, actual, expected;
  end if;
  raise notice 'ok : %', label;
end $$;

grant execute on all functions in schema t to public;
grant usage on schema public, auth, storage to authenticated;
grant all on all tables in schema public to authenticated;
grant select, insert, delete on storage.objects to authenticated;
grant execute on all functions in schema public, auth, storage to authenticated;

-- Comptes : chef (super admin), redac (rédacteur en chef), awa (journaliste), tech (technicien)
insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'chef@rtc.ml',  '{"full_name":"Chef"}'),
  ('00000000-0000-0000-0000-00000000000b', 'redac@rtc.ml', '{"full_name":"Redac"}'),
  ('00000000-0000-0000-0000-00000000000c', 'awa@rtc.ml',   '{"full_name":"Awa"}'),
  ('00000000-0000-0000-0000-00000000000d', 'tech@rtc.ml',  '{}');
update public.users set role = 'admin' where email in ('chef@rtc.ml', 'redac@rtc.ml');
update public.users set role = 'technician' where email = 'tech@rtc.ml';
update public.users set is_super_admin = true where email = 'chef@rtc.ml';

select t.eq((select count(*)::text from public.users), '4', 'un profil est créé pour chaque compte');
select t.eq((select role::text from public.users where email = 'awa@rtc.ml'), 'journalist', 'rôle par défaut : journaliste');
select t.eq((select full_name from public.users where email = 'tech@rtc.ml'), 'tech', 'nom par défaut tiré de l''email');
select t.eq(public.audio_stored_name(3, 'Reportage Marché.MP3', '2026-09-09'), '03_Reportage_Marche_2026-09-09.mp3', 'nommage automatique des fichiers');

-- ======================= Super administrateur =======================
set role authenticated;
select set_config('app.uid', '00000000-0000-0000-0000-00000000000a', false);
update public.users set role = 'technician' where email = 'awa@rtc.ml';
select t.eq((select role::text from public.users where email = 'awa@rtc.ml'), 'technician', 'le super admin change un rôle');
update public.users set role = 'journalist' where email = 'awa@rtc.ml';
select t.refused($$update public.users set role = 'journalist' where id = auth.uid()$$, 'le super admin ne se rétrograde pas');
select t.refused($$update public.users set active = false where email = 'awa@rtc.ml'$$, 'l''état actif ne se change pas depuis le client');

select set_config('app.uid', '00000000-0000-0000-0000-00000000000b', false);
select t.touches_nothing($$update public.users set role = 'technician' where email = 'awa@rtc.ml'$$, 'un rédacteur en chef ordinaire ne change pas un rôle');
select t.refused($$update public.users set is_super_admin = true where id = auth.uid()$$, 'personne ne se promeut super admin');
select t.refused($$update public.users set role = 'journalist' where id = auth.uid()$$, 'un admin ordinaire ne change pas son propre rôle');
select t.touches_nothing($$update public.users set role = 'journalist' where email = 'chef@rtc.ml'$$, 'un admin ne rétrograde pas le super admin');

select set_config('app.uid', '00000000-0000-0000-0000-00000000000c', false);
select t.refused($$update public.users set role = 'admin' where id = auth.uid()$$, 'un journaliste ne se promeut pas');
select t.refused($$update public.users set email = 'autre@rtc.ml' where id = auth.uid()$$, 'personne ne modifie son email de profil');

reset role;
select set_config('app.uid', '', false);
select t.refused($$update public.users set is_super_admin = true where email = 'redac@rtc.ml'$$, 'un seul super admin (même depuis le serveur)');
select t.refused($$update public.users set active = false where email = 'chef@rtc.ml'$$, 'le super admin ne se désactive pas (même depuis le serveur)');
select t.refused($$update public.users set role = 'journalist' where email = 'chef@rtc.ml'$$, 'le super admin ne se rétrograde pas (même depuis le serveur)');

-- ======================= Conducteur, fils, audio, verrouillage =======================
set role authenticated;
select set_config('app.uid', '00000000-0000-0000-0000-00000000000c', false);
select t.refused($$insert into public.conductors (title, broadcast_date) values ('J', '2026-09-09')$$, 'un journaliste ne crée pas de conducteur');

select set_config('app.uid', '00000000-0000-0000-0000-00000000000b', false);
insert into public.broadcast_slots (title, broadcast_time) values ('Flash de 07h', '07:00'), ('Journal de 12h', '12:00');
select t.eq(public.generate_conductors('2026-09-09')::text, '2', 'génération des conducteurs depuis la grille');
select t.eq(public.generate_conductors('2026-09-09')::text, '0', 'la génération ne crée pas de doublon');
select id as cid from public.conductors where title = 'Journal de 12h' \gset
select public.add_conductor_line(:'cid', 'Générique', 'jingle', 15) \gset
select public.add_conductor_line(:'cid', 'Reportage', 'reportage', 120) as l2 \gset
select public.add_conductor_line(:'cid', 'Interview') as l3 \gset
select t.eq((select string_agg(title, ',' order by position_index) from public.conductor_lines where conductor_id = :'cid'), 'Générique,Reportage,Interview', 'positions automatiques');
select public.swap_conductor_lines(:'l2', :'l3');
select t.eq((select string_agg(title, ',' order by position_index) from public.conductor_lines where conductor_id = :'cid'), 'Générique,Interview,Reportage', 'échange de deux lignes');
select t.eq((select count(*)::text from public.discussion_threads), '3', 'un fil par ligne');
select id as th from public.discussion_threads limit 1 \gset

select set_config('app.uid', '00000000-0000-0000-0000-00000000000c', false);
select t.refused(format($$insert into public.messages (thread_id, user_id, content) values (%L, '00000000-0000-0000-0000-00000000000b', 'usurpation')$$, :'th'), 'on n''écrit pas au nom d''un autre');
insert into public.messages (thread_id, user_id, content) values (:'th', '00000000-0000-0000-0000-00000000000c', 'Bonjour');
insert into public.messages (thread_id, user_id, audio_file_url, audio_original_name)
  values (:'th', '00000000-0000-0000-0000-00000000000c', :'cid' || '/01_Test_2026-09-09.mp3', 'Test.mp3');
insert into storage.objects (bucket_id, name) values ('conductor-audio', :'cid' || '/01_Test_2026-09-09.mp3');
select t.eq((select count(*)::text from public.sound_files), '1', 'l''Espace Son liste le fichier');

select set_config('app.uid', '00000000-0000-0000-0000-00000000000d', false);
select t.refused($$insert into storage.objects (bucket_id, name) values ('conductor-audio', 'x/01_A_2026-09-09.mp3')$$, 'un technicien n''envoie pas d''audio');

select set_config('app.uid', '00000000-0000-0000-0000-00000000000b', false);
update public.conductors set status = 'locked' where id = :'cid';
select set_config('app.uid', '00000000-0000-0000-0000-00000000000c', false);
select t.refused(format($$insert into public.messages (thread_id, user_id, audio_file_url) values (%L, '00000000-0000-0000-0000-00000000000c', 'x.mp3')$$, :'th'), 'audio refusé sur conducteur verrouillé');
select t.refused(format($$insert into storage.objects (bucket_id, name) values ('conductor-audio', %L)$$, :'cid' || '/02_A_2026-09-09.mp3'), 'upload refusé sur conducteur verrouillé');
insert into public.messages (thread_id, user_id, content) values (:'th', '00000000-0000-0000-0000-00000000000c', 'texte permis');
select set_config('app.uid', '00000000-0000-0000-0000-00000000000b', false);
insert into storage.objects (bucket_id, name) values ('conductor-audio', :'cid' || '/02_Admin_2026-09-09.mp3');
select t.eq((select count(*)::text from storage.objects), '2', 'un admin peut encore envoyer sur un conducteur verrouillé');

-- ======================= Forum =======================
select set_config('app.uid', '00000000-0000-0000-0000-00000000000c', false);
insert into public.forum_proposals (author_id, title, angle, format) values (auth.uid(), 'Marché', 'angle', 'interview');
select t.refused($$update public.forum_proposals set status = 'approved'$$, 'auto-approbation refusée');
select set_config('app.uid', '00000000-0000-0000-0000-00000000000d', false);
select t.refused($$insert into public.forum_proposals (author_id, title, angle, format) values (auth.uid(), 'x', 'y', 'brief')$$, 'un technicien ne propose pas de sujet');
select set_config('app.uid', '00000000-0000-0000-0000-00000000000b', false);
update public.forum_proposals set status = 'approved', decision_note = 'ok';
select t.eq((select (decided_by is not null and decided_at is not null)::text from public.forum_proposals), 'true', 'décision tracée');
select set_config('app.uid', '00000000-0000-0000-0000-00000000000c', false);
select t.refused($$update public.forum_proposals set title = 'modif'$$, 'sujet décidé non modifiable par l''auteur');

-- ======================= Tâches et tableau de bord =======================
insert into public.tasks (user_id, title) values (auth.uid(), 'Monter le son');
select t.refused($$insert into public.tasks (user_id, title) values ('00000000-0000-0000-0000-00000000000b', 'au nom d''un autre')$$, 'tâche au nom d''un autre refusée');
update public.tasks set status = 'done';
select t.eq((select (completed_at is not null)::text from public.tasks), 'true', 'date de fin posée à la clôture');
select set_config('app.uid', '00000000-0000-0000-0000-00000000000d', false);
select t.touches_nothing($$update public.tasks set status = 'todo'$$, 'on ne modifie pas la tâche d''un autre');
select t.eq((select audio_count::text from public.production_stats(current_date, current_date) where full_name = 'Awa'), '1', 'classement : sons comptés');
select t.eq((select tasks_done::text from public.production_stats(current_date, current_date) where full_name = 'Awa'), '1', 'classement : tâches terminées comptées');
select t.eq((select count(*)::text from public.production_stats(current_date, current_date) where full_name = 'tech'), '0', 'classement : les techniciens n''y figurent pas');

-- ======================= Visiteur non connecté =======================
reset role;
set role anon;
select t.refused($$select * from public.tasks$$, 'un visiteur ne lit aucune table');
select t.refused($$select public.production_stats(current_date, current_date)$$, 'un visiteur n''appelle pas les statistiques');
select t.refused($$select public.app_role()$$, 'un visiteur n''appelle pas les fonctions internes');
reset role;

\echo TOUS LES TESTS DE LA BASE SONT PASSES
