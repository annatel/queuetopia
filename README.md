# Queuetopia

A persistant blocking job queue built with Ecto.

#### Features

- **Persistence** — Jobs are stored in a DB and updated after each execution attempt.

- **Blocking** — A failing job blocks its queue until it is done.

- **Dynamicity** — Queues are dynamically defined. Once the first job is created
  for the queue, the queue exists.

- **Retries** — Failed jobs are retried with a configurable backoff.

- **Persistence** — Jobs are stored in a DB and updated after each execution attempt.

- **Isolated Queues** — Jobs are stored in a single table but are executed in
  distinct queues. Each queue runs in isolation, ensuring that a job in a single
  slow queue can't back up other faster queues and that a failing job in a queue
  don't block other queues.

- **Handle Node Duplication** — Queues are locked, preventing two nodes to perform
  the same job at the same time.


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `queuetopia` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:queuetopia, "~> 0.1.2"}
  ]
end
```

After the packages are installed you must create a database migration to
add the queuetopia tables to your database:

```bash
mix ecto.gen.migration create_queuetopia_tables
```

Open the generated migration in your editor and call the `up` and `down`
functions on `Queuetopia.Migrations`:

```elixir
defmodule MyApp.Repo.Migrations.CreateQueuetopiaTables do
  use Ecto.Migration

  def up do
    Queuetopia.Migrations.V1.up
  end

  def down do
    Queuetopia.Migrations.V1.down
  end
end
```

Now, run the migration to create the table:

```sh
mix ecto.migrate
```

## Usage

### Defining the Queuetopia

A Queuetopia must be informed a repo to persist the jobs and a performer module,
responsible to execute the jobs.

Define a Queuetopia with a repo and a perfomer like this:

```elixir
defmodule MyApp.MailQueue do
  use Queuetopia,
    repo: MyApp.Repo,
    performer: MyApp.MailQueue.Performer
end
```

Define the perfomer, adopting the Queuetopia.Jobs.Performer behaviour, like this:

```elixir
defmodule MyApp.MailQueue.Performer do
  @behaviour Queuetopia.Jobs.Performer

  @impl true
  def perform(%Queuetopia.Jobs.Job{action: "do_x"}) do
    do_x()
  end

  defp do_x(), do: {:ok, "done"}
end
```

### Start the Queuetopia

An instance Queuetopia is a supervision tree and can be started as a child of a supervisor.

For instance, in the application supervision tree:

```elixir
defmodule MyApp do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.MailQueue, [[polling_interval: 1_000]]}
    ]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Or, it can be started directly like this:

```elixir
MyApp.MailQueue.start_link([poll_interval: 1_000])
```

Note that the polling interval is optionnal.
By default, it will be set to 60 seconds.


### Feeds your queues

To create a job defines its action and its params and configure its timeout and the max backoff for the retries.
By default, the job timeout is set to 60 seconds, the max backoff to 24 hours and the max attempts to 20.


```elixir
MyApp.MailQueue.create_job("mails_queue_1", "send_mail", %{email_address: "toto@mail.com", body: "Welcome"}, [timeout: 1_000, max_backoff: 60_000])
```

So, the mails_queue_1 was born and you can add it other jobs as we do above.

### One DB, many Queuetopia

Multiple Queuetopia can coexist in your project, e.g your project may own its Queuetopia and uses a library
shipping its Queuetopia. The both Queuetopia may run on the same DB and share the same repo. They will have a different scheduler,
may have a different polling interval. They will be defined a scope to reach only their own jobs,
so the won't interfer each other.


## Test

Rename env/test.env.example to env/test.env, set your params and source it.

```sh
MIX_ENV=test mix do ecto.drop, ecto.create, ecto.migrate
mix test
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/queuetopia](https://hexdocs.pm/queuetopia).

