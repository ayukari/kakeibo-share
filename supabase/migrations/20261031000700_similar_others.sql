-- 似た記録の確認を、家族が別々に入れた同じ支出にも広げる（先人調査: 共有家計簿で「同じ支出を二人とも入れる」。docs/research-deep-2026-10-30.md）
--   これまで: 同じ日・同じ金額・同じカテゴリで、10 分以内に登録したもの（自分の二重送信・押し間違い）
--   追加: 同じ日・同じ金額で、ほかのメンバーが登録したもの（いつ登録したか、カテゴリが同じかは問わない）
create or replace function public.similar_transactions(p_group uuid, p_amount bigint, p_occurred_on date, p_category uuid) returns setof public.transactions
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public._need(p_group, 'viewer');
  return query select * from public.transactions t
  where t.group_id = p_group and t.status = 'active' and t.amount = p_amount and t.occurred_on = p_occurred_on
    and (t.visibility = 'group' or t.created_by = auth.uid())
    and ((t.category_id = p_category and t.created_at > now() - interval '10 minutes')
         or t.created_by is distinct from auth.uid())
  order by t.created_at desc
  limit 5;
end $$;
