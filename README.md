# PostgreSQL 11 to 13 Migration with TimescaleDB

Migration scripts for upgrading PostgreSQL 11 (TimescaleDB 2.3.1) to PostgreSQL 13 (TimescaleDB 2.15.3).

## Quick Start

1. Copy `.env.example` to `.env` and update values
2. Run migration: `./migrate_pg11_to_pg13.sh`
3. Migrate hypertables: `./migrate_hypertables.sh`
4. Verify: `./verify_all_tables.sh`

## Configuration

Edit `.env` file:

```bash
OLD_CONTAINER=database-genki-db-1    # Source PG11 container
NEW_CONTAINER=genki-db-pg13          # Target PG13 container
POSTGRES_USER=genki_dev              # Database user
DB=genki                             # Database name
BACKUP_DIR=/path/to/backup           # Backup directory
```

## Scripts

| Script | Description |
|--------|-------------|
| `migrate_pg11_to_pg13.sh` | Full database backup and restore |
| `migrate_hypertables.sh` | Migrate TimescaleDB hypertable data |
| `verify_all_tables.sh` | Compare row counts for all tables |
| `verify_migration.sh` | Compare database objects (tables, triggers, functions) |

## Notes

- TimescaleDB hypertable data requires separate migration using CSV COPY
- Some distributed features (12 functions) are not available in newer TimescaleDB versions
- Run `migrate_hypertables.sh` after `migrate_pg11_to_pg13.sh` to ensure complete data migration
