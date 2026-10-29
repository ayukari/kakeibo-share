// 退会: ログイン中の本人だけが自分を消せる。service_role キーはこの関数の環境変数にだけ置く（アプリには入れない）。
// 1) JWT から本人を確かめる 2) prepare_account_deletion（オーナーで他のメンバーがいれば止める・名前を消す）3) Auth のユーザーを消す
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Content-Type": "application/json" };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json(405, { code: "method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return json(500, { code: "server_misconfigured" });
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { code: "unauthorized" });

  // 本人の確認（アプリから届いたアクセストークンで）
  const asUser = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: me, error: meErr } = await asUser.auth.getUser();
  if (meErr || !me.user) return json(401, { code: "unauthorized" });

  // 確認のため、本文に "confirm": "DELETE" が要る
  let body: { confirm?: string } = {};
  try { body = await req.json(); } catch { /* 空 */ }
  if (body.confirm !== "DELETE") return json(422, { code: "confirm_required" });

  const admin = createClient(url, service, { auth: { persistSession: false } });
  const { data: prep, error: prepErr } = await admin.rpc("prepare_account_deletion", { p_user: me.user.id });
  if (prepErr) return json(500, { code: "server" });
  if (!prep?.ok) return json(409, { code: "owner_must_transfer", owner_of: prep?.owner_of ?? [] });

  const { error: delErr } = await admin.auth.admin.deleteUser(me.user.id);
  if (delErr) return json(500, { code: "server" });
  return json(200, { ok: true });
});
