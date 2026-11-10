-- =====================================================================
-- Run as the postgres superuser (pgAdmin Query Tool or psql), connected to salesdb.
-- Creates a READ-ONLY role for the dashboard: least-privilege security practice.
-- Change the password before using it anywhere real!
-- Replace sales_user below if your owner role has a different name.
-- Run it AFTER scripts/load_database.py (it grants on existing tables) - the
-- DEFAULT PRIVILEGES line keeps the grant alive when the tables are rebuilt later.
-- =====================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bi_readonly') THEN
        CREATE ROLE bi_readonly LOGIN PASSWORD 'change_me_readonly';
    END IF;
END $$;

GRANT CONNECT ON DATABASE salesdb TO bi_readonly;
GRANT USAGE   ON SCHEMA public   TO bi_readonly;
GRANT SELECT  ON ALL TABLES IN SCHEMA public TO bi_readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE sales_user IN SCHEMA public GRANT SELECT ON TABLES TO bi_readonly;
