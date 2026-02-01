defmodule Zixir.Python.Worker do
  @moduledoc """
  Enhanced Python port worker with timeout handling, retry logic, and health checks.
  Supervised; on crash supervisor restarts it.
  """

  use GenServer

  require Logger

  @max_retries 3
  @health_check_interval 60_000

  def start_link(opts \\ []) do
    id = Keyword.get(opts, :id, 0)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  def call(pid, module, function, args, opts \\ []) when is_pid(pid) do
    timeout = Keyword.get(opts, :timeout, default_timeout())
    retries = Keyword.get(opts, :retries, @max_retries)
    kwargs = Keyword.get(opts, :kwargs, [])
    
    do_call_with_retry(pid, module, function, args, kwargs, timeout, retries)
  end
  
  @doc """
  Perform a health check on the worker.
  """
  def health_check(pid) when is_pid(pid) do
    GenServer.call(pid, :health_check, 5_000)
  end

  defp via(id), do: {:via, Registry, {Zixir.Python.Registry, id}}

  @impl true
  def init(opts) do
    id = Keyword.get(opts, :id, 0)
    
    case start_port() do
      nil ->
        Logger.error("Python worker #{id}: Failed to start port")
        {:ok, %{id: id, port: nil, pending: nil, buffer: "", ready: false, last_health_check: nil}}
      
      port ->
        # Schedule health check
        schedule_health_check()
        {:ok, %{id: id, port: port, pending: nil, buffer: "", ready: false, last_health_check: nil}}
    end
  end

  defp start_port() do
    python_path = Application.get_env(:zixir, :python_path) || 
                  System.find_executable("python3") || 
                  System.find_executable("python")
    script_path = script_path()

    if is_nil(python_path) or is_nil(script_path) do
      Logger.error("Python not found. Set :python_path in config or ensure python is on PATH")
      nil
    else
      port = Port.open({:spawn_executable, python_path}, [
        :binary, 
        {:line, 65536},  # Increased line buffer for large arrays
        :stderr_to_stdout, 
        {:args, [script_path]},
        {:env, [{~c"PYTHONUNBUFFERED", ~c"1"}]}
      ])
      
      Logger.debug("Started Python port: #{inspect(port)}")
      port
    end
  rescue
    e -> 
      Logger.error("Failed to start Python port: #{inspect(e)}")
      nil
  end

  defp script_path() do
    base = Application.app_dir(:zixir)
    path = Path.join([base, "priv", "python", "port_bridge.py"])
    if File.exists?(path) do
      path
    else
      Logger.error("Python bridge script not found at #{path}")
      nil
    end
  end

  @impl true
  def handle_call(:health_check, _from, %{port: nil} = state) do
    {:reply, {:error, :port_not_ready}, state}
  end

  def handle_call(:health_check, _from, %{port: _port, ready: true} = state) do
    # Simple health check - if port is open and we've received ready signal, we're healthy
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:health_check, _from, %{port: _port, ready: false} = state) do
    # Port exists but hasn't sent ready signal yet
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call(:health_check, _from, %{pending: _} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:call, _module, _function, _args, _kwargs}, _from, %{port: nil} = state) do
    {:reply, {:error, :python_not_ready}, state}
  end

  def handle_call({:call, module, function, args, kwargs}, from, %{port: port, pending: nil} = state) do
    request = Zixir.Python.Protocol.encode_request(module, function, args, kwargs)
    Port.command(port, request)
    {:noreply, %{state | pending: from}}
  end

  def handle_call({:call, _m, _f, _a, _k}, _from, %{pending: _} = state) do
    {:reply, {:error, :busy}, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port, pending: from} = state) when not is_nil(from) do
    result = Zixir.Python.Protocol.decode_response(line)
    
    # Handle ready signal
    {reply, new_state} = case result do
      {:ok, {:ready, info}} ->
        Logger.debug("Python worker #{state.id} ready: numpy=#{info["numpy"]}, pandas=#{info["pandas"]}")
        {{:ok, :ready}, %{state | ready: true}}
      
      _ ->
        reply = case result do
          {:ok, value} -> {:ok, value}
          {:error, reason} -> {:error, reason}
        end
        {reply, state}
    end
    
    GenServer.reply(from, reply)
    {:noreply, %{new_state | pending: nil}}
  end

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port, buffer: buf} = state) do
    {:noreply, %{state | buffer: buf <> chunk}}
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    buf = state.buffer <> data
    case String.split(buf, "\n", parts: 2) do
      [line, rest] ->
        result = Zixir.Python.Protocol.decode_response(line)
        reply = case result do
          {:ok, value} -> {:ok, value}
          {:error, reason} -> {:error, reason}
        end
        if state.pending do
          GenServer.reply(state.pending, reply)
          {:noreply, %{state | pending: nil, buffer: rest}}
        else
          {:noreply, %{state | buffer: rest}}
        end
      [_] ->
        {:noreply, %{state | buffer: buf}}
    end
  end

  def handle_info({_port, {:exit_status, status}}, state) do
    Logger.error("Python worker #{state.id} port exited with status #{status}")
    
    if state.pending do
      GenServer.reply(state.pending, {:error, :port_closed})
    end
    
    {:noreply, %{state | port: nil, pending: nil, ready: false}}
  end

  def handle_info(:health_check, %{port: port, ready: true} = state) when not is_nil(port) do
    # Perform periodic health check
    request = Zixir.Python.Protocol.encode_command(:health)
    Port.command(port, request)
    
    schedule_health_check()
    {:noreply, state}
  end

  def handle_info(:health_check, state) do
    schedule_health_check()
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp schedule_health_check() do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  # Retry logic for calls
  defp do_call_with_retry(pid, module, function, args, kwargs, timeout, retries) do
    case GenServer.call(pid, {:call, module, function, args, kwargs}, timeout) do
      {:ok, result} ->
        {:ok, result}
      
      {:error, reason} when retries > 0 ->
        Logger.warning("Python call failed (#{reason}), retrying... (#{retries} left)")
        Process.sleep(100)
        do_call_with_retry(pid, module, function, args, kwargs, timeout, retries - 1)
      
      error ->
        error
    end
  end

  # Get default timeout from application config
  defp default_timeout do
    Application.get_env(:zixir, :python_timeout, 30_000)
  end
end
