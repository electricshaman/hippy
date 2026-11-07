defmodule Hippy.EventStreamTest do
  use ExUnit.Case, async: true

  alias Hippy.EventStream

  defp printer(state, reasons \\ ["none"]) do
    EventStream.printer_event(%{
      "printer-state" => state,
      "printer-state-reasons" => reasons,
      "printer-is-accepting-jobs" => true,
      "printer-name" => "ignored"
    })
  end

  defp job(id, state) do
    EventStream.job_event(%{
      "job-id" => id,
      "job-state" => state,
      "job-state-reasons" => ["none"],
      "job-name" => "Job #{id}"
    })
  end

  test "events have the same keys, whatever else the printer reports" do
    assert printer(:idle) == %{
             "notify-subscribed-event" => "printer-state-changed",
             "printer-state" => :idle,
             "printer-state-reasons" => ["none"],
             "printer-is-accepting-jobs" => true
           }

    assert job(7, :completed) == %{
             "notify-subscribed-event" => "job-state-changed",
             "notify-job-id" => 7,
             "job-state" => :completed,
             "job-state-reasons" => ["none"],
             "job-name" => "Job 7"
           }
  end

  test "only changes are reported" do
    {events, seen} = EventStream.changes([printer(:idle), job(1, :pending)], %{})
    assert events == [printer(:idle), job(1, :pending)]

    # The same state again, then a change.
    {events, seen} =
      EventStream.changes([printer(:idle), job(1, :pending), job(1, :processing)], seen)

    assert events == [job(1, :processing)]

    {events, _seen} = EventStream.changes([printer(:stopped, ["paused"])], seen)
    assert events == [printer(:stopped, ["paused"])]
  end

  test "a job's end is reported once, and jobs that stop being active are found" do
    {_events, seen} = EventStream.changes([job(1, :pending), job(2, :pending)], %{})
    assert EventStream.vanished(seen, [2]) == [1]

    {events, seen} = EventStream.changes([job(1, :canceled)], seen)
    assert events == [job(1, :canceled)]
    assert EventStream.vanished(seen, [2]) == []

    # A finished job is reported once, even if it's seen again.
    assert {[], _seen} = EventStream.changes([job(1, :canceled)], seen)
  end

  test "only the most recent finished jobs are remembered" do
    {_events, seen} = 1..600 |> Enum.map(&job(&1, :completed)) |> EventStream.changes(%{})

    assert map_size(seen) == 500
    refute Map.has_key?(seen, {:job, 100})
    assert Map.has_key?(seen, {:job, 101})
  end

  test "completed jobs newer than any seen are the ones that came and went between checks" do
    completed = [%{"job-id" => 3}, %{"job-id" => 8}, %{"job-id" => 9}]
    assert EventStream.new_finished(completed, 8) == [%{"job-id" => 9}]
  end

  describe "a page of completed jobs" do
    defp page(ids), do: Enum.map(ids, &%{"job-id" => &1})

    test "smaller than the limit has every new job" do
      assert EventStream.complete_page?(page([4, 5]), 3, 3)
      assert EventStream.complete_page?(page([]), 3, 3)
    end

    test "newest first, it's complete once it reaches an old job" do
      assert EventStream.complete_page?(page([9, 8, 7]), 7, 3)
      refute EventStream.complete_page?(page([9, 8, 7]), 3, 3)
    end

    test "oldest first, it's complete if the printer honoured first-job-id" do
      # CUPS: only jobs after the newest seen, and the rest come next time.
      assert EventStream.complete_page?(page([4, 5, 6]), 3, 3)
      # A printer that ignored it, listing its oldest jobs: the new ones are past the limit.
      refute EventStream.complete_page?(page([1, 2, 3]), 5, 3)
    end
  end
end
