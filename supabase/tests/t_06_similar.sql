-- 似た記録の確認: 自分の 10 分以内の同じ記録と、家族が入れた同じ日・同じ金額の記録（カテゴリが違っても）を返す
\i supabase/tests/helpers.sql
delete from public.invitation_attempts;
select tst.user('a2000000-0000-0000-0000-0000000000a2', 'a2@example.com', 'A2');
select tst.user('b2000000-0000-0000-0000-0000000000b2', 'b2@example.com', 'B2');

select tst.as_user('a2000000-0000-0000-0000-0000000000a2');
set role authenticated;
create temp table sg2 as select id from public.create_group('重複テスト');
create temp table si2 as select public.create_invitation((select id from sg2), 'member', 24, 1) j;
reset role;
grant select on sg2, si2 to authenticated;
select tst.as_user('b2000000-0000-0000-0000-0000000000b2'); set role authenticated; select public.accept_invitation((select j ->> 'code' from si2)); reset role;
create temp table sids as select
  (select id from public.categories where group_id = (select id from sg2) and name = '食費') food,
  (select id from public.categories where group_id = (select id from sg2) and name = '日用品') daily,
  (select id from public.group_members where group_id = (select id from sg2) and user_id = 'a2000000-0000-0000-0000-0000000000a2') a,
  (select id from public.group_members where group_id = (select id from sg2) and user_id = 'b2000000-0000-0000-0000-0000000000b2') b;
grant select on sids to authenticated;

-- B が 2,480 円（食費）を記録
select tst.as_user('b2000000-0000-0000-0000-0000000000b2');
set role authenticated;
select * from public.save_transaction((select id from sg2), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 2480, 'occurred_on', '2026-10-20',
  'category_id', (select food from sids), 'payer_member_id', (select b from sids)));
-- B 自身が同じ内容を入れようとすると、10 分以内なので出る（カテゴリが違うと出ない）
select tst.eq((select count(*) from public.similar_transactions((select id from sg2), 2480, '2026-10-20', (select food from sids))), 1::bigint, 'own recent duplicate');
select tst.eq((select count(*) from public.similar_transactions((select id from sg2), 2480, '2026-10-20', (select daily from sids))), 0::bigint, 'own different category not similar');
reset role;

-- A が同じ日・同じ金額を「日用品」で入れようとすると、B が入れた記録が出る
select tst.as_user('a2000000-0000-0000-0000-0000000000a2');
set role authenticated;
select tst.eq((select count(*) from public.similar_transactions((select id from sg2), 2480, '2026-10-20', (select daily from sids))), 1::bigint, 'other member same day and amount');
select tst.eq((select count(*) from public.similar_transactions((select id from sg2), 2480, '2026-10-21', (select food from sids))), 0::bigint, 'different day not similar');
select tst.eq((select count(*) from public.similar_transactions((select id from sg2), 2481, '2026-10-20', (select food from sids))), 0::bigint, 'different amount not similar');
reset role;

-- B の「自分だけ」の記録は、A には出ない
select tst.as_user('b2000000-0000-0000-0000-0000000000b2');
set role authenticated;
select * from public.save_transaction((select id from sg2), jsonb_build_object('client_request_id', gen_random_uuid(), 'kind', 'expense', 'amount', 990, 'occurred_on', '2026-10-20',
  'category_id', (select food from sids), 'payer_member_id', (select b from sids), 'visibility', 'private'));
reset role;
select tst.as_user('a2000000-0000-0000-0000-0000000000a2');
set role authenticated;
select tst.eq((select count(*) from public.similar_transactions((select id from sg2), 990, '2026-10-20', (select food from sids))), 0::bigint, 'private entry of others hidden');
reset role;
