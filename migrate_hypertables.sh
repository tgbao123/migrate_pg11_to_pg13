#!/bin/bash

# =============================================================================
# MIGRATE HYPERTABLE DATA TỪ PG11 SANG PG13
# =============================================================================

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# Default values if not set in .env
OLD_CONTAINER="${OLD_CONTAINER:-database-genki-db-1}"
NEW_CONTAINER="${NEW_CONTAINER:-genki-db-pg13}"
POSTGRES_USER="${POSTGRES_USER:-genki_dev}"
DB="${DB:-genki}"

echo "=============================================="
echo " MIGRATE DỮ LIỆU HYPERTABLES"
echo "=============================================="

# Lấy danh sách hypertables
HYPERTABLES=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT hypertable_name FROM timescaledb_information.hypertables;")

TOTAL=$(echo "$HYPERTABLES" | grep -c '[a-z]')
COUNT=0

for TABLE in $HYPERTABLES; do
    TABLE=$(echo "$TABLE" | xargs)
    if [ -z "$TABLE" ]; then continue; fi
    
    COUNT=$((COUNT + 1))
    
    # Đếm rows ở nguồn
    SRC_COUNT=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM \"$TABLE\";" | xargs)
    
    echo ""
    echo "[$COUNT/$TOTAL] $TABLE (PG11: $SRC_COUNT rows)"
    
    if [ "$SRC_COUNT" == "0" ]; then
        echo "  → Bỏ qua (0 rows)"
        continue
    fi
    
    # Delete dữ liệu cũ trên PG13 (thay vì TRUNCATE)
    echo "  → Xóa dữ liệu cũ..."
    docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -c "DELETE FROM \"$TABLE\";" 2>/dev/null || true
    
    # Disable triggers trên PG13
    docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -c "ALTER TABLE \"$TABLE\" DISABLE TRIGGER ALL;" 2>/dev/null || true
    
    # Export từ PG11 và import vào PG13 (dùng CSV thay vì BINARY)
    echo "  → Đang copy $SRC_COUNT rows..."
    
    docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" \
        -c "\COPY (SELECT * FROM \"$TABLE\") TO STDOUT WITH (FORMAT CSV, HEADER)" | \
    docker exec -i "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" \
        -c "\COPY \"$TABLE\" FROM STDIN WITH (FORMAT CSV, HEADER)"
    
    RESULT=$?
    
    # Enable triggers
    docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -c "ALTER TABLE \"$TABLE\" ENABLE TRIGGER ALL;" 2>/dev/null || true
    
    # Verify
    DST_COUNT=$(docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM \"$TABLE\";" 2>/dev/null | xargs)
    
    if [ "$SRC_COUNT" == "$DST_COUNT" ]; then
        echo "  ✓ OK: $DST_COUNT rows"
    else
        echo "  ⚠ PG11=$SRC_COUNT, PG13=$DST_COUNT"
    fi
done

echo ""
echo "=============================================="
echo " KIỂM TRA KẾT QUẢ CUỐI CÙNG"
echo "=============================================="
echo ""
echo "user_health_source_step:"
echo "  PG11: $(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM user_health_source_step;" | xargs)"
echo "  PG13: $(docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM user_health_source_step;" | xargs)"

echo ""
echo "=============================================="
echo " HOÀN TẤT!"
echo "=============================================="
