// Server action that clears the Supabase session and redirects to /login.
"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase-server";

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
