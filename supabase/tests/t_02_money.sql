-- 金額の計算: 分担・立替と負担・精算（二重精算の防止）・予算・集計・二重登録・定期取引
\i supabase/tests/helpers.sql
delete from public.invitation_attempts;
select tst.user('a0000000-0000-0000-0000-00000000000a', 'a@example.com', 'A');
select tst.user('b0000000-0000-0000-0000-00000000000b', 'b@example.com', 'B');
select tst.user('c0000000-0000-0000-0000-00000000000c', 'c@example.com', 'C');

-- 均等割り（共通のテスト値 tests/vectors/splits.json）: メンバー 7 人の並びを作って確かめる
create temp table mem7 (id uuid, joined timestamptz);
insert into public.groups (id, name) values ('99999999-0000-0000-0000-000000000000', 'vec');
insert into public.group_members (id, group_id, role, display_name, joined_at)
select ('99999999-0000-0000-0000-00000000000' || i)::uuid, '99999999-0000-0000-0000-000000000000', 'member', 'm' || i, timestamptz '2026-01-01' + make_interval(mins => i) from generate_series(1, 7) i;
do $$
declare v jsonb := pg_read_file(current_setting('kb.root') || '/tests/vectors/splits.json')::jsonb; c jsonb; got bigint[]; ids uuid[];
begin
  for c in select * from jsonb_array_elements(v -> 'cases') loop
    select array_agg(id order by joined_at, id) into ids from (select id, joined_at from public.group_members where group_id = '99999999-0000-0000-0000-000000000000' order by joined_at limit (c ->> 'members')::int) x;
    select array_agg(s.amount order by m.joined_at, m.id) into got from public.equal_split((c ->> 'amount')::bigint, ids) s join public.group_members m on m.id = s.member_id;
    if got <> array(select jsonb_array_elements_text(c -> 'expected')::bigint) then raise exception 'FAIL(split %) got %', c, got; end if;
  end loop;
end $$;

-- グループ: A がオーナー、B と C が参加
select tst.as_user('a0000000-0000-0000-0000-00000000000a');
set role authenticated;
create temp table g as select id from public.create_group('旅行');
create temp table inv as select public.create_invitation((select id from g), 'member', 24, 2) j;
reset role;
grant select on g, inv to authenticated;
select tst.as_user('b0000000-0000-0000-0000-00000000000b'); set role authenticated; select public.accept_invitation((select j ->> 'code' from inv)); reset role;
select tst.as_user('c0000000-0000-0000-0000-00000000000c'); set role authenticated; select public.accept_invitation((select j ->> 'code' from inv)); reset role;
create temp table ids as select
  (select id from public.categories where group_id = (select id from g) and name = '食費') food,
  (select id from public.group_members where group_id = (select id from g) and user_id = 'a0000000-0000-0000-0000-00000000000a') a,
  (select id from public.group_members where group_id = (select id from g) and user_id = 'b0000000-0000-0000-0000-00000000000b') b,
  (select id from public.group_members where group_id = (select id from g) and user_id = 'c0000000-0000-0000-0000-00000000000c') c;
grant select on ids to authenticated;

-- 共通のテスト値 tests/vectors/settlement.json と同じ支出を登録
select tst.as_user('a0000000-0000-0000-0000-00000000000a');
set role authenticated;
select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', 'aaaaaaaa-0000-0000-0000-000000000001', 'kind', 'expense', 'amount', 3000, 'occurred_on', '2026-10-03',
  'category_id', (select food from ids), 'payer_member_id', (select a from ids), 'split_mode', 'equal', 'splits', jsonb_build_array((select a from ids), (select b from ids), (select c from ids))));
-- 二重送信（同じ client_request_id）は 1 件だけ
select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', 'aaaaaaaa-0000-0000-0000-000000000001', 'kind', 'expense', 'amount', 3000, 'occurred_on', '2026-10-03',
  'category_id', (select food from ids), 'payer_member_id', (select a from ids), 'split_mode', 'equal', 'splits', jsonb_build_array((select a from ids), (select b from ids), (select c from ids))));
select tst.eq((select count(*) from public.transactions where group_id = (select id from g)), 1::bigint, 'idempotent insert');
select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 1000, 'occurred_on', '2026-10-04',
  'category_id', (select food from ids), 'payer_member_id', (select b from ids), 'split_mode', 'custom',
  'splits', jsonb_build_array(jsonb_build_object('member_id', (select a from ids), 'amount', 0), jsonb_build_object('member_id', (select b from ids), 'amount', 400), jsonb_build_object('member_id', (select c from ids), 'amount', 600))));
select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 500, 'occurred_on', '2026-10-05', 'category_id', (select food from ids), 'payer_member_id', (select c from ids)));
-- 入力の誤り
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 1000, 'occurred_on', '2026-10-04', 'category_id', (select food from ids), 'payer_member_id', (select b from ids), 'split_mode', 'custom', 'splits', jsonb_build_array(jsonb_build_object('member_id', (select a from ids), 'amount', 999)))), 'KB422', 'custom split sum mismatch');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 12.5, 'occurred_on', '2026-10-04', 'category_id', (select food from ids), 'payer_member_id', (select b from ids))), 'KB422', 'fractional yen');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 0, 'occurred_on', '2026-10-04', 'category_id', (select food from ids), 'payer_member_id', (select b from ids))), 'KB422', 'zero amount');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 1000000000, 'occurred_on', '2026-10-04', 'category_id', (select food from ids), 'payer_member_id', (select b from ids))), 'KB422', 'too large');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', '1000', 'occurred_on', '2026-10-04', 'category_id', (select food from ids), 'payer_member_id', (select b from ids))), 'KB422', 'string amount');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 100, 'occurred_on', '1999-12-31', 'category_id', (select food from ids), 'payer_member_id', (select b from ids))), 'KB422', 'old date');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'income', 'amount', 100, 'occurred_on', '2026-10-04', 'category_id', (select food from ids), 'payer_member_id', (select b from ids))), 'KB422', 'expense category for income');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 100, 'occurred_on', '2026-10-04', 'category_id', (select food from ids), 'payer_member_id', (select b from ids), 'memo', repeat('x', 501))), 'KB422', 'memo too long');

-- 立替と負担（共通のテスト値）
select tst.eq((select paid || '/' || burden || '/' || net from public.group_balances((select id from g)) where member_id = (select a from ids)), '3000/1000/2000', 'A balance');
select tst.eq((select paid || '/' || burden || '/' || net from public.group_balances((select id from g)) where member_id = (select b from ids)), '1000/1400/-400', 'B balance');
select tst.eq((select paid || '/' || burden || '/' || net from public.group_balances((select id from g)) where member_id = (select c from ids)), '0/1600/-1600', 'C balance');
select tst.eq((select string_agg(amount::text, ',') from public.settlement_suggestions((select id from g))), '1600,400', 'suggestions');
reset role;

-- 精算: C が A に 1600 円を記録 → A が確認。二重の記録・確認・超過はできない
select tst.as_user('c0000000-0000-0000-0000-00000000000c');
set role authenticated;
create temp table s1 as select * from public.record_settlement((select id from g), (select c from ids), (select a from ids), 1600, '振込', 'cccccccc-0000-0000-0000-000000000001');
select tst.eq((select id from public.record_settlement((select id from g), (select c from ids), (select a from ids), 1600, '振込', 'cccccccc-0000-0000-0000-000000000001')), (select id from s1), 'same request returns same settlement');
select tst.raises(format($$select public.record_settlement(%L, %L, %L, 1, '', gen_random_uuid())$$, (select id from g), (select c from ids), (select a from ids)), 'KB422', 'cannot exceed owed incl pending');
select tst.raises(format($$select public.record_settlement(%L, %L, %L, 100, '', gen_random_uuid())$$, (select id from g), (select b from ids), (select a from ids)), 'KB403', 'cannot record for someone else');
select tst.raises(format($$select public.confirm_settlement(%L)$$, (select id from s1)), 'KB403', 'payer cannot confirm');
select tst.eq((select net from public.group_balances((select id from g)) where member_id = (select c from ids)), -1600::bigint, 'pending not counted');
reset role;
grant select on s1 to authenticated;
select tst.as_user('a0000000-0000-0000-0000-00000000000a');
set role authenticated;
select * from public.confirm_settlement((select id from s1));
select tst.raises(format($$select public.confirm_settlement(%L)$$, (select id from s1)), 'KB409', 'double confirm');
select tst.eq((select string_agg(net::text, ',') from public.group_balances((select id from g))), '400,-400,0', 'after settle nets');
select tst.eq((select count(*) from public.settlement_suggestions((select id from g))), 1::bigint, 'one suggestion left');

-- 予算: 全体 5000、食費 3000（10 月から。11 月も続く）
select * from public.save_budget((select id from g), 'group', null, null, '2026-10-01', 5000);
select * from public.save_budget((select id from g), 'group', (select food from ids), null, '2026-10-01', 3000);
select * from public.save_budget((select id from g), 'personal', null, (select b from ids), '2026-10-01', 1000);
select tst.eq((select spent || '/' || remaining || '/' || over from public.budget_status((select id from g), '2026-10-15') where category_id is null and scope = 'group'), '4500/500/false', 'total budget');
select tst.eq((select spent || '/' || remaining || '/' || over || '/' || ratio from public.budget_status((select id from g), '2026-10-01') where category_id is not null), '4500/-1500/true/1.5000', 'food budget over');
select tst.eq((select spent || '/' || over from public.budget_status((select id from g), '2026-10-01') where scope = 'personal'), '1400/true', 'personal burden budget');
select tst.eq((select count(*) from public.budget_status((select id from g), '2026-11-01')), 3::bigint, 'budget continues next month');
select tst.eq((select spent from public.budget_status((select id from g), '2026-11-01') where category_id is null and scope = 'group'), 0::bigint, 'new month restarts');
select tst.eq((select count(*) from public.budget_status((select id from g), '2026-09-01')), 0::bigint, 'no budget before start');

-- 集計
select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'income', 'amount', 250000, 'occurred_on', '2026-10-25',
  'category_id', (select id from public.categories where group_id = (select id from g) and name = '給与'), 'payer_member_id', (select a from ids)));
select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 7000, 'occurred_on', '2026-09-10', 'category_id', (select food from ids), 'payer_member_id', (select a from ids)));
select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 99999, 'occurred_on', '2026-10-10', 'category_id', (select food from ids), 'payer_member_id', (select a from ids), 'visibility', 'private'));
select tst.eq((select (s ->> 'income') || '/' || (s ->> 'expense') || '/' || (s ->> 'balance') || '/' || (s ->> 'prev_expense') from public.month_summary((select id from g), '2026-10-31') s), '250000/4500/245500/7000', 'month summary excludes private');
select tst.eq((select string_agg(expense::text, ',') from public.monthly_series((select id from g), '2026-10-01', 3)), '0,7000,4500', 'series');

-- 同時更新: 2 台が同じ version で更新 → 後の方は競合
create temp table tx as select * from public.save_transaction((select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 100, 'occurred_on', '2026-10-11', 'category_id', (select food from ids), 'payer_member_id', (select a from ids)));
select * from public.save_transaction((select id from g), jsonb_build_object('id', (select id from tx), 'version', 1, 'kind', 'expense', 'amount', 200, 'occurred_on', '2026-10-11', 'category_id', (select food from ids), 'payer_member_id', (select a from ids)));
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('id', (select id from tx), 'version', 1, 'kind', 'expense', 'amount', 300, 'occurred_on', '2026-10-11', 'category_id', (select food from ids), 'payer_member_id', (select a from ids))), 'KB409', 'concurrent edit conflict');

-- 定期取引: 毎月 31 日（ない月は月末）。何度生成しても同じ数
create temp table rc as select * from public.save_recurring((select id from g), jsonb_build_object('kind', 'expense', 'amount', 80000, 'category_id', (select food from ids), 'payer_member_id', (select a from ids),
  'freq', 'monthly', 'day_of_month', 31, 'start_on', '2026-01-15', 'end_on', '2026-05-31'));
select tst.eq((select next_run_on from rc), date '2026-01-31', 'first run');
select tst.eq(public.generate_due_recurring((select id from g)), 5, 'generated 5 (Jan-May)');
select tst.eq(public.generate_due_recurring((select id from g)), 0, 'second run generates nothing');
select tst.eq((select string_agg(to_char(occurred_on, 'MM-DD'), ',' order by occurred_on) from public.transactions where recurring_id = (select id from rc)), '01-31,02-28,03-31,04-30,05-31', 'month-end dates');
select tst.eq((select active from public.recurring_transactions where id = (select id from rc)), false, 'ended recurring is inactive');
-- 毎週・分担つき
create temp table rw as select * from public.save_recurring((select id from g), jsonb_build_object('kind', 'expense', 'amount', 900, 'category_id', (select food from ids), 'payer_member_id', (select a from ids),
  'freq', 'weekly', 'weekday', 1, 'start_on', '2026-10-01', 'end_on', '2026-10-31', 'split_mode', 'equal', 'splits', jsonb_build_array((select a from ids), (select b from ids), (select c from ids))));
select tst.eq((select next_run_on from rw), date '2026-10-05', 'first monday');
select public.generate_due_recurring((select id from g));
select tst.eq((select count(*) from public.transaction_splits s join public.transactions t on t.id = s.transaction_id where t.recurring_id = (select id from rw)), 12::bigint, 'weekly splits generated (4 mondays x 3)');

-- カテゴリ: 使われていれば消さずにアーカイブ
select tst.eq(public.delete_category((select food from ids)), 'archived', 'used category archived');
select tst.eq(public.delete_category((select id from public.categories where group_id = (select id from g) and name = '税金')), 'deleted', 'unused category deleted');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from g), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 100, 'occurred_on', '2026-10-04', 'category_id', (select food from ids), 'payer_member_id', (select a from ids))), 'KB422', 'archived category not selectable for new');
reset role;

-- 退会の準備: オーナーで他のメンバーがいるなら止める。メンバーなら名前を消して記録は残す
select tst.eq((public.prepare_account_deletion('a0000000-0000-0000-0000-00000000000a')) ->> 'ok', 'false', 'owner blocked');
select tst.eq((public.prepare_account_deletion('c0000000-0000-0000-0000-00000000000c')) ->> 'ok', 'true', 'member can delete');
select tst.eq((select display_name || '/' || status from public.group_members where id = (select c from ids)), '退会したメンバー/left', 'member anonymized');

