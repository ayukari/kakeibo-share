-- 返金と、予算の余りを翌月に回す（GitHub の先人調査: split-pro の返金、Actual Budget の rollover）
--   返金: 支出の取引に「返金」の印を付ける。金額は正のまま持ち、集計と立替では引き算する（signed_amount）
--         分担つきの返金は、払った人が受け取り、分担した人の負担も同じ割合で減る
--   繰り越し: 予算ごとに選ぶ。前の月の余りを足し、使いすぎを引く。繰り越さない月があれば、そこで 0 から数え直す

-- ---------- 返金 ----------
alter table public.transactions add column is_refund boolean not null default false;
alter table public.transactions add constraint transactions_refund_expense check (kind = 'expense' or not is_refund);
alter table public.transactions add column signed_amount bigint generated always as (case when is_refund then -amount else amount end) stored;

-- p: { …, is_refund? }（それ以外は前と同じ）
create or replace function public.save_transaction(p_group uuid, p jsonb) returns public.transactions
language plpgsql security definer set search_path = public as $$
declare me public.group_members; t public.transactions; old public.transactions;
  v_id uuid := nullif(p ->> 'id', '')::uuid; v_amount numeric; v_date date; v_kind public.txn_kind; v_vis public.txn_visibility; v_split public.split_mode; v_memo text;
  v_refund boolean;
begin
  me := public._need(p_group, 'member');
  begin
    v_kind := (p ->> 'kind')::public.txn_kind;
    v_vis := coalesce(p ->> 'visibility', 'group')::public.txn_visibility;
    v_split := coalesce(p ->> 'split_mode', 'none')::public.split_mode;
  exception when others then perform public._err('KB422', 'enum_invalid', 'kind');
  end;
  if jsonb_typeof(coalesce(p -> 'is_refund', 'false'::jsonb)) <> 'boolean' then perform public._err('KB422', 'refund_invalid', 'is_refund'); end if;
  v_refund := coalesce((p ->> 'is_refund')::boolean, false);
  if v_refund and v_kind <> 'expense' then perform public._err('KB422', 'refund_income', 'is_refund'); end if;
  if jsonb_typeof(p -> 'amount') <> 'number' then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  v_amount := (p ->> 'amount')::numeric;
  if v_amount <> floor(v_amount) or v_amount < 1 or v_amount > 999999999 then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  begin v_date := (p ->> 'occurred_on')::date; exception when others then perform public._err('KB422', 'date_invalid', 'occurred_on'); end;
  if v_date is null or v_date < date '2000-01-01' or v_date > public.today_jst() + 366 then perform public._err('KB422', 'date_invalid', 'occurred_on'); end if;
  v_memo := coalesce(p ->> 'memo', '');
  if char_length(v_memo) > 500 then perform public._err('KB422', 'memo_too_long', 'memo'); end if;
  if v_kind = 'income' and v_split <> 'none' then perform public._err('KB422', 'split_income', 'split_mode'); end if;
  if v_vis = 'private' and v_split <> 'none' then perform public._err('KB422', 'split_private', 'split_mode'); end if;
  if not exists (select 1 from public.categories where id = (p ->> 'category_id')::uuid and group_id = p_group and kind = v_kind and (archived_at is null or v_id is not null)) then
    perform public._err('KB422', 'category_invalid', 'category_id');
  end if;
  if not exists (select 1 from public.group_members where id = (p ->> 'payer_member_id')::uuid and group_id = p_group and (status = 'active' or v_id is not null)) then
    perform public._err('KB422', 'payer_invalid', 'payer_member_id');
  end if;
  if nullif(p ->> 'payment_method_id', '') is not null and not exists (select 1 from public.payment_methods where id = (p ->> 'payment_method_id')::uuid and group_id = p_group) then
    perform public._err('KB422', 'payment_method_invalid', 'payment_method_id');
  end if;

  if v_id is null then
    if nullif(p ->> 'client_request_id', '') is null then perform public._err('KB422', 'client_request_id_required', 'client_request_id'); end if;
    select * into t from public.transactions where group_id = p_group and client_request_id = (p ->> 'client_request_id')::uuid;
    if t.id is not null then return t; end if;   -- 二重送信
    insert into public.transactions (group_id, kind, amount, occurred_on, category_id, payer_member_id, payment_method_id, memo, visibility, split_mode, is_refund, created_by, created_by_member, updated_by, client_request_id)
    values (p_group, v_kind, v_amount::bigint, v_date, (p ->> 'category_id')::uuid, (p ->> 'payer_member_id')::uuid, nullif(p ->> 'payment_method_id', '')::uuid, v_memo, v_vis, v_split, v_refund, auth.uid(), me.id, auth.uid(), (p ->> 'client_request_id')::uuid)
    returning * into t;
  else
    select * into old from public.transactions where id = v_id and group_id = p_group and status = 'active' for update;
    if old.id is null then perform public._err('KB404', 'not_found'); end if;
    if old.visibility = 'private' and old.created_by is distinct from auth.uid() then perform public._err('KB404', 'not_found'); end if;
    if me.role = 'member' and old.created_by is distinct from auth.uid() then perform public._err('KB403', 'forbidden'); end if;
    if (p ->> 'version')::int is distinct from old.version then perform public._err('KB409', 'conflict'); end if;
    update public.transactions set kind = v_kind, amount = v_amount::bigint, occurred_on = v_date, category_id = (p ->> 'category_id')::uuid,
      payer_member_id = (p ->> 'payer_member_id')::uuid, payment_method_id = nullif(p ->> 'payment_method_id', '')::uuid, memo = v_memo,
      visibility = v_vis, split_mode = v_split, is_refund = v_refund, updated_by = auth.uid(), updated_at = now(), version = version + 1
    where id = v_id returning * into t;
  end if;
  perform public._write_splits(t, coalesce(p -> 'splits', '[]'::jsonb));
  return t;
end $$;

-- 立替と負担: 返金は引く（払った人は受け取った分だけ立替が減り、分担した人は負担が減る）
create or replace function public.group_balances(p_group uuid) returns table (member_id uuid, display_name text, status public.member_status, paid bigint, burden bigint, settled_out bigint, settled_in bigint, net bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public._need(p_group, 'viewer');
  return query
  with p as (select payer_member_id m, sum(signed_amount)::bigint v from public.transactions where group_id = p_group and status = 'active' and kind = 'expense' and split_mode <> 'none' group by 1),
       b as (select s.member_id m, sum(case when t.is_refund then -s.amount else s.amount end)::bigint v from public.transaction_splits s join public.transactions t on t.id = s.transaction_id
             where t.group_id = p_group and t.status = 'active' group by 1),
       so as (select from_member m, sum(amount)::bigint v from public.settlements where group_id = p_group and status = 'confirmed' group by 1),
       si as (select to_member m, sum(amount)::bigint v from public.settlements where group_id = p_group and status = 'confirmed' group by 1)
  select m.id, m.display_name, m.status, coalesce(p.v, 0), coalesce(b.v, 0), coalesce(so.v, 0), coalesce(si.v, 0),
         coalesce(p.v, 0) - coalesce(b.v, 0) + coalesce(so.v, 0) - coalesce(si.v, 0)
  from public.group_members m left join p on p.m = m.id left join b on b.m = m.id left join so on so.m = m.id left join si on si.m = m.id
  where m.group_id = p_group and (m.status = 'active' or abs(coalesce(p.v, 0)) + abs(coalesce(b.v, 0)) + coalesce(so.v, 0) + coalesce(si.v, 0) > 0)
  order by m.joined_at, m.id;
end $$;

create or replace function public.month_summary(p_group uuid, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m0 date := date_trunc('month', p_month)::date; r jsonb;
begin
  perform public._need(p_group, 'viewer');
  with t as (select * from public.transactions where group_id = p_group and status = 'active' and visibility = 'group'),
  cur as (select * from t where occurred_on >= m0 and occurred_on < m0 + interval '1 month'),
  prev as (select * from t where occurred_on >= m0 - interval '1 month' and occurred_on < m0)
  select jsonb_build_object(
    'month', m0,
    'income', coalesce((select sum(amount) from cur where kind = 'income'), 0),
    'expense', coalesce((select sum(signed_amount) from cur where kind = 'expense'), 0),
    'prev_income', coalesce((select sum(amount) from prev where kind = 'income'), 0),
    'prev_expense', coalesce((select sum(signed_amount) from prev where kind = 'expense'), 0),
    'by_category', coalesce((select jsonb_agg(jsonb_build_object('category_id', category_id, 'amount', s) order by s desc) from (select category_id, sum(signed_amount) s from cur where kind = 'expense' group by 1) x), '[]'::jsonb),
    'by_payer', coalesce((select jsonb_agg(jsonb_build_object('member_id', payer_member_id, 'amount', s) order by s desc) from (select payer_member_id, sum(signed_amount) s from cur where kind = 'expense' group by 1) x), '[]'::jsonb),
    'by_burden', coalesce((select jsonb_agg(jsonb_build_object('member_id', m, 'amount', s) order by s desc) from (
        select m, sum(a) s from (select sp.member_id m, case when cur.is_refund then -sp.amount else sp.amount end a from cur join public.transaction_splits sp on sp.transaction_id = cur.id where cur.split_mode <> 'none'
                                 union all select payer_member_id, signed_amount from cur where kind = 'expense' and split_mode = 'none') u group by 1) x), '[]'::jsonb)
  ) into r;
  r := r || jsonb_build_object('balance', (r ->> 'income')::bigint - (r ->> 'expense')::bigint);
  return r;
end $$;

create or replace function public.monthly_series(p_group uuid, p_end_month date, p_months int default 12) returns table (month date, income bigint, expense bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare e date := date_trunc('month', p_end_month)::date;
begin
  perform public._need(p_group, 'viewer');
  if p_months not between 1 and 36 then perform public._err('KB422', 'months_range', 'months'); end if;
  return query
  select ms::date, coalesce(sum(t.amount) filter (where t.kind = 'income'), 0)::bigint, coalesce(sum(t.signed_amount) filter (where t.kind = 'expense'), 0)::bigint
  from generate_series(e - make_interval(months => p_months - 1), e, interval '1 month') ms
  left join public.transactions t on t.group_id = p_group and t.status = 'active' and t.visibility = 'group' and t.occurred_on >= ms and t.occurred_on < ms + interval '1 month'
  group by ms order by ms;
end $$;

-- ---------- 予算の繰り越し ----------
alter table public.budgets add column rollover boolean not null default false;

drop function public.save_budget(uuid, public.budget_scope, uuid, uuid, date, bigint, date);
create function public.save_budget(p_group uuid, p_scope public.budget_scope, p_category uuid, p_member uuid, p_start_month date, p_amount bigint,
  p_end_month date default null, p_rollover boolean default false)
returns public.budgets language plpgsql security definer set search_path = public as $$
declare r public.budgets; sm date := date_trunc('month', p_start_month)::date; em date := date_trunc('month', p_end_month)::date;
begin
  perform public._need(p_group, 'admin');
  if p_amount is null or p_amount not between 1 and 999999999 then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  if p_category is not null and not exists (select 1 from public.categories where id = p_category and group_id = p_group and kind = 'expense') then
    perform public._err('KB422', 'category_invalid', 'category_id');
  end if;
  if (p_scope = 'personal') <> (p_member is not null) then perform public._err('KB422', 'budget_member', 'member_id'); end if;
  insert into public.budgets (group_id, scope, category_id, member_id, start_month, end_month, amount, rollover, created_by)
  values (p_group, p_scope, p_category, p_member, sm, em, p_amount, coalesce(p_rollover, false), auth.uid())
  on conflict (group_id, scope, coalesce(category_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(member_id, '00000000-0000-0000-0000-000000000000'::uuid), start_month)
  do update set amount = excluded.amount, end_month = excluded.end_month, rollover = excluded.rollover, updated_at = now(), version = budgets.version + 1
  returning * into r;
  return r;
end $$;

-- 内部用: その月に有効な予算（同じ対象で、始まりがいちばん新しいもの）
create function public._budget_for(p_group uuid, p_scope public.budget_scope, p_category uuid, p_member uuid, p_month date) returns public.budgets
language sql stable security definer set search_path = public as $$
  select b.* from public.budgets b
  where b.group_id = p_group and b.scope = p_scope and b.category_id is not distinct from p_category and b.member_id is not distinct from p_member
    and b.start_month <= p_month and (b.end_month is null or b.end_month >= p_month)
  order by b.start_month desc limit 1
$$;

-- 内部用: その月に予算の対象として使った額（返金は引く）
--   グループの予算: 公開範囲「グループ」の支出（カテゴリの予算はそのカテゴリだけ）
--   個人の予算: その人の負担（分担があれば分担額、なければ自分が払った支出）
create function public._budget_spent(p_group uuid, p_scope public.budget_scope, p_category uuid, p_member uuid, p_month date) returns bigint
language sql stable security definer set search_path = public as $$
  with tx as (
    select * from public.transactions t where t.group_id = p_group and t.status = 'active' and t.kind = 'expense' and t.visibility = 'group'
      and t.occurred_on >= p_month and t.occurred_on < p_month + interval '1 month' and (p_category is null or t.category_id = p_category)
  )
  select coalesce(case when p_scope = 'group' then (select sum(signed_amount) from tx)
    else (select sum(a) from (
      select case when tx.is_refund then -s.amount else s.amount end a from tx join public.transaction_splits s on s.transaction_id = tx.id where tx.split_mode <> 'none' and s.member_id = p_member
      union all select tx.signed_amount from tx where tx.split_mode = 'none' and tx.payer_member_id = p_member) u) end, 0)::bigint
$$;

-- 内部用: 前の月から繰り越す額。さかのぼって、繰り越さない月か予算のない月に当たったら、そこで止める（最大 10 年）
create function public._budget_carry(p_group uuid, p_scope public.budget_scope, p_category uuid, p_member uuid, p_month date) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare mm date := (p_month - interval '1 month')::date; b public.budgets; months date[] := '{}'; amounts bigint[] := '{}'; carry bigint := 0; i int;
begin
  loop
    exit when mm < p_month - interval '120 months';
    b := public._budget_for(p_group, p_scope, p_category, p_member, mm);
    exit when b.id is null or not b.rollover;
    months := mm || months; amounts := b.amount || amounts;
    mm := (mm - interval '1 month')::date;
  end loop;
  for i in 1..coalesce(array_length(months, 1), 0) loop
    carry := carry + amounts[i] - public._budget_spent(p_group, p_scope, p_category, p_member, months[i]);
  end loop;
  return carry;
end $$;

-- その月の予算の状態。amount は毎月の額、carry は前の月からの繰り越し（繰り越さない予算は 0）。残りと超過は amount + carry で見る
drop function public.budget_status(uuid, date);
create function public.budget_status(p_group uuid, p_month date)
returns table (budget_id uuid, scope public.budget_scope, category_id uuid, member_id uuid, amount bigint, spent bigint, remaining bigint, ratio numeric, over boolean,
  carry bigint, rollover boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare m0 date := date_trunc('month', p_month)::date;
begin
  perform public._need(p_group, 'viewer');
  return query
  with eff as (
    select distinct on (b.scope, b.category_id, b.member_id) b.* from public.budgets b
    where b.group_id = p_group and b.start_month <= m0 and (b.end_month is null or b.end_month >= m0)
    order by b.scope, b.category_id, b.member_id, b.start_month desc
  ), x as (
    select e.*, public._budget_spent(p_group, e.scope, e.category_id, e.member_id, m0) sp,
      case when e.rollover then public._budget_carry(p_group, e.scope, e.category_id, e.member_id, m0) else 0 end cr
    from eff e
  )
  select x.id, x.scope, x.category_id, x.member_id, x.amount, x.sp, x.amount + x.cr - x.sp,
    round(x.sp::numeric / greatest(x.amount + x.cr, 1), 4), x.sp > x.amount + x.cr, x.cr, x.rollover
  from x
  order by x.scope, x.category_id nulls first;
end $$;

-- 実行権限（既定では誰も実行できない。アプリが使うものだけ許可）
grant execute on function
  public.save_budget(uuid, public.budget_scope, uuid, uuid, date, bigint, date, boolean), public.budget_status(uuid, date)
to authenticated;
revoke execute on function
  public.save_budget(uuid, public.budget_scope, uuid, uuid, date, bigint, date, boolean), public.budget_status(uuid, date)
from public, anon;
revoke execute on function
  public._budget_for(uuid, public.budget_scope, uuid, uuid, date), public._budget_spent(uuid, public.budget_scope, uuid, uuid, date),
  public._budget_carry(uuid, public.budget_scope, uuid, uuid, date)
from public, anon, authenticated;
