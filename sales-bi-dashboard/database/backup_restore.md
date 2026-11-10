# PostgreSQL Backup, Restore, Import & Export

Replace `sales_user` / `salesdb` with your own role and database. Commands run in a normal terminal (not inside psql).

## Backup
```bash
# Plain SQL file (readable, portable) - this is what database/salesdb_backup.sql is
pg_dump -h localhost -U sales_user -d salesdb --no-owner --no-privileges -f salesdb_backup.sql

# Compressed custom format (smaller, supports selective restore)
pg_dump -h localhost -U sales_user -d salesdb -Fc -f salesdb.dump
```

## Restore
```bash
createdb -h localhost -U sales_user salesdb_copy            # or create it in pgAdmin
psql -h localhost -U sales_user -d salesdb_copy -f salesdb_backup.sql
# custom format:
pg_restore -h localhost -U sales_user -d salesdb_copy --no-owner salesdb.dump
```
Verify: `psql -d salesdb_copy -c "SELECT COUNT(*) FROM order_items;"` should print 5905.

pgAdmin 4: right-click the database -> **Backup...** / **Restore...**.

## Import and export CSV
```sql
-- inside psql (client-side file paths, no superuser needed)
\copy (SELECT * FROM vw_sales_detail) TO 'sales_detail.csv' CSV HEADER
\copy regions (region_id, region_name) FROM 'regions.csv' CSV HEADER
```
Python alternative: `df.to_sql("table", engine, if_exists="append")` and `pd.read_sql(...)`.

## Roles (least privilege)
`database/roles.sql` creates `bi_readonly`, which can only SELECT. Point the dashboard's `DATABASE_URL`
at it to guarantee the app can never modify data:
`postgresql+psycopg://bi_readonly:<password>@localhost:5432/salesdb`
