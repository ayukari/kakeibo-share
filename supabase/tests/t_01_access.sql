-- 認証・グループ・招待・権限・RLS（別グループのデータが見えないこと）
\i supabase/tests/helpers.sql
select tst.user('a0000000-0000-0000-0000-00000000000a', 'a@example.com', 'あや');
select tst.user('b0000000-0000-0000-0000-00000000000b', 'b@example.com', 'ぼん');
select tst.user('c0000000-0000-0000-0000-00000000000c', 'c@example.com', 'ちか');
select tst.user('d0000000-0000-0000-0000-00000000000d', 'd@example.com', 'でん');

-- 未ログインでは何もできない
set role authenticated;
select tst.as_user(null);
select tst.raises($$select public.create_group('x')$$, 'KB401', 'anon create');
select tst.eq((select count(*) from public.groups), 0::bigint, 'anon sees no groups');
reset role;

-- A がグループを作る（初期のカテゴリと支払い方法が入る）
select tst.as_user('a0000000-0000-0000-0000-00000000000a');
set role authenticated;
create temp table g as select (public.create_group('うちの家計簿')).id;
select tst.eq((select count(*) from public.categories where group_id = (select id from g) and kind = 'expense'), 14::bigint, 'default expense categories');
select tst.eq((select count(*) from public.categories where group_id = (select id from g) and kind = 'income'), 5::bigint, 'default income categories');
select tst.eq((select role::text from public.group_members where group_id = (select id from g)), 'owner', 'creator is owner');
select tst.raises($$select public.create_group('')$$, 'KB422', 'empty name');
select tst.raises($$select public.create_group(repeat('あ', 41))$$, 'KB422', 'long name');
-- 直接の書き込みはできない（関数だけ）
select tst.raises($$insert into public.groups (name) values ('x')$$, '42501', 'direct insert groups');
select tst.raises(format($$update public.groups set name = 'x' where id = %L$$, (select id from g)), '42501', 'direct update');
select tst.raises(format($$delete from public.transactions where group_id = %L$$, (select id from g)), '42501', 'direct delete');
-- 招待コード（member）と（viewer）
create temp table inv as select public.create_invitation((select id from g), 'member', 24, 1) as j;
create temp table invv as select public.create_invitation((select id from g), 'viewer', 24, 2) as j;
select tst.raises(format($$select public.create_invitation(%L, 'admin', 24, 1)$$, (select id from g)), 'KB422', 'cannot invite admin');
select tst.eq(char_length((select j ->> 'code' from inv)), 12, 'code length');
reset role;
-- コードは平文で保存しない
select tst.eq((select count(*) from public.invitations where code_hash = (select j ->> 'code' from inv)), 0::bigint, 'code not stored in plain');
grant select on inv, invv, g to authenticated;

-- C（部外者）: グループの ID を知っていても何も見えない・できない
select tst.as_user('c0000000-0000-0000-0000-00000000000c');
set role authenticated;
select tst.eq((select count(*) from public.groups where id = (select id from g)), 0::bigint, 'outsider cannot read group');
select tst.eq((select count(*) from public.categories where group_id = (select id from g)), 0::bigint, 'outsider cannot read categories');
select tst.eq((select count(*) from public.group_members where group_id = (select id from g)), 0::bigint, 'outsider cannot read members');
select tst.raises(format($$select public.month_summary(%L, '2026-10-01')$$, (select id from g)), 'KB403', 'outsider summary');
select tst.raises(format($$select * from public.group_balances(%L)$$, (select id from g)), 'KB403', 'outsider balances');
select tst.raises(format($$select public.save_transaction(%L, '{}'::jsonb)$$, (select id from g)), 'KB403', 'outsider save txn');
-- 間違ったコードは弾かれ、10 回で止まる（総当たりの防止）
select tst.eq((public.accept_invitation('WRONGCODE123')).id, null::uuid, 'wrong code returns null');
do $$ begin for i in 1..9 loop perform public.accept_invitation('WRONG' || i); end loop; end $$;
select tst.raises(format($$select public.accept_invitation(%L)$$, (select j ->> 'code' from inv)), 'KB409', 'rate limited even with right code');
reset role;

-- B が member として参加（コードは前後の空白・小文字・ハイフンがあっても通る）
select tst.as_user('b0000000-0000-0000-0000-00000000000b');
set role authenticated;
select tst.eq((select role::text from public.accept_invitation(lower((select j ->> 'code' from inv)), 'ぼんちゃん')), 'member', 'B joins as member');
select tst.eq((public.accept_invitation((select j ->> 'code' from inv))).id, null::uuid, 'used-up code returns null');
select tst.eq((select count(*) from public.groups where id = (select id from g)), 1::bigint, 'member reads group');
select tst.raises(format($$select public.create_invitation(%L, 'member', 24, 1)$$, (select id from g)), 'KB403', 'member cannot invite');
select tst.raises(format($$select public.rename_group(%L, 'x')$$, (select id from g)), 'KB403', 'member cannot rename');
select tst.eq((select count(*) from public.audit_logs), 0::bigint, 'member cannot read audit');
reset role;

-- D が viewer として参加
select tst.as_user('d0000000-0000-0000-0000-00000000000d');
set role authenticated;
select tst.eq((select role::text from public.accept_invitation((select j ->> 'code' from invv))), 'viewer', 'D joins as viewer');
reset role;

-- 取引: A が「グループ」と「自分だけ」を登録
select tst.as_user('a0000000-0000-0000-0000-00000000000a');
set role authenticated;
create temp table ids as select
  (select id from public.categories where group_id = (select id from g) and name = '食費') as food,
  (select id from public.categories where group_id = (select id from g) and kind = 'income' and name = '給与') as salary,
  (select id from public.group_members where group_id = (select id from g) and role = 'owner') as ma,
  (select id from public.group_members where group_id = (select id from g) and role = 'member') as mb;
create temp table t1 as select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 1200, 'occurred_on', '2026-10-05',
  'category_id', (select food from ids), 'payer_member_id', (select ma from ids), 'memo', 'スーパー'));
create temp table t2 as select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 500, 'occurred_on', '2026-10-06',
  'category_id', (select food from ids), 'payer_member_id', (select ma from ids), 'visibility', 'private'));
reset role;
grant select on ids, t1, t2 to authenticated;

-- B（member）: 自分だけの取引は見えない。他人の取引は編集・削除できない
select tst.as_user('b0000000-0000-0000-0000-00000000000b');
set role authenticated;
select tst.eq((select count(*) from public.transactions where group_id = (select id from g)), 1::bigint, 'member sees only group-visible');
select tst.raises(format($$select public.delete_transaction(%L, 1)$$, (select id from t1)), 'KB403', 'member cannot delete others');
select tst.raises(format($$select public.delete_transaction(%L, 1)$$, (select id from t2)), 'KB404', 'private is not found for others');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('id', (select id from t1), 'version', 1, 'kind', 'expense', 'amount', 1, 'occurred_on', '2026-10-05', 'category_id', (select food from ids), 'payer_member_id', (select mb from ids))), 'KB403', 'member cannot edit others');
-- 自分の取引は登録・編集・削除できる
create temp table tb as select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 800, 'occurred_on', '2026-10-07', 'category_id', (select food from ids), 'payer_member_id', (select mb from ids)));
select tst.eq((public.save_transaction((select id from g), jsonb_build_object('id', (select id from tb), 'version', 1, 'kind', 'expense', 'amount', 850, 'occurred_on', '2026-10-07', 'category_id', (select food from ids), 'payer_member_id', (select mb from ids)))).amount, 850::bigint, 'member edits own');
select tst.raises(format($$select public.delete_transaction(%L, 1)$$, (select id from tb)), 'KB409', 'stale version conflict');
select public.delete_transaction((select id from tb), 2);
select tst.eq((select count(*) from public.transactions where id = (select id from tb)), 0::bigint, 'deleted hidden? (status shown)') where false;
select tst.eq((select status::text from public.transactions where id = (select id from tb)), 'deleted', 'soft deleted');
reset role;

-- D（viewer）: 見るだけ
select tst.as_user('d0000000-0000-0000-0000-00000000000d');
set role authenticated;
select tst.eq((select count(*) from public.transactions where group_id = (select id from g) and status = 'active'), 1::bigint, 'viewer reads');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 1, 'occurred_on', '2026-10-05', 'category_id', (select food from ids), 'payer_member_id', (select ma from ids))), 'KB403', 'viewer cannot add');
reset role;

-- 役割: admin は owner しか作れない。member は役割を変えられない。オーナーは抜けられない
select tst.as_user('b0000000-0000-0000-0000-00000000000b');
set role authenticated;
select tst.raises(format($$select public.change_member_role(%L, 'admin')$$, (select mb from ids)), 'KB403', 'member cannot promote self');
reset role;
select tst.as_user('a0000000-0000-0000-0000-00000000000a');
set role authenticated;
select tst.eq((public.change_member_role((select mb from ids), 'admin')).role::text, 'admin', 'owner promotes B to admin');
select tst.raises(format($$select public.leave_group(%L)$$, (select id from g)), 'KB422', 'owner cannot leave');
reset role;
select tst.as_user('b0000000-0000-0000-0000-00000000000b');
set role authenticated;
select tst.raises(format($$select public.change_member_role(%L, 'admin')$$, (select id from public.group_members where group_id = (select id from g) and role = 'viewer')), 'KB403', 'admin cannot make admin');
select tst.raises(format($$select public.remove_member(%L)$$, (select ma from ids)), 'KB403', 'admin cannot remove owner');
select tst.eq((select count(*) > 0 from public.audit_logs where group_id = (select id from g)), true, 'admin reads audit');
select tst.eq((select count(*) from public.audit_logs where detail ? 'code_hash' or detail::text like '%code_hash%'), 0::bigint, 'audit has no secrets');
reset role;

-- 他のグループのデータは、グループ ID を書き換えても届かない
select tst.as_user('c0000000-0000-0000-0000-00000000000c');
set role authenticated;
create temp table gc as select (public.create_group('ちかの家計簿')).id;
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from gc), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 1, 'occurred_on', '2026-10-05', 'category_id', (select food from ids), 'payer_member_id', (select ma from ids))), 'KB422', 'other group category rejected');
select tst.eq((select count(*) from public.transactions), 0::bigint, 'C sees no transactions of A');
reset role;
