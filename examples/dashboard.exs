# A live dashboard of printers, in one file.
#
#     PRINTERS="ipp://192.168.1.50/ipp/print ipp://cups.local:631/printers/labels" \
#       elixir --no-halt examples/dashboard.exs
#
# Then open http://localhost:4000. Each printer gets a card showing its state, anything wrong
# with it and its jobs, updated as they change. It only reads from the printers.

Mix.install([
  {:phoenix_playground, "~> 0.1.9"},
  # The Hippy in this repository. In your own project, use {:hippy, "~> 0.8"}.
  {:hippy, path: Path.expand("..", __DIR__)}
])

defmodule Dashboard do
  use Phoenix.LiveView

  @finished [:completed, :canceled, :aborted]

  def mount(_params, _session, socket) do
    printers =
      "PRINTERS"
      |> System.get_env("")
      |> String.split()

    if connected?(socket) do
      Enum.each(printers, &watch(&1, self()))
    end

    cards = Map.new(printers, &{&1, %{state: nil, reasons: [], jobs: %{}, error: nil}})
    {:ok, assign(socket, printers: printers, cards: cards, page_title: "Printers")}
  end

  # Each printer is watched by its own task, linked to this LiveView so it stops with it. If the
  # printer can't be reached, the stream raises: show why, and try again shortly.
  defp watch(uri, view) do
    Task.start_link(fn -> watch_loop(uri, view) end)
  end

  defp watch_loop(uri, view) do
    uri
    |> Hippy.stream_events(interval: 1_000)
    |> Enum.each(&send(view, {:event, uri, &1}))
  rescue
    error ->
      send(view, {:unreachable, uri, Exception.message(error)})
      Process.sleep(5_000)
      watch_loop(uri, view)
  end

  def handle_info(
        {:event, uri, %{"notify-subscribed-event" => "printer-state-changed"} = e},
        socket
      ) do
    {:noreply,
     update_card(socket, uri, fn card ->
       %{
         card
         | state: e["printer-state"],
           reasons: Enum.reject(e["printer-state-reasons"] || [], &(&1 == "none")),
           error: nil
       }
     end)}
  end

  def handle_info({:event, uri, %{"notify-job-id" => id} = e}, socket) do
    # Finished jobs stay on the card for a few seconds, then go.
    if e["job-state"] in @finished, do: Process.send_after(self(), {:forget, uri, id}, 10_000)

    {:noreply,
     update_card(socket, uri, fn card ->
       job = Map.merge(Map.get(card.jobs, id, %{}), Map.reject(e, fn {_k, v} -> is_nil(v) end))
       %{card | jobs: Map.put(card.jobs, id, job)}
     end)}
  end

  def handle_info({:forget, uri, id}, socket) do
    {:noreply, update_card(socket, uri, &%{&1 | jobs: Map.delete(&1.jobs, id)})}
  end

  def handle_info({:unreachable, uri, message}, socket) do
    {:noreply, update_card(socket, uri, &%{&1 | error: message})}
  end

  defp update_card(socket, uri, fun) do
    update(socket, :cards, &Map.update!(&1, uri, fun))
  end

  def render(assigns) do
    ~H"""
    <main>
      <h1>Printers</h1>
      <p :if={@printers == []} class="hint">
        Set <code>PRINTERS</code> to one or more printer URIs, separated by spaces.
      </p>
      <section class="grid">
        <article :for={uri <- @printers} class={["card", status(@cards[uri])]}>
          <header>
            <span class="dot"></span>
            <h2>{title(uri)}</h2>
            <span class="state">{label(@cards[uri])}</span>
          </header>
          <p class="uri">{uri}</p>
          <p :if={@cards[uri].error} class="problem">{@cards[uri].error}</p>
          <ul :if={@cards[uri].reasons != []} class="reasons">
            <li :for={reason <- @cards[uri].reasons}>{reason}</li>
          </ul>
          <ol class="jobs">
            <li :for={{id, job} <- Enum.sort(@cards[uri].jobs)} class={"job #{job["job-state"]}"}>
              <span>#{id} {job["job-name"]}</span>
              <span class="job-state">{job["job-state"]}</span>
            </li>
            <li :if={@cards[uri].jobs == %{}} class="empty">No jobs</li>
          </ol>
        </article>
      </section>
    </main>
    <style>
      :root { color-scheme: light dark; --bg: #f6f6f4; --card: #fff; --ink: #222; --muted: #777;
              --ok: #2f9e44; --busy: #1c7ed6; --bad: #e03131; --line: #e4e4e0; }
      @media (prefers-color-scheme: dark) {
        :root { --bg: #161616; --card: #202020; --ink: #eee; --muted: #999; --line: #333; }
      }
      body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.4 system-ui, sans-serif; }
      main { max-width: 1100px; margin: 0 auto; padding: 24px 16px; }
      h1 { font-size: 22px; margin: 0 0 16px; }
      .grid { display: grid; gap: 16px; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); }
      .card { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; }
      .card header { display: flex; align-items: center; gap: 8px; }
      .card h2 { font-size: 16px; margin: 0; flex: 1; overflow-wrap: anywhere; }
      .dot { width: 10px; height: 10px; border-radius: 50%; background: var(--muted); }
      .ok .dot { background: var(--ok); } .busy .dot { background: var(--busy); }
      .bad .dot { background: var(--bad); }
      .state { color: var(--muted); font-size: 13px; }
      .uri { color: var(--muted); font-size: 12px; margin: 2px 0 8px; overflow-wrap: anywhere; }
      .problem, .reasons { color: var(--bad); font-size: 13px; }
      .reasons { margin: 0 0 8px; padding-left: 18px; }
      .jobs { list-style: none; margin: 0; padding: 0; border-top: 1px solid var(--line); }
      .job, .empty { display: flex; justify-content: space-between; gap: 8px; padding: 6px 0;
                     border-bottom: 1px solid var(--line); font-size: 13px; }
      .empty { color: var(--muted); border: 0; }
      .job-state { color: var(--muted); }
      .job.processing .job-state { color: var(--busy); }
      .job.completed .job-state { color: var(--ok); }
      .job.aborted .job-state, .job.canceled .job-state { color: var(--bad); }
      .hint code { background: var(--card); padding: 1px 4px; border-radius: 4px; }
    </style>
    """
  end

  # A CUPS queue's name, or the printer's address.
  defp title(uri) do
    case URI.parse(uri) do
      %URI{path: "/printers/" <> queue} -> queue
      %URI{host: host, port: port} -> "#{host}:#{port}"
    end
  end

  defp status(%{error: error}) when is_binary(error), do: "bad"
  defp status(%{state: :stopped}), do: "bad"
  defp status(%{reasons: [_ | _]}), do: "bad"
  defp status(%{state: :processing}), do: "busy"
  defp status(%{state: :idle}), do: "ok"
  defp status(_card), do: "unknown"

  defp label(%{error: error}) when is_binary(error), do: "unreachable"
  defp label(%{state: nil}), do: "connecting…"
  defp label(%{state: state}), do: to_string(state)
end

PhoenixPlayground.start(live: Dashboard, open_browser: false)
