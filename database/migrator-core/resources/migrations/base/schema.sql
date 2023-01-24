-- This is the schema that will set up a new Postgres database for an Anvil server
-- (central or dedicated)
-- DO NOT run this to upgrade an existing server. Obviously.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE app_storage_tables (id integer primary key, 
                                 name text NOT NULL, 
                                 columns jsonb NOT NULL DEFAULT '{}');

CREATE TABLE app_storage_access (table_id integer references app_storage_tables(id), 
                                 python_name text NOT NULL, 
                                 server text not null, 
                                 client text not null);

CREATE TABLE app_storage_data (id serial, 
                               table_id integer references app_storage_tables(id), 
                               data jsonb NOT NULL DEFAULT '{}');
CREATE INDEX app_storage_data_idx ON app_storage_data (table_id,id);
CREATE INDEX app_storage_data_json_idx ON app_storage_data using gin (data jsonb_path_ops);

CREATE TABLE app_storage_media (object_id integer PRIMARY KEY NOT NULL,
                                content_type text,
                                name text,
                                row_id integer,
                                table_id integer,
                                column_id text);
CREATE INDEX app_storage_media_object_id_uindex ON app_storage_media (object_id);


-- https://stackoverflow.com/questions/10169309/get-size-of-large-object-in-postgresql-query/10171306#10171306
CREATE OR REPLACE FUNCTION get_lo_size(oid) RETURNS bigint
VOLATILE STRICT
LANGUAGE 'plpgsql'
AS $$
DECLARE
    fd integer;
    sz bigint;
BEGIN
    -- Open the LO; N.B. it needs to be in a transaction otherwise it will close immediately.
    -- Luckily a function invocation makes its own transaction if necessary.
    -- The mode x'40000'::int corresponds to the PostgreSQL LO mode INV_READ = 0x40000.
    fd := lo_open($1, x'40000'::int);
    -- Seek to the end.  2 = SEEK_END.
    PERFORM lo_lseek64(fd, 0, 2);
    -- Fetch the current file position; since we're at the end, this is the size.
    sz := lo_tell64(fd);
    -- Remember to close it, since the function may be called as part of a larger transaction.
    PERFORM lo_close(fd);
    -- Return the size.
    RETURN sz;
END;
$$; 

CREATE OR REPLACE FUNCTION parse_anvil_timestamp(ts text) RETURNS timestamptz AS $$
BEGIN
  return replace(regexp_replace(ts, '.(\d\d\d\d)$', ''), 'A', ' ')::timestamptz;
END$$
  LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION to_anvil_timestamp(ts timestamptz) RETURNS text AS $$
BEGIN
  return to_char(ts, 'YYYY-MM-DDAHH24:MI:SS.US+0000');
END$$
  LANGUAGE plpgsql;

CREATE TABLE db_version (version text not null, updated timestamp);

--[GRANTS]--
GRANT SELECT ON db_version TO $ANVIL_USER;
GRANT EXECUTE ON FUNCTION parse_anvil_timestamp TO $ANVIL_USER;
GRANT EXECUTE ON FUNCTION to_anvil_timestamp TO $ANVIL_USER;
GRANT EXECUTE ON FUNCTION get_lo_size TO $ANVIL_USER;

GRANT ALL ON app_storage_tables, app_storage_access, app_storage_data, app_storage_media, app_storage_data_id_seq TO $ANVIL_USER;
--[/GRANTS]--
