#!/bin/bash

# =============================================================================
# KIỂM TRA TOÀN BỘ DỮ LIỆU - SO SÁNH TẤT CẢ TABLES
# =============================================================================

OLD_CONTAINER="database-genki-db-1"
NEW_CONTAINER="genki-db-pg13"
POSTGRES_USER="genki_dev"
DB="genki"

echo "=============================================="
echo " KIỂM TRA TOÀN BỘ DỮ LIỆU"
echo "=============================================="
echo ""

# Lấy danh sách tất cả tables trong public schema
TABLES=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;")

TOTAL=$(echo "$TABLES" | grep -c '[a-z]')
MATCH=0
MISMATCH=0
MISMATCH_LIST=""

echo "Đang kiểm tra $TOTAL tables..."
echo ""

for TABLE in $TABLES; do
    TABLE=$(echo "$TABLE" | xargs)
    if [ -z "$TABLE" ]; then continue; fi
    
    PG11=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM \"$TABLE\";" 2>/dev/null | xargs)
    PG13=$(docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM \"$TABLE\";" 2>/dev/null | xargs)
    
    if [ "$PG11" == "$PG13" ]; then
        MATCH=$((MATCH + 1))
        echo "✓ $TABLE: $PG11"
    else
        MISMATCH=$((MISMATCH + 1))
        MISMATCH_LIST="$MISMATCH_LIST\n$TABLE: PG11=$PG11, PG13=$PG13"
        echo "✗ $TABLE: PG11=$PG11, PG13=$PG13"
    fi
done

echo ""
echo "=============================================="
echo " KẾT QUẢ"
echo "=============================================="
echo "Tổng tables: $TOTAL"
echo "Khớp: $MATCH"
echo "Không khớp: $MISMATCH"

if [ $MISMATCH -gt 0 ]; then
    echo ""
    echo "=== DANH SÁCH TABLES KHÔNG KHỚP ==="
    echo -e "$MISMATCH_LIST"
fi

echo ""
echo "=============================================="
