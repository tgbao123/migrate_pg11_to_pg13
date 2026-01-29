#!/bin/bash

# =============================================================================
# SO SÁNH DỮ LIỆU VÀ OBJECTS GIỮA PG11 VÀ PG13
# =============================================================================

OLD_CONTAINER="database-genki-db-1"
NEW_CONTAINER="genki-db-pg13"
POSTGRES_USER="genki_dev"
DB="genki"

echo "=============================================="
echo " SO SÁNH DỮ LIỆU GIỮA PG11 VÀ PG13"
echo "=============================================="
echo ""

# 1. So sánh số lượng tables
echo "=== TABLES ==="
PG11_TABLES=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';")
PG13_TABLES=$(docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';")
echo "PG11: $(echo $PG11_TABLES | xargs) tables"
echo "PG13: $(echo $PG13_TABLES | xargs) tables"
echo ""

# 2. So sánh triggers
echo "=== TRIGGERS ==="
PG11_TRIGGERS=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM pg_trigger WHERE NOT tgisinternal;")
PG13_TRIGGERS=$(docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM pg_trigger WHERE NOT tgisinternal;")
echo "PG11: $(echo $PG11_TRIGGERS | xargs) triggers"
echo "PG13: $(echo $PG13_TRIGGERS | xargs) triggers"

# Liệt kê triggers khác nhau
echo ""
echo "Triggers trên PG11 nhưng KHÔNG có trên PG13:"
docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "
SELECT DISTINCT t.tgname, c.relname as table_name 
FROM pg_trigger t 
JOIN pg_class c ON t.tgrelid = c.oid 
WHERE NOT t.tgisinternal
ORDER BY c.relname, t.tgname;" > /tmp/pg11_triggers.txt

docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "
SELECT DISTINCT t.tgname, c.relname as table_name 
FROM pg_trigger t 
JOIN pg_class c ON t.tgrelid = c.oid 
WHERE NOT t.tgisinternal
ORDER BY c.relname, t.tgname;" > /tmp/pg13_triggers.txt

comm -23 <(sort /tmp/pg11_triggers.txt) <(sort /tmp/pg13_triggers.txt) | head -20
echo ""

# 3. So sánh functions
echo "=== FUNCTIONS ==="
PG11_FUNCS=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');")
PG13_FUNCS=$(docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');")
echo "PG11: $(echo $PG11_FUNCS | xargs) functions"
echo "PG13: $(echo $PG13_FUNCS | xargs) functions"

# Liệt kê functions khác nhau
echo ""
echo "Functions trên PG11 nhưng KHÔNG có trên PG13:"
docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "
SELECT proname FROM pg_proc 
WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY proname;" > /tmp/pg11_funcs.txt

docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "
SELECT proname FROM pg_proc 
WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY proname;" > /tmp/pg13_funcs.txt

comm -23 <(sort /tmp/pg11_funcs.txt) <(sort /tmp/pg13_funcs.txt) | head -20
echo ""

# 4. So sánh indexes
echo "=== INDEXES ==="
PG11_IDX=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';")
PG13_IDX=$(docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';")
echo "PG11: $(echo $PG11_IDX | xargs) indexes"
echo "PG13: $(echo $PG13_IDX | xargs) indexes"
echo ""

# 5. So sánh row counts cho các tables lớn nhất
echo "=== ROW COUNTS (Top Tables) ==="
echo ""
echo "| Table | PG11 | PG13 | Match |"
echo "|-------|------|------|-------|"

TABLES="accounts users user_health_source_step user_health_source_heart user_health_source_respiratory_rate phr_personals"

for TABLE in $TABLES; do
    PG11_COUNT=$(docker exec "$OLD_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM \"$TABLE\";" 2>/dev/null | xargs)
    PG13_COUNT=$(docker exec "$NEW_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB" -t -c "SELECT COUNT(*) FROM \"$TABLE\";" 2>/dev/null | xargs)
    
    if [ "$PG11_COUNT" == "$PG13_COUNT" ]; then
        MATCH="✓"
    else
        MATCH="✗"
    fi
    
    echo "| $TABLE | $PG11_COUNT | $PG13_COUNT | $MATCH |"
done

echo ""
echo "=============================================="
echo " HOÀN TẤT KIỂM TRA!"
echo "=============================================="
