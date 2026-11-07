defmodule Hippy.EventStream do
  @moduledoc false

  # The stream behind Hippy.stream_events/2. Every interval it reads the printer's state and its
  # active jobs, and reports what changed. It also lists completed jobs, so a job that started and
  # finished between two checks is still reported, with its final state.
  #
  # It doesn't use IPP notifications: with CUPS, a printer subscription isn't told about jobs
  # being held, released or canceled, and its printer events can carry state-reasons from before
  # the change. Reading the state is always current.

  alias Hippy.Message
  alias Hippy.Operation.{GetJobAttributes, GetJobs, GetPrinterAttributes}

  @kinds ["printer-state-changed", "job-state-changed"]
  @printer_keys ["printer-state", "printer-state-reasons", "printer-is-accepting-jobs"]
  @job_keys ["job-state", "job-state-reasons", "job-name"]
  @finished [:completed, :canceled, :aborted]
  @remember_finished 500

  @defaults [interval: 2_000, retries: 3]

  def stream(uri, opts) do
    Stream.resource(fn -> init(uri, opts) end, &next/1, fn _state -> :ok end)
  end

  ## Pure: events, and detecting changes

  @doc false
  def printer_event(printer) do
    printer
    |> Map.take(@printer_keys)
    |> Map.put("notify-subscribed-event", "printer-state-changed")
  end

  @doc false
  def job_event(job) do
    job
    |> Map.take(@job_keys)
    |> Map.put("notify-job-id", job["job-id"])
    |> Map.put("notify-subscribed-event", "job-state-changed")
  end

  # Keeps the events that change what was last seen for their printer or job, and returns them
  # with the updated view. Finished jobs are remembered, so they're reported once, up to the most
  # recent @remember_finished of them.
  @doc false
  def changes(events, seen) do
    {events, seen} =
      Enum.flat_map_reduce(events, seen, fn event, seen ->
        key = key(event)

        cond do
          Map.get(seen, key) == event -> {[], seen}
          finished?(Map.get(seen, key)) -> {[], seen}
          true -> {[event], Map.put(seen, key, event)}
        end
      end)

    {events, forget_old_finished(seen)}
  end

  # Jobs that were being followed and are no longer active, so their final state needs asking for.
  @doc false
  def vanished(seen, active_ids) do
    for {{:job, id}, event} <- seen, not finished?(event), id not in active_ids, do: id
  end

  # Completed jobs newer than any seen before: jobs that started and finished between checks.
  @doc false
  def new_finished(completed_jobs, newest_id) do
    Enum.filter(completed_jobs, &(&1["job-id"] > newest_id))
  end

  defp key(%{"notify-subscribed-event" => "printer-state-changed"}), do: :printer
  defp key(%{"notify-job-id" => id}), do: {:job, id}

  defp finished?(%{"job-state" => state}), do: state in @finished
  defp finished?(_event), do: false

  defp forget_old_finished(seen) do
    finished = for {{:job, id}, event} <- seen, finished?(event), do: id

    if length(finished) > @remember_finished do
      finished
      |> Enum.sort()
      |> Enum.take(length(finished) - @remember_finished)
      |> Enum.reduce(seen, &Map.delete(&2, {:job, &1}))
    else
      seen
    end
  end

  ## The stream

  defp init(uri, opts) do
    opts = Keyword.merge(@defaults, opts)

    %{
      uri: uri,
      send: Keyword.take(opts, [:timeout, :req_options]),
      kinds: opts |> Keyword.get(:events, @kinds) |> Enum.filter(&(&1 in @kinds)),
      interval: opts[:interval],
      retries: opts[:retries],
      seen: %{},
      newest_job_id: nil,
      failures: 0
    }
  end

  # First, the current state: the printer, and each active job. Jobs already completed before the
  # stream started aren't reported.
  defp next(%{newest_job_id: nil} = state) do
    case check(state) do
      {:ok, events, completed} ->
        report(events, %{state | newest_job_id: newest_id(events, completed, 0)})

      {:error, error} ->
        raise error
    end
  end

  defp next(state) do
    Process.sleep(state.interval)

    case check(state) do
      {:ok, events, completed} ->
        fast = completed |> new_finished(state.newest_job_id) |> Enum.map(&job_event/1)
        state = %{state | newest_job_id: newest_id(events, completed, state.newest_job_id)}
        report(events ++ fast, %{state | failures: 0})

      {:error, error} ->
        retry(error, state)
    end
  end

  # The printer's state, its active jobs, the final state of jobs that stopped being active, and
  # the completed jobs.
  defp check(state) do
    with {:ok, printer} <- printer_state(state),
         {:ok, active} <- jobs(state, :not_completed),
         {:ok, finished} <- finished_jobs(state, Enum.map(active, & &1["job-id"])),
         {:ok, completed} <- jobs(state, :completed) do
      {:ok, [printer_event(printer) | Enum.map(active ++ finished, &job_event/1)], completed}
    end
  end

  defp newest_id(events, completed, newest) do
    events
    |> Enum.map(& &1["notify-job-id"])
    |> Enum.concat(Enum.map(completed, & &1["job-id"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> newest end)
    |> max(newest)
  end

  # Only the kinds asked for, and only when something changed.
  defp report(events, state) do
    events = Enum.filter(events, &(&1["notify-subscribed-event"] in state.kinds))
    {events, seen} = changes(events, state.seen)
    {events, %{state | seen: seen}}
  end

  defp printer_state(state) do
    with {:ok, res} <-
           state.uri
           |> GetPrinterAttributes.new(requested_attributes: @printer_keys)
           |> Hippy.send_operation(state.send) do
      {:ok, Message.printer(res)}
    end
  end

  defp jobs(state, which) do
    if "job-state-changed" in state.kinds do
      with {:ok, res} <-
             state.uri
             |> GetJobs.new(which_jobs: which, requested_attributes: ["job-id" | @job_keys])
             |> Hippy.send_operation(state.send) do
        {:ok, Message.jobs(res)}
      end
    else
      {:ok, []}
    end
  end

  # The final state of jobs that were active last time and aren't now. A job the printer has
  # already forgotten is skipped.
  defp finished_jobs(state, active_ids) do
    state.seen
    |> vanished(active_ids)
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
      case state.uri
           |> GetJobAttributes.new(id, requested_attributes: ["job-id" | @job_keys])
           |> Hippy.send_operation(state.send) do
        {:ok, res} -> {:cont, {:ok, acc ++ [Message.job(res)]}}
        {:error, %Hippy.Error{status: :client_error_not_found}} -> {:cont, {:ok, acc}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # Wait longer after each failure, and give up after the configured number of retries.
  defp retry(error, %{failures: failures, retries: retries}) when failures >= retries,
    do: raise(error)

  defp retry(_error, state) do
    Process.sleep(state.interval * Integer.pow(2, state.failures))
    {[], %{state | failures: state.failures + 1}}
  end
end
