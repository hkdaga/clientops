// Login page: shows the sign-in form and a notice when the account was deactivated.
import LoginForm from "./login-form";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ deactivated?: string }>;
}) {
  const { deactivated } = await searchParams;

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-sm flex-col justify-center gap-6 px-4">
      <h1 className="text-2xl font-semibold">Sign in</h1>
      {deactivated && (
        <p className="text-sm text-red-600">
          Your account has been deactivated. Contact your admin.
        </p>
      )}
      <LoginForm />
    </main>
  );
}
