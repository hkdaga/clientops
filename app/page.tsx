// Home page: shows who is signed in (from profiles) with a Sign out button.
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase-server";
import { signOut } from "./actions";

export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name, role, is_active")
    .eq("id", user.id)
    .single();

  // No profile or deactivated: end the session via the route handler (pages can't clear cookies).
  if (!profile || !profile.is_active) redirect("/auth/deactivated");

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 px-4">
      <p>
        Signed in as {profile.full_name} ({profile.role})
      </p>
      <form action={signOut}>
        <button type="submit" className="rounded bg-black px-3 py-2 text-white">
          Sign out
        </button>
      </form>
    </main>
  );
}
