// Health check page: confirms the app can reach the database by counting cases.
import { connection } from "next/server";
import { supabase } from "@/lib/supabase";

export default async function HealthPage() {
  // Run at request time, not build time, so the check reflects live status.
  await connection();

  const { count, error } = await supabase
    .from("cases")
    .select("*", { count: "exact", head: true });

  return (
    <main style={{ padding: 24, fontFamily: "sans-serif" }}>
      {error ? (
        <>
          <h1>Connection failed</h1>
          <p>{error.message}</p>
        </>
      ) : (
        <>
          <h1>Connected to database</h1>
          <p>Rows in cases: {count}</p>
        </>
      )}
    </main>
  );
}
