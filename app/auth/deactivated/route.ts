// Signs out a deactivated user (route handlers can clear cookies) and sends them to /login with a notice.
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase-server";

export async function GET(request: Request) {
  const supabase = await createClient();
  await supabase.auth.signOut();
  return NextResponse.redirect(new URL("/login?deactivated=1", request.url));
}
