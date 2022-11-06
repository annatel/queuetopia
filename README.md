# Queuetopia

[![GitHub Workflow Status](https://img.shields.io/github/workflow/status/annatel/queuetopia/CI?cacheSeconds=3600&style=flat-square)](https://github.com/annatel/queuetopia/actions) [![GitHub issues](https://img.shields.io/github/issues-raw/annatel/queuetopia?style=flat-square&cacheSeconds=3600)](https://github.com/annatel/queuetopia/issues) [![License](https://img.shields.io/badge/license-MIT-brightgreen.svg?cacheSeconds=3600?style=flat-square)](http://opensource.org/licenses/MIT) [![Hex.pm](https://img.shields.io/hexpm/v/queuetopia?style=flat-square)](https://hex.pm/packages/queuetopia) [![Hex.pm](https://img.shields.io/hexpm/dt/queuetopia?style=flat-square)](https://hex.pm/packages/queuetopia)

A persistant blocking job queue built with Ecto.

#### Features

- Persistence — Jobs are stored in a DB and updated after each execution attempt.

- Blocking — A failing job blocks its queue until it is done.

- Dynamicity — Queues are dynamically defined. Once the first job is created
  for the queue, the queue exists.

- Reactivity — Immediatly try to execute a job that has just been created.

- Scheduled Jobs — Allow to schedule job in the future.

- Retries — Failed jobs are retried with a configurable backoff.

- Persistence — Jobs are stored in a DB and updated after each execution attempt.

- Performance — At each poll, only one job per queue is run. Optionnaly, jobs can
  avoid waiting unnecessarily. The performed job triggers an other polling.

- Isolated Queues — Jobs are stored in a single table but are executed in
  distinct queues. Each queue runs in isolation, ensuring that a job in a single
  slow queue can't back up other faster queues and that a failing job in a queue
  don't block other queues.

- Handle Node Duplication — Queues are locked, preventing two nodes to perform
  the same job at the same time.

## Installation

Queuetopia is published on [Hex](https://hex.pm/packages/queuetopia).
The package can be installed by adding `queuetopia` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:queuetopia, "~> 2.4"}
  ]
end
```

After the packages are installed, you must create a database migration to
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
    Queuetopia.Migrations.up()
  end

  def down do
    Queuetopia.Migrations.down()
  end
end
```

Now, run the migration to create the table:

```sh
mix ecto.migrate
```

Each migration can be called separately.
## Usage

### Defining the Queuetopia

A Queuetopia must be informed a repo to persist the jobs and a performer module,
responsible to execute the jobs.

Define a Queuetopia with a repo and a perfomer like this:

```elixir
defmodule MyApp.MailQueuetopia do
  use Queuetopia,
    otp_app: :my_app,
    performer: MyApp.MailQueuetopia.Performer,
    repo: MyApp.Repo
end
```
A Queuetopia expects a performer to exist.
For example, the performer can be implemented like this:

```elixir
defmodule MyApp.MailQueuetopia.Performer do
  @behaviour Queuetopia.Performer

  @impl true
  def perform(%Queuetopia.Queue.Job{action: "do_x"}) do
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
      MyApp.MailQueuetopia
    ]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Or, it can be started directly like this:

```elixir
MyApp.MailQueuetopia.start_link()
```

The configuration can be set as below:

```elixir
 # config/config.exs
  config :my_app, MyApp.MailQueuetopia,
    poll_interval: 60 * 1_000,
    disable?: true

```

Note that the polling interval is optionnal and is an available param of start_link/1.
By default, it will be set to 60 seconds.
`disable?` is usefull to prevent the scheduler to start. 
In test environnement, it is recommanded to set it to true. It will be sufficient to test the job creation 
and the performer.

### Feeds your queues

To create a job defines its action and its params and configure its timeout.
By default, the job timeout is set to 60 seconds, the max backoff to 24 hours.


```elixir
MyApp.MailQueuetopia.create_job!("mails_queue_1", "send_mail", %{email_address: "toto@mail.com", body: "Welcome"}, [timeout: 1_000])
```
or

```elixir
MyApp.MailQueuetopia.create_job("mails_queue_1", "send_mail", %{email_address: "toto@mail.com", body: "Welcome"}, [timeout: 1_000])
```
to handle changeset errors.

So, the mails_queue_1 was born and you can add it other jobs as we do above.
When the job creation is out of transaction, Queuetopia is automatically notified about the new job.
Anyway, you can notify the queuetopia about a new created job.

```elixir
MyApp.MailQueuetopia.notify(:new_incoming_job)
```

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

Thanks to [Oban] [https://github.com/sorentwo/oban] and elixir community who inspired the Queuetopia development.

