#!/usr/bin/env bash
# ローカルの PostgreSQL に、まっさらな DB を作ってマイグレーションとテストを流す
# Windows（Git Bash）: そのまま。Linux・CI: PSQL_BIN=psql PGPORT=5432 などで上書き
set -e
cd "$(dirname "$0")/../.."
PSQL_BIN="${PSQL_BIN:-/d/tools/pgsql17/pgsql/bin/psql.exe}"
NULL_OUT=/dev/null; ROOT="$(pwd)"
if pwd -W >/dev/null 2>&1; then NULL_OUT=nul; ROOT="$(pwd -W)"; fi
PSQL="$PSQL_BIN -h ${PGHOST:-127.0.0.1} -p ${PGPORT:-54329} -U ${PGUSER:-postgres} -v ON_ERROR_STOP=1 -q -o $NULL_OUT"
export PGOPTIONS="-c kb.root=$ROOT"
$PSQL -c "drop database if exists kb_test" -c "create database kb_test" 2>/dev/null
$PSQL -d kb_test -f supabase/tests/local_bootstrap.sql
for f in supabase/migrations/*.sql; do $PSQL -d kb_test -f "$f"; done
echo "migrations: OK"
for f in supabase/tests/t_*.sql; do $PSQL -d kb_test -f "$f" && echo "PASS $(basename "$f")"; done
