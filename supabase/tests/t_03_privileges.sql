-- 実行権限: 利用者（authenticated）が呼べる関数は、アプリが使う公開の関数だけ
\i supabase/tests/helpers.sql

select tst.eq((
  select string_agg(p.proname, ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')
    and p.proname in ('_err', '_uid', '_need', '_write_splits', 'equal_split', 'handle_new_user', 'gen_random_bytes_safe', 'next_occurrence', 'first_occurrence', 'prepare_account_deletion', '_audit')
), null, 'internal functions not executable by authenticated');

select tst.eq((
  select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute') and p.proname not in ('role_rank', 'today_jst')
), 0::bigint, 'anon executes nothing important');

select tst.eq(has_function_privilege('authenticated', 'public.save_transaction(uuid, jsonb)', 'execute'), true, 'public api still executable');
select tst.eq(has_function_privilege('service_role', 'public.prepare_account_deletion(uuid)', 'execute'), true, 'service role keeps account deletion');

-- 利用者が直接 _write_splits を呼ぶと権限エラー
select tst.as_user('a0000000-0000-0000-0000-00000000000a');
set role authenticated;
select tst.raises($$select public._write_splits(null::public.transactions, '[]'::jsonb)$$, '42501', 'direct internal call denied');
reset role;

-- 表への直接の書き込みもできない（書き込みは関数だけ）
set role authenticated;
select tst.raises($$insert into public.transactions (group_id) values (gen_random_uuid())$$, '42501', 'direct insert denied');
reset role;
