if Mix.env() != :dev do
  raise "Demo seeds must run with MIX_ENV=dev; production data is never seeded"
end

Arcanum.DevelopmentSeeds.run()

IO.puts("""
Development demo data is ready.

Accounts: demo_alice, demo_bob, demo_carol, demo_dave
Emails: <username>@example.com
Password for newly created demo accounts: arcanum-demo-password

Alice and Bob share Demo Commons and Demo Elixir.
Carol shares Demo Commons with them and Demo Book Club with Dave.
Dave has no shared communities with Alice or Bob.

Existing matching accounts, content, roles, and votes are preserved.
""")
