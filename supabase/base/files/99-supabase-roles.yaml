#!/bin/bash
# Runs once on an EMPTY data dir via the supabase/postgres entrypoint.
#
# This reproduces the full role/grant foundation that the image's own
# init-scripts would normally lay down. Hard-won gotchas baked in:
#  1. This image bootstraps as `supabase_admin`, NOT `postgres`. Connect as it.
#  2. psql `:'pw'` does NOT interpolate inside a DO $$...$$ block, so password
#     assignment happens in top-level ALTER statements outside the block.
#  3. Every Supabase service migration assumes a `postgres` LOGIN role exists.
#     It must be created explicitly here (auth/storage/realtime all break
#     with `role "postgres" does not exist` otherwise).
#  4. realtime needs `supabase_realtime_admin` to own the _realtime/realtime
#     schemas and run its migrations + tenant seed.
set -euo pipefail

SUPERUSER="${POSTGRES_USER:-supabase_admin}"
DB="${POSTGRES_DB:-postgres}"

psql -v ON_ERROR_STOP=1 -U "$SUPERUSER" -d "$DB" -v pw="$POSTGRES_PASSWORD" <<-'EOSQL'
    -- === existence (no passwords inside the DO block) =====================
    DO $$
    BEGIN
      -- API / grant roles
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN; END IF;
      -- service admin roles
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_auth_admin') THEN
        CREATE ROLE supabase_auth_admin NOINHERIT LOGIN CREATEROLE; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_storage_admin') THEN
        CREATE ROLE supabase_storage_admin NOINHERIT LOGIN CREATEROLE; END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_realtime_admin') THEN
        CREATE ROLE supabase_realtime_admin NOINHERIT LOGIN CREATEROLE CREATEDB REPLICATION; END IF;
      -- the role every migration assumes exists
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='postgres') THEN
        CREATE ROLE postgres LOGIN CREATEDB CREATEROLE REPLICATION BYPASSRLS; END IF;
    END $$;

    -- === passwords (top-level so :'pw' interpolates) ======================
    ALTER ROLE authenticator            WITH LOGIN PASSWORD :'pw';
    ALTER ROLE supabase_auth_admin       WITH LOGIN PASSWORD :'pw';
    ALTER ROLE supabase_storage_admin    WITH LOGIN PASSWORD :'pw';
    ALTER ROLE supabase_realtime_admin   WITH LOGIN PASSWORD :'pw';
    ALTER ROLE supabase_admin            WITH LOGIN PASSWORD :'pw';
    ALTER ROLE postgres                  WITH LOGIN PASSWORD :'pw';

    -- === role membership ==================================================
    GRANT anon, authenticated, service_role TO authenticator;
    GRANT anon, authenticated, service_role TO postgres;
    GRANT anon, authenticated, service_role TO supabase_auth_admin, supabase_storage_admin;
    GRANT supabase_admin TO postgres;

    -- === schemas + ownership ==============================================
    CREATE SCHEMA IF NOT EXISTS auth      AUTHORIZATION supabase_auth_admin;
    CREATE SCHEMA IF NOT EXISTS storage   AUTHORIZATION supabase_storage_admin;
    CREATE SCHEMA IF NOT EXISTS _realtime AUTHORIZATION supabase_realtime_admin;
    CREATE SCHEMA IF NOT EXISTS realtime  AUTHORIZATION supabase_realtime_admin;

    ALTER SCHEMA auth      OWNER TO supabase_auth_admin;
    ALTER SCHEMA storage   OWNER TO supabase_storage_admin;
    ALTER SCHEMA _realtime OWNER TO supabase_realtime_admin;
    ALTER SCHEMA realtime  OWNER TO supabase_realtime_admin;

    -- === database + schema grants =========================================
    GRANT ALL ON DATABASE postgres
      TO supabase_auth_admin, supabase_storage_admin, supabase_realtime_admin, postgres;

    GRANT ALL   ON SCHEMA auth      TO supabase_auth_admin;
    GRANT ALL   ON SCHEMA storage   TO supabase_storage_admin;
    GRANT ALL   ON SCHEMA _realtime TO supabase_realtime_admin;
    GRANT ALL   ON SCHEMA realtime  TO supabase_realtime_admin;
    GRANT USAGE ON SCHEMA auth      TO supabase_storage_admin, anon, authenticated, service_role;
    GRANT ALL   ON SCHEMA public
      TO postgres, supabase_auth_admin, supabase_storage_admin, supabase_realtime_admin;

    -- === default privileges so API roles can use what supabase_admin makes =
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
      GRANT ALL ON TABLES    TO postgres, anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
      GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
      GRANT ALL ON FUNCTIONS  TO postgres, anon, authenticated, service_role;

    -- === extensions =======================================================
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
