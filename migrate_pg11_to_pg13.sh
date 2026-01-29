#!/bin/bash

# =============================================================================
# SCRIPT MIGRATE DATABASE TỪ PG11 SANG PG13
# =============================================================================

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# Default values if not set in .env
BACKUP_DIR="${BACKUP_DIR:-/Users/tgbao/Desktop/source_code/database/backup_pg11}"
OLD_CONTAINER="${OLD_CONTAINER:-database-genki-db-1}"
NEW_CONTAINER="${NEW_CONTAINER:-genki-db-pg13}"
POSTGRES_USER="${POSTGRES_USER:-genki_dev}"

mkdir -p "$BACKUP_DIR"

echo "=============================================="
echo " BƯỚC 1: BACKUP TẤT CẢ DATABASES TỪ PG11"
echo "=============================================="

# Backup globals (roles, users)
echo "→ Backup roles và users..."
docker exec "$OLD_CONTAINER" pg_dumpall -U "$POSTGRES_USER" --globals-only > "$BACKUP_DIR/globals.sql"
echo "✓ globals.sql"

# Lấy danh sách databases
DBS=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

for DB in $DBS; do
    DB=$(echo "$DB" | xargs)
    if [ -z "$DB" ]; then continue; fi
    
    echo "→ Backup: $DB"
    docker exec "$OLD_CONTAINER" pg_dump -U "$POSTGRES_USER" -d "$DB" -Fc \
        -f "/var/lib/postgresql/data/${DB}_backup.dump"
    
    # Copy ra ngoài
    docker cp "$OLD_CONTAINER:/var/lib/postgresql/data/${DB}_backup.dump" "$BACKUP_DIR/${DB}.dump"
    docker exec "$OLD_CONTAINER" rm -f "/var/lib/postgresql/data/${DB}_backup.dump"
    
    SIZE=$(ls -lh "$BACKUP_DIR/${DB}.dump" | awk '{print $5}')
    echo "✓ ${DB}.dump ($SIZE)"
done

echo ""
echo "=============================================="
echo " BƯỚC 2: RESTORE VÀO PG13"
echo "=============================================="

# Restore globals
echo "→ Restore roles và users..."
docker exec -i "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d postgres < "$BACKUP_DIR/globals.sql" 2>&1 | grep -vE "(already exists|^$)"
echo "✓ Done"

# Restore từng database
for dump_file in "$BACKUP_DIR"/*.dump; do
    if [ ! -f "$dump_file" ]; then continue; fi
    
    db_name=$(basename "$dump_file" .dump)
    file_size=$(ls -lh "$dump_file" | awk '{print $5}')
    
    echo ""
    echo "→ Restore: $db_name ($file_size)"
    
    # Drop và tạo lại database
    docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d postgres \
        -c "DROP DATABASE IF EXISTS \"$db_name\";" 2>/dev/null
    docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d postgres \
        -c "CREATE DATABASE \"$db_name\";" 2>/dev/null
    
    # Copy file vào container và restore
    docker cp "$dump_file" "$NEW_CONTAINER:/tmp/${db_name}.dump"
    
    # Gọi timescaledb_pre_restore() nếu có
    docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$db_name" \
        -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" 2>/dev/null
    docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$db_name" \
        -c "SELECT timescaledb_pre_restore();" 2>/dev/null
    
    # Restore với disable triggers
    docker exec "$NEW_CONTAINER" pg_restore -U "$POSTGRES_USER" -d "$db_name" \
        --no-owner --no-privileges --disable-triggers \
        "/tmp/${db_name}.dump" 2>&1 | grep -E "^(ERROR|WARNING)" | head -5
    
    # Gọi timescaledb_post_restore() nếu có
    docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$db_name" \
        -c "SELECT timescaledb_post_restore();" 2>/dev/null
    
    # Cleanup
    docker exec "$NEW_CONTAINER" rm -f "/tmp/${db_name}.dump"
    
    echo "✓ $db_name restored"
done

echo ""
echo "=============================================="
echo " BƯỚC 3: KIỂM TRA KẾT QUẢ"
echo "=============================================="

echo "So sánh số lượng tables trong database genki:"
echo "PG11:"
docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d genki -t \
    -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname NOT LIKE 'pg_%' AND schemaname != 'information_schema';"
echo "PG13:"
docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d genki -t \
    -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname NOT LIKE 'pg_%' AND schemaname != 'information_schema';"

echo ""
echo "So sánh user_health_source_step:"
echo "PG11:"
docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d genki -t \
    -c "SELECT COUNT(*) FROM user_health_source_step;"
echo "PG13:"
docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d genki -t \
    -c "SELECT COUNT(*) FROM user_health_source_step;"

echo ""
echo "=============================================="
echo " HOÀN TẤT!"
echo "=============================================="
