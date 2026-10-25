-- Radio Flow : durcissement signalé par les conseillers de sécurité Supabase

-- Fonctions de déclencheurs : jamais appelables via l'API REST
revoke execute on function public.handle_new_user()                from public, anon, authenticated;
revoke execute on function public.prevent_role_escalation()        from public, anon, authenticated;
revoke execute on function public.create_thread_for_line()         from public, anon, authenticated;
revoke execute on function public.guard_forum_proposal_update()    from public, anon, authenticated;
revoke execute on function public.guard_locked_conductor_message() from public, anon, authenticated;

-- Fonctions utilisées par les politiques RLS : réservées aux utilisateurs connectés
revoke execute on function public.app_role()                  from public, anon;
revoke execute on function public.conductor_is_locked(uuid)   from public, anon;

-- Chemin de recherche figé
alter function public.set_updated_at()          set search_path = '';
alter function public.set_task_completed_at()   set search_path = '';
alter function public.audio_stored_name(integer, text, date) set search_path = '';
