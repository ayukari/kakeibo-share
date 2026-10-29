-- 貯金: 目標・記録・取り崩しの上限・予算の余りは 1 か月 1 回・先取り貯金（何度生成しても同じ）・通帳の残高・権限・自分だけの目標
\i supabase/tests/helpers.sql
delete from public.invitation_attempts;
select tst.user('d0000000-0000-0000-0000-00000000000d', 'd@example.com', 'D');
select tst.user('e0000000-0000-0000-0000-00000000000e', 'e@example.com', 'E');
select tst.user('f0000000-0000-0000-0000-00000000000f', 'f@example.com', 'F');

select tst.as_user('d0000000-0000-0000-0000-00000000000d');
set role authenticated;
create temp table sg as select id from public.create_group('貯金テスト');
create temp table si as select public.create_invitation((select id from sg), 'member', 24, 1) m, public.create_invitation((select id from sg), 'viewer', 24, 1) v;
reset role;
grant select on sg, si to authenticated;
select tst.as_user('e0000000-0000-0000-0000-00000000000e'); set role authenticated; select public.accept_invitation((select m ->> 'code' from si)); reset role;
select tst.as_user('f0000000-0000-0000-0000-00000000000f'); set role authenticated; select public.accept_invitation((select v ->> 'code' from si)); reset role;

-- D が「旅行」（いちばん大事・来年の今月まで 120,000 円）を作る
select tst.as_user('d0000000-0000-0000-0000-00000000000d');
set role authenticated;
create temp table g1 as select * from public.save_goal((select id from sg), jsonb_build_object('name', '旅行', 'target', 120000, 'is_main', true,
  'due_month', (date_trunc('month', public.today_jst()) + interval '11 months')::date));
reset role;
grant select on g1 to authenticated;
select tst.eq((select is_main from g1), true, 'main goal');

-- 記録: 預け入れ 30,000（二重送信でも 1 件）、取り崩し 5,000、残高をこえる取り崩しは拒否
select tst.as_user('e0000000-0000-0000-0000-00000000000e');
set role authenticated;
select public.record_saving((select id from g1), public.today_jst(), 30000, 'manual', '', '11111111-1111-1111-1111-111111111111');
select public.record_saving((select id from g1), public.today_jst(), 30000, 'manual', '', '11111111-1111-1111-1111-111111111111');
select tst.eq((select count(*) from public.savings_entries where goal_id = (select id from g1)), 1::bigint, 'idempotent deposit');
select public.record_saving((select id from g1), public.today_jst(), -5000, 'manual', '引き出し', gen_random_uuid());
select tst.raises(format($$select public.record_saving(%L, public.today_jst(), -25001, 'manual', '', gen_random_uuid())$$, (select id from g1)), 'KB422', 'withdraw over balance');
select tst.raises(format($$select public.record_saving(%L, public.today_jst() + 1, 100, 'manual', '', gen_random_uuid())$$, (select id from g1)), 'KB422', 'future day');
select tst.raises(format($$select public.record_saving(%L, public.today_jst(), -100, 'tsumori', '', gen_random_uuid())$$, (select id from g1)), 'KB422', 'negative tsumori');
-- 予算の余りは同じ月を 2 回は回せない
select public.record_saving((select id from g1), public.today_jst(), 4000, 'leftover', '2026-09', gen_random_uuid());
select tst.raises(format($$select public.record_saving(%L, public.today_jst(), 4000, 'leftover', '2026-09', gen_random_uuid())$$, (select id from g1)), 'KB409', 'leftover twice');
select tst.eq((select saved from public.savings_status((select id from sg)) where goal_id = (select id from g1)), 29000::bigint, 'saved = 30000 - 5000 + 4000');
-- 期限まで 12 か月（今月を含む）。残り 91,000 ÷ 12 = 7,584（切り上げ）
select tst.eq((select per_month from public.savings_status((select id from sg)) where goal_id = (select id from g1)), 7584::bigint, 'per month');
select tst.eq((select months_left from public.savings_status((select id from sg)) where goal_id = (select id from g1)), 12, 'months left');
-- メンバーは他人の目標を直せない
select tst.raises(format($$select public.save_goal(%L, jsonb_build_object('id', %L, 'version', 1, 'name', 'x', 'target', 1))$$, (select id from sg), (select id from g1)), 'KB403', 'member cannot edit others goal');
reset role;

-- 通帳: 日付順の差引残高。最後の行が残高と同じ
select tst.as_user('d0000000-0000-0000-0000-00000000000d');
set role authenticated;
select tst.eq((select (array_agg(balance))[count(*)] from public.savings_passbook((select id from sg), (select id from g1))), 29000::bigint, 'passbook balance');
-- 先取り貯金: 3 か月前の 1 日から、毎月の月末に 10,000。何度生成しても同じ件数
create temp table g2 as select * from public.save_goal((select id from sg), jsonb_build_object('name', 'もしものとき', 'target', 300000, 'auto_amount', 10000, 'auto_dom', 99,
  'start_on', (date_trunc('month', public.today_jst()) - interval '3 months')::date));
select public.generate_due_savings((select id from sg));
select public.generate_due_savings((select id from sg));
reset role;
grant select on g2 to authenticated;
select tst.eq((select count(*) from public.savings_entries where goal_id = (select id from g2) and kind = 'auto'),
  (case when public.today_jst() = (date_trunc('month', public.today_jst()) + interval '1 month - 1 day')::date then 4 else 3 end)::bigint, 'auto saves once per month end');
select tst.eq((select bool_and(day = (date_trunc('month', day) + interval '1 month - 1 day')::date) from public.savings_entries where goal_id = (select id from g2)), true, 'auto on month end');
-- いちばん大事は 1 つだけ: g2 を main にすると g1 が外れる
select tst.as_user('d0000000-0000-0000-0000-00000000000d');
set role authenticated;
select public.save_goal((select id from sg), jsonb_build_object('id', (select id from g2), 'version', 1, 'name', 'もしものとき', 'target', 300000, 'is_main', true, 'auto_amount', 10000, 'auto_dom', 99, 'start_on', (select start_on from g2)));
reset role;
select tst.eq((select count(*) from public.savings_goals where group_id = (select id from sg) and is_main), 1::bigint, 'one main');
select tst.eq((select is_main from public.savings_goals where id = (select id from g1)), false, 'old main cleared');

-- 閲覧のみは記録できない。見ることはできる
select tst.as_user('f0000000-0000-0000-0000-00000000000f');
set role authenticated;
select tst.raises(format($$select public.record_saving(%L, public.today_jst(), 100, 'manual', '', gen_random_uuid())$$, (select id from g1)), 'KB403', 'viewer cannot save');
select tst.eq((select count(*) from public.savings_goals), 2::bigint, 'viewer sees goals');
reset role;

-- 自分だけの目標は、ほかの人には見えず、記録もできない
select tst.as_user('e0000000-0000-0000-0000-00000000000e');
set role authenticated;
create temp table g3 as select * from public.save_goal((select id from sg), jsonb_build_object('name', 'へそくり', 'target', 50000, 'visibility', 'private'));
reset role;
grant select on g3 to authenticated;
select tst.as_user('d0000000-0000-0000-0000-00000000000d');
set role authenticated;
select tst.eq((select count(*) from public.savings_goals where id = (select id from g3)), 0::bigint, 'private goal hidden');
select tst.raises(format($$select public.record_saving(%L, public.today_jst(), 100, 'manual', '', gen_random_uuid())$$, (select id from g3)), 'KB404', 'private goal not writable');
select tst.eq((select count(*) from public.savings_status((select id from sg))), 2::bigint, 'status excludes private of others');
-- 直接の書き込みはできない
select tst.raises($$insert into public.savings_entries (group_id, goal_id, day, amount, kind) values (gen_random_uuid(), gen_random_uuid(), current_date, 1, 'manual')$$, '42501', 'direct insert denied');
reset role;

-- 記録を消す: 消すと残高がマイナスになるなら消せない（預け入れ 30,000 を消すと −1,000）
select tst.as_user('e0000000-0000-0000-0000-00000000000e');
set role authenticated;
select tst.raises(format($$select public.delete_saving(%L)$$, (select id from public.savings_entries where goal_id = (select id from g1) and amount = 30000)), 'KB422', 'delete would go negative');
select public.delete_saving((select id from public.savings_entries where goal_id = (select id from g1) and amount = -5000));
reset role;
select tst.eq((select sum(amount) from public.savings_entries where goal_id = (select id from g1)), 34000::numeric, 'after delete');
-- 履歴に残る
select tst.eq((select count(*) > 0 from public.audit_logs where target_table = 'savings_entries'), true, 'audited');
