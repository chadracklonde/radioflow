-- Radio Flow : optimisation des règles d'accès (conseiller de performance Supabase)
-- (select auth.uid()) est évalué une seule fois par requête au lieu d'une fois par ligne.
-- alter policy : aucune règle n'est supprimée, le comportement est identique.

alter policy users_update_self on public.users
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

alter policy messages_insert on public.messages
  with check (user_id = (select auth.uid()));
alter policy messages_update on public.messages
  using (user_id = (select auth.uid()) or public.app_role() = 'admin')
  with check (user_id = (select auth.uid()) or public.app_role() = 'admin');
alter policy messages_delete on public.messages
  using (user_id = (select auth.uid()) or public.app_role() = 'admin');

alter policy tasks_insert on public.tasks
  with check (user_id = (select auth.uid()) or public.app_role() = 'admin');
alter policy tasks_update on public.tasks
  using (user_id = (select auth.uid()) or public.app_role() = 'admin')
  with check (user_id = (select auth.uid()) or public.app_role() = 'admin');
alter policy tasks_delete on public.tasks
  using (user_id = (select auth.uid()) or public.app_role() = 'admin');

alter policy forum_proposals_insert on public.forum_proposals
  with check (
    author_id = (select auth.uid())
    and status = 'pending'
    and public.app_role() in ('admin', 'journalist')
  );
alter policy forum_proposals_update on public.forum_proposals
  using (author_id = (select auth.uid()) or public.app_role() = 'admin')
  with check (author_id = (select auth.uid()) or public.app_role() = 'admin');
alter policy forum_proposals_delete on public.forum_proposals
  using ((author_id = (select auth.uid()) and status = 'pending') or public.app_role() = 'admin');

-- Clés étrangères sans index
create index if not exists conductors_created_by_idx on public.conductors (created_by);
create index if not exists forum_proposals_decided_by_idx on public.forum_proposals (decided_by);
