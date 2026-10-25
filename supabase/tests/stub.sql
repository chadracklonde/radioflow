-- Simulacre minimal des schémas gérés par Supabase (auth, storage, rôles), pour tester
-- les migrations sur un PostgreSQL ordinaire (CI). Ne sert jamais sur le vrai projet.
create schema auth;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable
  as $$ select nullif(current_setting('app.uid', true), '')::uuid $$;

create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint);
create table storage.objects (id uuid default gen_random_uuid(), bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
create function storage.foldername(n text) returns text[] language sql
  as $$ select string_to_array(n, '/') $$;

create role anon nologin;
create role authenticated nologin;
create publication supabase_realtime;
