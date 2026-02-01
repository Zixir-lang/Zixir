defmodule Zixir.Python.CircuitBreaker do
  @moduledoc """
  Optional circuit breaker for Python specialist: after repeated failures in a window,
  open circuit and return {:error, :circuit_open} without calling Python; cooldown then half-open.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns :ok if circuit closed or half-open; {:error, :circuit_open} if open."
  def allow? do
    GenServer.call(__MODULE__, :allow?, 1_000)
  end

  @doc "Record a successful Python call."
  def record_success do
    GenServer.cast(__MODULE__, :success)
  end

  @doc "Record a failed Python call."
  def record_failure do
    GenServer.cast(__MODULE__, :failure)
  end

  @impl true
  def init(_opts) do
    state = %{
      failures: [],
      state: :closed,
      threshold: 5,
      window_ms: 10_000,
      cooldown_ms: Application.get_env(:zixir, :circuit_breaker_cooldown, 30_000),
      opened_at: nil
    }
    {:ok, state}
  end

  @impl true
  def handle_call(:allow?, _from, %{state: :closed} = state), do: {:reply, :ok, state}
  def handle_call(:allow?, _from, %{state: :half_open} = state), do: {:reply, :ok, state}

  def handle_call(:allow?, _from, %{state: :open, opened_at: at, cooldown_ms: cd} = state) do
    if System.monotonic_time(:millisecond) - at >= cd do
      {:reply, :ok, %{state | state: :half_open}}
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end

  @impl true
  def handle_cast(:success, %{state: :half_open} = state) do
    {:noreply, %{state | state: :closed, failures: []}}
  end

  def handle_cast(:success, state), do: {:noreply, state}

  def handle_cast(:failure, %{state: :closed, failures: fails, threshold: th, window_ms: win} = state) do
    now = System.monotonic_time(:millisecond)
    fails = [now | fails] |> Enum.take(th * 2)
    recent = Enum.count(fails, fn t -> now - t < win end)

    if recent >= th do
      {:noreply, %{state | state: :open, failures: [], opened_at: now}}
    else
      {:noreply, %{state | failures: fails}}
    end
  end

  def handle_cast(:failure, %{state: :half_open} = state) do
    {:noreply, %{state | state: :open, opened_at: System.monotonic_time(:millisecond)}}
  end

  def handle_cast(:failure, state), do: {:noreply, state}
end
