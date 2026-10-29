-- 貯金（かざすレシートの「貯金」と同じ考え方: 目的ごとの封筒＝目標、通帳＝記録、先取り貯金）
-- 目標は家計簿（グループ）ごと。「自分だけ」の目標は作った人だけが見える。記録は家計簿の上の記録で、実際のお金は動かさない。
-- 金額は円の整数。取り崩しはマイナスの記録。目標の残高はマイナスにならない。

create table public.savings_goals (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 20),
  target bigint not null check (target between 1 and 999999999),
  due_month date check (due_month is null or extract(day from due_month) = 1),   -- 期限の月（その月の 1 日）
  is_main boolean not null default false,                                         -- いちばん大事な目標（1 つだけ）
  auto_amount bigint check (auto_amount is null or auto_amount between 1 and 999999999),   -- 毎月の先取り貯金
  auto_dom int check (auto_dom is null or auto_dom between 1 and 31 or auto_dom = 99),      -- 何日に（99 = 月末）
  start_on date not null,
  visibility public.txn_visibility not null default 'group',
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  version int not null default 1,
  unique (id, group_id),
  check ((auto_amount is null) = (auto_dom is null))
);
create unique index savings_goals_one_main on public.savings_goals (group_id) where is_main and archived_at is null;
create index savings_goals_group_idx on public.savings_goals (group_id) where archived_at is null;

create table public.savings_entries (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null,
  goal_id uuid not null,
  day date not null,
  amount bigint not null check (amount <> 0 and amount between -999999999 and 999999999),
  kind text not null check (kind in ('manual', 'tsumori', 'leftover', 'auto')),   -- 預入・つもり貯金・予算の余り・先取り
  memo text not null default '' check (char_length(memo) <= 60),
  created_by uuid references auth.users (id) on delete set null,
  created_by_member uuid,
  created_at timestamptz not null default now(),
  client_request_id uuid,
  foreign key (goal_id, group_id) references public.savings_goals (id, group_id) on delete cascade,
  unique (group_id, client_request_id)
);
create index savings_entries_goal_idx on public.savings_entries (goal_id, day);
-- 先取り貯金は 1 つの目標で 1 日 1 回（何度生成しても二重にならない）
create unique index savings_entries_auto_uniq on public.savings_entries (goal_id, day) where kind = 'auto';
-- 予算の余りは、同じ月の分を 2 回は回さない（memo に 'YYYY-MM'）
create unique index savings_entries_leftover_uniq on public.savings_entries (group_id, memo) where kind = 'leftover';

alter table public.savings_goals enable row level security;
alter table public.savings_entries enable row level security;
revoke insert, update, delete, truncate on public.savings_goals, public.savings_entries from anon, authenticated;
revoke all on public.savings_goals, public.savings_entries from anon;

create policy savings_goals_read on public.savings_goals for select to authenticated using (
  public.has_role(group_id, 'viewer') and (visibility = 'group' or created_by = auth.uid())
);
create policy savings_entries_read on public.savings_entries for select to authenticated using (
  exists (select 1 from public.savings_goals g where g.id = goal_id and public.has_role(g.group_id, 'viewer') and (g.visibility = 'group' or g.created_by = auth.uid()))
);

-- 見える目標か（作った人以外は「自分だけ」の目標を触れない）
create function public._goal_for(p_goal uuid, p_min public.member_role) returns public.savings_goals
language plpgsql security definer set search_path = public as $$
declare g public.savings_goals;
begin
  select * into g from public.savings_goals where id = p_goal and archived_at is null;
  if g.id is null then perform public._err('KB404', 'not_found'); end if;
  perform public._need(g.group_id, p_min);
  if g.visibility = 'private' and g.created_by is distinct from auth.uid() then perform public._err('KB404', 'not_found'); end if;
  return g;
end $$;

-- 目標を作る・直す。作るのはメンバー以上。直すのは作った人か管理者以上
create function public.save_goal(p_group uuid, p jsonb) returns public.savings_goals
language plpgsql security definer set search_path = public as $$
declare me public.group_members; g public.savings_goals; v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_name text := btrim(coalesce(p ->> 'name', '')); v_target numeric; v_due date; v_main boolean := coalesce((p ->> 'is_main')::boolean, false);
  v_auto numeric := nullif(p ->> 'auto_amount', '')::numeric; v_dom int := nullif(p ->> 'auto_dom', '')::int;
  v_vis public.txn_visibility; v_start date;
begin
  me := public._need(p_group, 'member');
  if char_length(v_name) not between 1 and 20 then perform public._err('KB422', 'goal_name_length', 'name'); end if;
  if jsonb_typeof(p -> 'target') <> 'number' then perform public._err('KB422', 'amount_invalid', 'target'); end if;
  v_target := (p ->> 'target')::numeric;
  if v_target <> floor(v_target) or v_target not between 1 and 999999999 then perform public._err('KB422', 'amount_invalid', 'target'); end if;
  begin v_due := nullif(p ->> 'due_month', '')::date; exception when others then perform public._err('KB422', 'date_invalid', 'due_month'); end;
  if v_due is not null then v_due := date_trunc('month', v_due)::date; end if;
  if (v_auto is null) <> (v_dom is null) then perform public._err('KB422', 'auto_invalid', 'auto_amount'); end if;
  if v_auto is not null and (v_auto <> floor(v_auto) or v_auto not between 1 and 999999999) then perform public._err('KB422', 'amount_invalid', 'auto_amount'); end if;
  if v_dom is not null and not (v_dom between 1 and 31 or v_dom = 99) then perform public._err('KB422', 'auto_invalid', 'auto_dom'); end if;
  begin v_vis := coalesce(p ->> 'visibility', 'group')::public.txn_visibility; exception when others then perform public._err('KB422', 'enum_invalid', 'visibility'); end;
  begin v_start := coalesce(nullif(p ->> 'start_on', '')::date, public.today_jst()); exception when others then perform public._err('KB422', 'date_invalid', 'start_on'); end;
  if v_main and v_vis = 'private' then perform public._err('KB422', 'main_private', 'is_main'); end if;   -- いちばん大事な目標は全員に見えるもの
  if v_id is null then
    if (select count(*) from public.savings_goals where group_id = p_group and archived_at is null) >= 10 then perform public._err('KB422', 'too_many_goals'); end if;
  else
    g := public._goal_for(v_id, 'member');
    if g.group_id <> p_group then perform public._err('KB404', 'not_found'); end if;
    if me.role = 'member' and g.created_by is distinct from auth.uid() then perform public._err('KB403', 'forbidden'); end if;
    if (p ->> 'version')::int is distinct from g.version then perform public._err('KB409', 'conflict'); end if;
  end if;
  if v_main then update public.savings_goals set is_main = false, updated_at = now() where group_id = p_group and is_main and id is distinct from v_id; end if;
  if v_id is null then
    insert into public.savings_goals (group_id, name, target, due_month, is_main, auto_amount, auto_dom, start_on, visibility, created_by)
    values (p_group, v_name, v_target::bigint, v_due, v_main, v_auto::bigint, v_dom, v_start, v_vis, auth.uid()) returning * into g;
  else
    update public.savings_goals set name = v_name, target = v_target::bigint, due_month = v_due, is_main = v_main, auto_amount = v_auto::bigint, auto_dom = v_dom,
      start_on = v_start, visibility = v_vis, updated_at = now(), version = version + 1 where id = v_id returning * into g;
  end if;
  return g;
end $$;

-- 目標をやめる（記録は消さずに、目標ごと見えなくする）
create function public.archive_goal(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g public.savings_goals; me public.group_members;
begin
  g := public._goal_for(p_id, 'member');
  me := public.my_member(g.group_id);
  if me.role = 'member' and g.created_by is distinct from auth.uid() then perform public._err('KB403', 'forbidden'); end if;
  update public.savings_goals set archived_at = now(), is_main = false, updated_at = now(), version = version + 1 where id = p_id;
end $$;

-- 目標の残高（記録の合計。先取り貯金の分も記録として入っている）
create function public._goal_balance(p_goal uuid) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount), 0)::bigint from public.savings_entries where goal_id = p_goal
$$;

-- 貯金した・取り崩した・つもり貯金・予算の余り。取り崩しは残高まで
create function public.record_saving(p_goal uuid, p_day date, p_amount bigint, p_kind text, p_memo text, p_client_request_id uuid) returns public.savings_entries
language plpgsql security definer set search_path = public as $$
declare g public.savings_goals; me public.group_members; e public.savings_entries;
begin
  g := public._goal_for(p_goal, 'member');
  me := public.my_member(g.group_id);
  if p_client_request_id is null then perform public._err('KB422', 'client_request_id_required', 'client_request_id'); end if;
  select * into e from public.savings_entries where group_id = g.group_id and client_request_id = p_client_request_id;
  if e.id is not null then return e; end if;   -- 二重送信
  if p_kind is null or p_kind not in ('manual', 'tsumori', 'leftover') then perform public._err('KB422', 'enum_invalid', 'kind'); end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 999999999 then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  if p_kind <> 'manual' and p_amount < 0 then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  if p_day is null or p_day < date '2000-01-01' or p_day > public.today_jst() then perform public._err('KB422', 'date_invalid', 'day'); end if;
  if char_length(coalesce(p_memo, '')) > 60 then perform public._err('KB422', 'memo_too_long', 'memo'); end if;
  if p_kind = 'leftover' and coalesce(p_memo, '') !~ '^\d{4}-\d{2}$' then perform public._err('KB422', 'leftover_month', 'memo'); end if;
  perform 1 from public.savings_goals where id = g.id for update;   -- 同じ目標の記録は順番に
  if p_amount < 0 and public._goal_balance(g.id) + p_amount < 0 then perform public._err('KB422', 'saving_exceeds_balance', 'amount'); end if;
  begin
    insert into public.savings_entries (group_id, goal_id, day, amount, kind, memo, created_by, created_by_member, client_request_id)
    values (g.group_id, g.id, p_day, p_amount, p_kind, coalesce(p_memo, ''), auth.uid(), me.id, p_client_request_id) returning * into e;
  exception when unique_violation then perform public._err('KB409', 'leftover_already', 'memo');
  end;
  return e;
end $$;

-- 記録を消す（作った人か管理者以上）。消すと残高がマイナスになるときは消せない
create function public.delete_saving(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.savings_entries; g public.savings_goals; me public.group_members;
begin
  select * into e from public.savings_entries where id = p_id;
  if e.id is null then perform public._err('KB404', 'not_found'); end if;
  g := public._goal_for(e.goal_id, 'member');
  me := public.my_member(g.group_id);
  if me.role = 'member' and e.created_by is distinct from auth.uid() then perform public._err('KB403', 'forbidden'); end if;
  if e.kind = 'auto' then perform public._err('KB422', 'auto_entry', 'kind'); end if;   -- 先取りは目標の設定で止める
  perform 1 from public.savings_goals where id = g.id for update;
  if public._goal_balance(g.id) - e.amount < 0 then perform public._err('KB422', 'saving_exceeds_balance', 'amount'); end if;
  delete from public.savings_entries where id = p_id;
end $$;

-- 先取り貯金の日（月の dom 日。その月にない日と 99 は月末）
create function public._auto_day(m date, dom int) returns date language sql immutable as $$
  select (date_trunc('month', m) + make_interval(days => least(dom, extract(day from (date_trunc('month', m) + interval '1 month - 1 day'))::int) - 1))::date
$$;

-- 期日の来た先取り貯金を記録にする。何度呼んでも同じ（目標と日の一意制約）
create function public.generate_due_savings(p_group uuid) returns int
language plpgsql security definer set search_path = public as $$
declare g public.savings_goals; m date; d date; n int := 0; today date := public.today_jst(); k int;
begin
  perform public._need(p_group, 'member');
  for g in select * from public.savings_goals where group_id = p_group and archived_at is null and auto_amount is not null order by id for update skip locked loop
    m := date_trunc('month', g.start_on)::date;
    while m <= today loop
      d := public._auto_day(m, g.auto_dom);
      if d >= g.start_on and d <= today then
        insert into public.savings_entries (group_id, goal_id, day, amount, kind, memo, created_by)
        values (g.group_id, g.id, d, g.auto_amount, 'auto', '先取り貯金', g.created_by)
        on conflict do nothing;
        get diagnostics k = row_count; n := n + k;
      end if;
      m := (m + interval '1 month')::date;
    end loop;
  end loop;
  return n;
end $$;

-- 目標ごとの進み具合。per_month は「期限までに届くには、今月から毎月いくら」（残り ÷ 期限の月までの月数）
create function public.savings_status(p_group uuid)
returns table (goal_id uuid, saved bigint, remaining bigint, ratio numeric, done boolean, months_left int, per_month bigint, overdue boolean, on_track boolean, this_month bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare cur date := date_trunc('month', public.today_jst())::date;
begin
  perform public._need(p_group, 'viewer');
  return query
  with s as (
    select g.*, greatest(0, coalesce((select sum(e.amount) from public.savings_entries e where e.goal_id = g.id), 0))::bigint as sv,
      coalesce((select sum(e.amount) from public.savings_entries e where e.goal_id = g.id and e.day >= cur and e.day < cur + interval '1 month'), 0)::bigint as tm
    from public.savings_goals g
    where g.group_id = p_group and g.archived_at is null and (g.visibility = 'group' or g.created_by = auth.uid())
  ), t as (
    select s.*, greatest(0, s.target - s.sv) as lf,
      case when s.due_month is null then null else ((extract(year from s.due_month) * 12 + extract(month from s.due_month)) - (extract(year from cur) * 12 + extract(month from cur)) + 1)::int end as mo
    from s
  )
  select t.id, t.sv, t.lf, round(least(1, t.sv::numeric / t.target), 4), t.sv >= t.target, t.mo,
    case when t.lf > 0 and t.mo is not null and t.mo > 0 then ceil(t.lf::numeric / t.mo)::bigint end,
    t.due_month is not null and t.mo <= 0 and t.lf > 0,
    case when t.lf > 0 and t.mo is not null and t.mo > 0 then coalesce(t.auto_amount, 0) >= ceil(t.lf::numeric / t.mo) end,
    t.tm
  from t order by t.is_main desc, t.created_at;
end $$;

-- 通帳（日付順。差引残高つき）。p_goal を渡すとその目標だけ
create function public.savings_passbook(p_group uuid, p_goal uuid default null)
returns table (id uuid, goal_id uuid, goal_name text, day date, amount bigint, kind text, memo text, balance bigint, created_by uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public._need(p_group, 'viewer');
  return query
  select e.id, e.goal_id, g.name, e.day, e.amount, e.kind, e.memo,
    (sum(e.amount) over (order by e.day, e.created_at, e.id rows between unbounded preceding and current row))::bigint, e.created_by
  from public.savings_entries e join public.savings_goals g on g.id = e.goal_id
  where e.group_id = p_group and g.archived_at is null and (g.visibility = 'group' or g.created_by = auth.uid())
    and (p_goal is null or e.goal_id = p_goal)
  order by e.day, e.created_at, e.id;
end $$;

-- 月ごとの預け入れ・引き出し（グラフ用）
create function public.savings_series(p_group uuid, p_end_month date, p_months int default 12)
returns table (month date, deposit bigint, withdrawal bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare e date := date_trunc('month', p_end_month)::date;
begin
  perform public._need(p_group, 'viewer');
  if p_months not between 1 and 36 then perform public._err('KB422', 'months_range', 'months'); end if;
  return query
  select ms::date,
    coalesce(sum(x.amount) filter (where x.amount > 0), 0)::bigint,
    coalesce(-sum(x.amount) filter (where x.amount < 0), 0)::bigint
  from generate_series(e - make_interval(months => p_months - 1), e, interval '1 month') ms
  left join (select en.day, en.amount from public.savings_entries en join public.savings_goals g on g.id = en.goal_id
             where en.group_id = p_group and g.archived_at is null and (g.visibility = 'group' or g.created_by = auth.uid())) x
    on x.day >= ms and x.day < ms + interval '1 month'
  group by ms order by ms;
end $$;

-- 操作の履歴
create trigger audit_savings_goals after insert or update on public.savings_goals for each row execute function public._audit();
create trigger audit_savings_entries after insert or delete on public.savings_entries for each row execute function public._audit();

-- 実行権限（既定では誰も実行できない。アプリが使うものだけ許可）
grant execute on function
  public.save_goal(uuid, jsonb), public.archive_goal(uuid), public.record_saving(uuid, date, bigint, text, text, uuid), public.delete_saving(uuid),
  public.generate_due_savings(uuid), public.savings_status(uuid), public.savings_passbook(uuid, uuid), public.savings_series(uuid, date, int)
to authenticated;
revoke execute on function
  public.save_goal(uuid, jsonb), public.archive_goal(uuid), public.record_saving(uuid, date, bigint, text, text, uuid), public.delete_saving(uuid),
  public.generate_due_savings(uuid), public.savings_status(uuid), public.savings_passbook(uuid, uuid), public.savings_series(uuid, date, int)
from public, anon;
revoke execute on function public._goal_for(uuid, public.member_role), public._goal_balance(uuid), public._auto_day(date, int) from public, anon, authenticated;
