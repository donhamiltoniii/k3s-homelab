#!/bin/bash
# Runs once on an EMPTY data dir. The supabase/postgres entrypoint executes
# *.sh files in docker-entrypoint-initdb.d with env vars available, so we can
# safely reference $POSTGRES_PASSWORD here (unlike a raw .sql file).
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v pw="$POSTGRES_PASSWORD" <<-'EOSQL'
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
      END IF;
    END
    $$;
EOSQL

# Roles WITH passwords: run separately so :'pw' is interpolated by psql, not
# swallowed by the dollar-quoted DO block above. LOGIN roles use ALTER to be
# idempotent if the image's own migrations already created them.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v pw="$POSTGRES_PASSWORD" <<-'EOSQL'
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD :'pw';
      ELSE
        ALTER ROLE authenticator WITH LOGIN PASSWORD :'pw';
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
        CREATE ROLE supabase_auth_admin NOINHERIT LOGIN PASSWORD :'pw' CREATEROLE;
      ELSE
        ALTER ROLE supabase_auth_admin WITH LOGIN PASSWORD :'pw';
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
        CREATE ROLE supabase_storage_admin NOINHERIT LOGIN PASSWORD :'pw' CREATEROLE;
      ELSE
        ALTER ROLE supabase_storage_admin WITH LOGIN PASSWORD :'pw';
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin LOGIN SUPERUSER PASSWORD :'pw';
      ELSE
        ALTER ROLE supabase_admin WITH LOGIN SUPERUSER PASSWORD :'pw';
      END IF;
    END
    $$;

    GRANT anon, authenticated, service_role TO authenticator;

    CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
    CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;
    CREATE SCHEMA IF NOT EXISTS _realtime;
    CREATE SCHEMA IF NOT EXISTS realtime;

    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
