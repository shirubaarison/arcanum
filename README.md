<div align="center">

# Arcanum

A project built with Elixir and Phoenix LiveView, bringing private communities,
threaded discussions, and live voting to a minimal, content-first interface.

[Explore the features](#features) · [Run locally](#quick-start) · [Try the demo](#demo-walkthrough)

</div>

---

## The idea

Arcanum brings community-driven discussions together with a clean, minimalist design: 
compact post lists, intuitive voting controls, readable threads, and a distraction-free 
experience that keeps the focus on meaningful conversations.

Unlike an open public feed, Arcanum centers on **private, membership-based communities**.
Posts, discussions, and profile activity respect community boundaries—even as
updates arrive in real time.

## Features

| | What you can do |
| --- | --- |
| **Private communities** | Create spaces for discussion and manage members and roles. |
| **Posts & threaded replies** | Publish text posts and keep conversations organized with nested comments. |
| **Live updates** | See new posts, comments, and vote changes across connected sessions without refreshing. |
| **Voting & karma** | Upvote or downvote posts and comments, with live profile karma updates. |
| **Privacy-aware profiles** | Browse a member's activity only within communities you both belong to. |

## Tech stack

| Layer | Technology |
| --- | --- |
| Language & runtime | Elixir / Erlang OTP |
| Web framework | Phoenix 1.8 |
| Interactive UI | Phoenix LiveView 1.2, LiveView streams, Phoenix PubSub |
| Data | PostgreSQL 17, Ecto |
| Styling & assets | Tailwind CSS 4, custom CSS, esbuild |
| Email | Swoosh, with a local development mailbox |
| Quality | ExUnit, LiveView tests, Credo, Dialyzer, GitHub Actions |

## Quick start

### Prerequisites

- **Elixir and Erlang/OTP** — CI uses Elixir `1.20.4` and OTP `29.0.6`.
- **Docker with Docker Compose** — for the local PostgreSQL database.
- **Node.js** — if you want to run the JavaScript timestamp tests.

From the repository root:

```sh
# Start PostgreSQL and wait until it is ready
docker compose up -d --wait

# Install dependencies, migrate the database, seed demo data, and build assets
mix setup

# Start the application
mix phx.server
```

Open **[localhost:4000](http://localhost:4000)** and sign in with a demo account below.
For an interactive Elixir session, use `iex -S mix phx.server` instead.

> **Local development only:** PostgreSQL runs at `localhost:5432`, using database
> `arcanum_dev`, username `postgres`, and password `postgres`. Data persists in a
> Docker volume. Stop the database with `docker compose down`.

## Demo walkthrough

`mix setup` creates confirmed accounts, three private communities, six posts,
eight threaded comments, and sample upvotes and downvotes.

Select **password mode** on the login page. All newly seeded accounts use:

```text
arcanum-demo-password
```

| Username | Email | Communities |
| --- | --- | --- |
| `demo_alice` | `demo_alice@example.com` | Demo Commons, Demo Elixir |
| `demo_bob` | `demo_bob@example.com` | Demo Commons, Demo Elixir |
| `demo_carol` | `demo_carol@example.com` | Demo Commons, Demo Book Club |
| `demo_dave` | `demo_dave@example.com` | Demo Book Club |

### See it in action

1. **Explore a community.** Sign in as Alice and open Demo Commons to browse posts and replies.
2. **Watch a live update.** Sign in as Bob in a separate browser or private window.
   Open the same post in both sessions, then add a comment or change a vote.
3. **Check the privacy model.** Open `/demo_carol` as Alice to see activity from
   Demo Commons only. Open `/demo_dave`: Alice and Dave share no communities,
   so Dave's posts are not visible to her.
4. **Create your own space.** Create a community, manage its members, and start a thread.

> Demo credentials are **only for local development**. Seeds refuse to run outside
> the development environment and send no activation emails.

<details>
<summary><strong>Reseeding an existing database</strong></summary>

```sh
mix ecto.migrate
mix run priv/repo/seeds.exs
```

Seeds are repeatable: matching records are not duplicated, and existing passwords,
content, roles, and votes are not reset. Identity or ownership conflicts stop the
transaction rather than overwrite existing data.

</details>

### Project map

```text
lib/arcanum/                  Business contexts, schemas, and authorization
lib/arcanum_web/live/         LiveView screens and interactions
lib/arcanum_web/components/   Shared UI components and layouts
assets/                      CSS, JavaScript, and browser hooks
priv/repo/                   Database migrations and development seeds
test/                        Context, controller, and LiveView tests
.github/workflows/ci.yml      Continuous integration
```

## Development

### Quality checks

With PostgreSQL running:

```sh
# Compile, format, lint, analyze types, and run tests
mix precommit

# Run the browser timestamp formatter tests
node --test assets/js/hooks/local_time.test.mjs
```

You can also run `mix test`, `mix credo --strict`, and `mix dialyzer` individually.
Dialyzer runs in the test environment and checks compiled test helpers. Its first
run builds a type cache under `_build/` and can take several minutes; later runs reuse it.

### Registration & development emails

Open **[the local mailbox](http://localhost:4000/dev/mailbox)** to read activation
and login emails. Register an account, open its activation link, and choose a
password of at least 12 characters. Email confirmation and password setup happen together.

To try email-link login, request a login email for an existing account and refresh
the mailbox. The local adapter sends no real email. Messages are stored in memory
and disappear when the server restarts; emails generated by a separate `mix run`
process do not appear in the running server's mailbox.

### Health check & deployment

`GET /health` returns HTTP `200` with `{"status":"ok"}` without authentication.
It is an uncached **liveness check**, not a database or external-service readiness check.

For production setup, see the [Phoenix deployment guide](https://phoenix.hexdocs.pm/deployment.html).
