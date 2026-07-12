# Optional SQL init (first boot only)

Drop any `*.sql` files in this directory. They run after the primary DB exists,
in sorted filename order, via `run-sql-init.sh`.

Examples:

```sql
CREATE DATABASE app OWNER supabase_admin;
CREATE DATABASE analytics OWNER supabase_admin;
```

Copy `01-databases.sql.example` → `01-databases.sql` to enable the sample.

You can also use env `POSTGRES_DATABASES=app,analytics` (no SQL file needed).
Both mechanisms can be used together.
