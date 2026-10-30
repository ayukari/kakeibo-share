-- 返金（集計・立替・予算で引く）と、予算の繰り越し（余りを足し、使いすぎを引き、繰り越さない月で止まる）
\i supabase/tests/helpers.sql
delete from public.invitation_attempts;
select tst.user('a1000000-0000-0000-0000-0000000000a1', 'a1@example.com', 'A1');
select tst.user('b1000000-0000-0000-0000-0000000000b1', 'b1@example.com', 'B1');

select tst.as_user('a1000000-0000-0000-0000-0000000000a1');
set role authenticated;
create temp table rg as select id from public.create_group('返金テスト');
create temp table ri as select public.create_invitation((select id from rg), 'member', 24, 1) j;
reset role;
grant select on rg, ri to authenticated;
select tst.as_user('b1000000-0000-0000-0000-0000000000b1'); set role authenticated; select public.accept_invitation((select j ->> 'code' from ri)); reset role;
create temp table rids as select
  (select id from public.categories where group_id = (select id from rg) and name = '食費') food,
  (select id from public.categories where group_id = (select id from rg) and kind = 'income' limit 1) inc,
  (select id from public.group_members where group_id = (select id from rg) and user_id = 'a1000000-0000-0000-0000-0000000000a1') a,
  (select id from public.group_members where group_id = (select id from rg) and user_id = 'b1000000-0000-0000-0000-0000000000b1') b;
grant select on rids to authenticated;

-- A が 4,000 円を払い、2 人で均等割り。そのうち 1,000 円が返金され、A が受け取った（これも均等割り）
select tst.as_user('a1000000-0000-0000-0000-0000000000a1');
set role authenticated;
select * from public.save_transaction((select id from rg), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 4000, 'occurred_on', '2026-08-10',
  'category_id', (select food from rids), 'payer_member_id', (select a from rids), 'split_mode', 'equal', 'splits', jsonb_build_array((select a from rids), (select b from rids))));
create temp table rf as select * from public.save_transaction((select id from rg), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 1000, 'occurred_on', '2026-08-12', 'is_refund', true,
  'category_id', (select food from rids), 'payer_member_id', (select a from rids), 'split_mode', 'equal', 'splits', jsonb_build_array((select a from rids), (select b from rids))));
select tst.eq((select is_refund || '/' || signed_amount from rf), 'true/-1000', 'refund stored');
-- 立替: A は 3,000 立替えて 1,500 負担 → B が A に 1,500
select tst.eq((select net from public.group_balances((select id from rg)) where member_id = (select a from rids)), 1500::bigint, 'refund reduces payer net');
select tst.eq((select net from public.group_balances((select id from rg)) where member_id = (select b from rids)), -1500::bigint, 'refund reduces burden');
select tst.eq((select amount from public.settlement_suggestions((select id from rg))), 1500::bigint, 'suggestion after refund');
-- 集計: 支出は 3,000
select tst.eq((select (month_summary((select id from rg), '2026-08-01') ->> 'expense')::bigint), 3000::bigint, 'summary expense minus refund');
select tst.eq((select expense from public.monthly_series((select id from rg), '2026-08-01', 1)), 3000::bigint, 'series minus refund');
-- 収入には返金の印を付けられない。真偽値でない値も拒否
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from rg), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'income', 'amount', 100, 'occurred_on', '2026-08-12', 'is_refund', true, 'category_id', (select inc from rids), 'payer_member_id', (select a from rids))), 'KB422', 'refund on income');
select tst.raises(format($$select public.save_transaction(%L, %L::jsonb)$$, (select id from rg), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 100, 'occurred_on', '2026-08-12', 'is_refund', 'yes', 'category_id', (select food from rids), 'payer_member_id', (select a from rids))), 'KB422', 'refund not boolean');
-- 直すときに返金の印を外せる
select * from public.save_transaction((select id from rg), jsonb_build_object('id', (select id from rf), 'version', (select version from rf), 'kind', 'expense', 'amount', 1000, 'occurred_on', '2026-08-12', 'is_refund', false,
  'category_id', (select food from rids), 'payer_member_id', (select a from rids), 'split_mode', 'equal', 'splits', jsonb_build_array((select a from rids), (select b from rids))));
select tst.eq((select (month_summary((select id from rg), '2026-08-01') ->> 'expense')::bigint), 5000::bigint, 'refund flag removed');
select * from public.save_transaction((select id from rg), jsonb_build_object('id', (select id from rf), 'version', (select version from rf) + 1, 'kind', 'expense', 'amount', 1000, 'occurred_on', '2026-08-12', 'is_refund', true,
  'category_id', (select food from rids), 'payer_member_id', (select a from rids), 'split_mode', 'equal', 'splits', jsonb_build_array((select a from rids), (select b from rids))));
reset role;

-- 予算: 8 月から全体 5,000（繰り越す）。8 月の支出 3,000 → 9 月に 2,000 を繰り越して 7,000 使える
select tst.as_user('a1000000-0000-0000-0000-0000000000a1');
set role authenticated;
select * from public.save_budget((select id from rg), 'group', null, null, '2026-08-01', 5000, null, true);
select tst.eq((select spent || '/' || carry || '/' || remaining from public.budget_status((select id from rg), '2026-08-01') where category_id is null), '3000/0/2000', 'first month no carry');
select tst.eq((select carry || '/' || remaining || '/' || rollover from public.budget_status((select id from rg), '2026-09-01') where category_id is null), '2000/7000/true', 'carry surplus');
-- 9 月に 9,000 使う → 7,000 をこえて超過。10 月には 2,000 + 5,000 - 9,000 = -2,000 を持ち越して 3,000 だけ使える
select * from public.save_transaction((select id from rg), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 9000, 'occurred_on', '2026-09-05', 'category_id', (select food from rids), 'payer_member_id', (select b from rids)));
select tst.eq((select over::text from public.budget_status((select id from rg), '2026-09-01') where category_id is null), 'true', 'over with carry');
select tst.eq((select carry || '/' || remaining from public.budget_status((select id from rg), '2026-10-01') where category_id is null), '-2000/3000', 'carry overspending');
-- 個人の予算も、その人の負担（返金で減った分も）で繰り越す: B の負担 8 月 1,500 → 9 月に 500 を繰り越す
select * from public.save_budget((select id from rg), 'personal', null, (select b from rids), '2026-08-01', 2000, null, true);
select tst.eq((select spent || '/' || carry from public.budget_status((select id from rg), '2026-09-01') where scope = 'personal'), '9000/500', 'personal carry');
-- 10 月から繰り越さない予算に変えると、10 月は 0。11 月にまた繰り越すようにしても、10 月で止まる
select * from public.save_budget((select id from rg), 'group', null, null, '2026-10-01', 5000, null, false);
select tst.eq((select carry || '/' || rollover from public.budget_status((select id from rg), '2026-10-01') where category_id is null and scope = 'group'), '0/false', 'no rollover month');
select * from public.save_budget((select id from rg), 'group', null, null, '2026-11-01', 5000, null, true);
select tst.eq((select carry from public.budget_status((select id from rg), '2026-11-01') where category_id is null and scope = 'group'), 0::bigint, 'carry stops at non-rollover month');
select tst.eq((select carry from public.budget_status((select id from rg), '2026-12-01') where category_id is null and scope = 'group'), 5000::bigint, 'carry restarts');
-- 繰り越さない予算は前と同じ（使った額と残り）
select tst.eq((select rollover from public.save_budget((select id from rg), 'group', (select food from rids), null, '2026-08-01', 4000)), false, 'default no rollover');
select tst.eq((select carry || '/' || remaining from public.budget_status((select id from rg), '2026-09-01') where category_id is not null), '0/-5000', 'plain budget unchanged');
-- 内部の関数は直接呼べない
select tst.raises(format($$select public._budget_carry(%L, 'group', null, null, '2026-09-01')$$, (select id from rg)), '42501', 'internal carry denied');
reset role;
