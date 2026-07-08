#!/bin/bash
# Runs once on an EMPTY data dir via the supabase/postgres entrypoint.
#
# Two hard-won gotchas baked in:
#  1. This image bootstraps as `supabase_admin`, NOT `postgres`. Connect as it.
#  2. psql `:'pw'` variables do NOT interpolate inside a `DO $$ ... $$` block
#     (the dollar-quoted body is opaque to client-side substitution). So roles
#     are CREATEd passwordless inside DO, then given passwords via top-level
#     ALTER statements outside the block.
set -euo pipefail

SUPERUSER="${POSTGRES_USER:-supabase_admin}"
DB="${POSTGRES_DB:-postgres}"

psql -v ON_ERROR_STOP=1 -U "$SUPERUSER" -d "$DB" -v pw="$POSTGRES_PASSWORD" <<-'EOSQL'
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_auth_admin') THEN
        CREATE ROLE supabase_auth_admin NOINHERIT LOGIN CREATEROLE; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_storage_admin') THEN
        CREATE ROLE supabase_storage_admin NOINHERIT LOGIN CREATEROLE; END IF;
    END $$;

    ALTER ROLE authenticator          WITH LOGIN PASSWORD :'pw';
    ALTER ROLE supabase_auth_admin     WITH LOGIN PASSWORD :'pw';
    ALTER ROLE supabase_storage_admin  WITH LOGIN PASSWORD :'pw';
    ALTER ROLE supabase_admin          WITH LOGIN PASSWORD :'pw';

    GRANT anon, authenticated, service_role TO authenticator;

    CREATE SCHEMA IF NOT EXISTS auth    AUTHORIZATION supabase_auth_admin;
    CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;
    CREATE SCHEMA IF NOT EXISTS _realtime;
    CREATE SCHEMA IF NOT EXISTS realtime;

    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
