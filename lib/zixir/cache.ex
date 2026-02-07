defmodule Zixir.Cache do
  @moduledoc """
  Caching and Persistence Layer for AI Workflows.
  
  Provides:
  - In-memory caching with TTL
  - Disk-based persistence
  - Redis integration (optional)
  - Automatic serialization
  - Cache warming and invalidation
  
  ## Example
  
      # Simple caching
      result = Zixir.Cache.fetch("model_predictions", ttl: 3600, fn ->
        python "model" "predict" (data)
      end)
      
      # Persistent storage
      Zixir.Cache.put_persistent("workflow_state", state)
      restored = Zixir.Cache.get_persistent("workflow_state")
      
      # Database-like operations
      Zixir.Cache.insert("predictions", %{input: data, output: result})
      records = Zixir.Cache.query("predictions", where: [status: "completed"])
  """

  use GenServer

  require Logger

  @local_cache :zixir_cache_table

  @default_config %{
    max_size: 100_000,        # Max entries in memory
    default_ttl: 3600,        # Default TTL in seconds
    cleanup_interval: 60_000,  # Cleanup every 60 seconds
    persist_dir: Application.get_env(:zixir, :cache_persist_dir, "_zixir_cache"),
    enable_disk: true
  }

  # Client API

  @doc """
  Start the Cache service.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  # Initialize local ETS cache for when GenServer is not running
  defp ensure_local_cache do
    case :ets.whereis(@local_cache) do
      :undefined ->
        :ets.new(@local_cache, [:named_table, :public, :set])
      _ ->
        :ok
    end
  end

  @doc """
  Fetch from cache or compute and store.
  
  ## Options
    * `:ttl` - Time-to-live in seconds
    * `:persistent` - Also save to disk
  """
  @spec fetch(String.t(), keyword(), function()) :: any()
  def fetch(key, opts \\ [], func) when is_function(func) do
    case get(key) do
      {:ok, value} ->
        value
      
      {:error, :not_found} ->
        value = func.()
        put(key, value, opts)
        value
    end
  end

  @doc """
  Store a value in cache.
  
  ## Options
    * `:ttl` - Time-to-live in seconds
    * `:persistent` - Also save to disk
  """
  @spec put(String.t(), any(), keyword()) :: :ok
  def put(key, value, opts \\ []) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:put, key, value, opts})
    else
      # Fallback: use ETS or Agent for local storage
      ensure_local_cache()
      ttl = Keyword.get(opts, :ttl, @default_config.default_ttl)
      expires_at = if ttl == :infinity do
        :infinity
      else
        System.monotonic_time(:second) + ttl
      end
      :ets.insert(@local_cache, {key, value, expires_at})
      :ok
    end
  end

  @doc """
  Get a value from cache.
  """
  @spec get(String.t()) :: {:ok, any()} | {:error, :not_found | :expired}
  def get(key) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:get, key})
    else
      ensure_local_cache()
      case :ets.lookup(@local_cache, key) do
        [{^key, value, expires_at}] ->
          if expires_at == :infinity or System.monotonic_time(:second) < expires_at do
            {:ok, value}
          else
            :ets.delete(@local_cache, key)
            {:error, :expired}
          end
        [] ->
          {:error, :not_found}
      end
    end
  end

  @doc """
  Delete a key from cache.
  """
  @spec delete(String.t()) :: :ok
  def delete(key) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:delete, key})
    else
      ensure_local_cache()
      :ets.delete(@local_cache, key)
      :ok
    end
  end

  @doc """
  Check if key exists in cache.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(key) do
    case get(key) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Store value persistently (always saved to disk).
  """
  @spec put_persistent(String.t(), any()) :: :ok
  def put_persistent(key, value) do
    put(key, value, persistent: true, ttl: :infinity)
  end

  @doc """
  Get persistent value.
  """
  @spec get_persistent(String.t()) :: {:ok, any()} | {:error, :not_found}
  def get_persistent(key) do
    # First try memory
    case get(key) do
      {:ok, value} -> {:ok, value}
      {:error, :not_found} -> load_from_disk(key)
    end
  end

  @doc """
  Insert into a collection/table.
  """
  @spec insert(String.t(), map(), keyword()) :: {:ok, String.t()}
  def insert(table, record, opts \\ []) do
    key = "#{table}:#{generate_id()}"
    record = Map.put(record, :_id, key)
    record = Map.put(record, :_table, table)
    record = Map.put(record, :_created_at, DateTime.utc_now())
    
    put(key, record, opts)
    {:ok, key}
  end

  @doc """
  Query records from a table.
  
  ## Options
    * `:where` - Filter conditions
    * `:limit` - Max results
    * `:order_by` - Sort field
  """
  @spec query(String.t(), keyword()) :: list(map())
  def query(table, opts \\ []) do
    GenServer.call(__MODULE__, {:query, table, opts})
  end

  @doc """
  Update a record.
  """
  @spec update(String.t(), map()) :: :ok | {:error, :not_found}
  def update(key, updates) do
    GenServer.call(__MODULE__, {:update, key, updates})
  end

  @doc """
  Get all cache statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Clear all cache entries.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  List cache entries with optional prefix filter.
  """
  @spec list(keyword()) :: [String.t()]
  def list(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    GenServer.call(__MODULE__, {:list, prefix})
  end

  @doc """
  Warm cache by pre-computing values.
  """
  @spec warm(list(String.t()), function()) :: :ok
  def warm(keys, func) when is_function(func) do
    Enum.each(keys, fn key ->
      spawn(fn ->
        value = func.(key)
        put(key, value)
      end)
    end)
    
    :ok
  end

  @doc """
  Invalidate cache entries matching a pattern.
  """
  @spec invalidate(String.t()) :: :ok
  def invalidate(pattern) when is_binary(pattern) do
    GenServer.call(__MODULE__, {:invalidate, pattern})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))
    
    # Create persist directory
    if config.enable_disk do
      File.mkdir_p!(config.persist_dir)
    end
    
    state = %{
      config: config,
      cache: %{},        # key => {value, expires_at, persistent}
      tables: %{},       # table => [keys]
      size: 0,
      hits: 0,
      misses: 0
    }
    
    # Start cleanup timer
    schedule_cleanup(config.cleanup_interval)
    
    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, opts}, _from, state) do
    ttl = Keyword.get(opts, :ttl, state.config.default_ttl)
    persistent = Keyword.get(opts, :persistent, false)
    
    expires_at = if ttl == :infinity do
      :infinity
    else
      System.monotonic_time(:second) + ttl
    end
    
    entry = {value, expires_at, persistent}
    new_cache = Map.put(state.cache, key, entry)
    
    # Save to disk if persistent
    if persistent and state.config.enable_disk do
      save_to_disk(key, value, state.config.persist_dir)
    end
    
    new_state = %{state | 
      cache: new_cache,
      size: map_size(new_cache)
    }
    
    {:reply, :ok, new_state}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.get(state.cache, key) do
      nil ->
        new_state = %{state | misses: state.misses + 1}
        {:reply, {:error, :not_found}, new_state}
      
      {value, expires_at, _persistent} ->
        if expires_at == :infinity or System.monotonic_time(:second) < expires_at do
          new_state = %{state | hits: state.hits + 1}
          {:reply, {:ok, value}, new_state}
        else
          # Expired
          new_cache = Map.delete(state.cache, key)
          new_state = %{state | 
            cache: new_cache,
            size: map_size(new_cache),
            misses: state.misses + 1
          }
          {:reply, {:error, :expired}, new_state}
        end
    end
  end

  def handle_call({:delete, key}, _from, state) do
    new_cache = Map.delete(state.cache, key)
    
    # Also delete from disk
    if state.config.enable_disk do
      delete_from_disk(key, state.config.persist_dir)
    end
    
    new_state = %{state | 
      cache: new_cache,
      size: map_size(new_cache)
    }
    
    {:reply, :ok, new_state}
  end

  def handle_call({:query, table, opts}, _from, state) do
    where = Keyword.get(opts, :where, [])
    limit = Keyword.get(opts, :limit, nil)
    order_by = Keyword.get(opts, :order_by, nil)
    
    # Get all records for this table
    records = state.cache
    |> Enum.filter(fn {key, {_value, _expires, _persistent}} ->
      String.starts_with?(key, "#{table}:")
    end)
    |> Enum.map(fn {_key, {value, _expires, _persistent}} -> value end)
    |> Enum.filter(fn record ->
      # Apply where clauses
      Enum.all?(where, fn {field, expected} ->
        Map.get(record, field) == expected
      end)
    end)
    
    # Sort if requested
    records = if order_by do
      Enum.sort_by(records, &Map.get(&1, order_by))
    else
      records
    end
    
    # Limit results
    records = if limit do
      Enum.take(records, limit)
    else
      records
    end
    
    {:reply, {:ok, records}, state}
  end

  def handle_call({:update, key, updates}, _from, state) do
    case Map.get(state.cache, key) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      {value, expires_at, persistent} ->
        updated_value = Map.merge(value, updates)
        updated_value = Map.put(updated_value, :_updated_at, DateTime.utc_now())
        
        new_cache = Map.put(state.cache, key, {updated_value, expires_at, persistent})
        
        # Update disk if persistent
        if persistent and state.config.enable_disk do
          save_to_disk(key, updated_value, state.config.persist_dir)
        end
        
        {:reply, {:ok, updated_value}, %{state | cache: new_cache}}
    end
  end

  def handle_call(:stats, _from, state) do
    total_requests = state.hits + state.misses
    hit_rate = if total_requests > 0, do: state.hits / total_requests, else: 0.0
    
    stats = %{
      size: state.size,
      max_size: state.config.max_size,
      hits: state.hits,
      misses: state.misses,
      hit_rate: Float.round(hit_rate * 100, 2),
      memory_usage: estimate_memory_usage(state.cache)
    }
    
    {:reply, stats, state}
  end

  def handle_call(:clear, _from, state) do
    # Clear memory
    new_state = %{state |
      cache: %{},
      size: 0,
      hits: 0,
      misses: 0
    }
    
    # Clear disk
    if state.config.enable_disk do
      File.rm_rf!(state.config.persist_dir)
      File.mkdir_p!(state.config.persist_dir)
    end
    
    {:reply, :ok, new_state}
  end

  def handle_call({:list, prefix}, _from, state) do
    keys = 
      state.cache
      |> Map.keys()
      |> Enum.filter(fn key -> String.starts_with?(key, prefix) end)
    
    {:reply, keys, state}
  end

  def handle_call({:invalidate, pattern}, _from, state) do
    # Remove keys matching pattern
    {to_remove, to_keep} = Map.split_with(state.cache, fn {key, _value} ->
      String.contains?(key, pattern)
    end)
    
    # Delete from disk
    if state.config.enable_disk do
      Enum.each(to_remove, fn {key, {_value, _expires, persistent}} ->
        if persistent do
          delete_from_disk(key, state.config.persist_dir)
        end
      end)
    end
    
    new_state = %{state |
      cache: to_keep,
      size: map_size(to_keep)
    }
    
    {:reply, {:ok, map_size(to_remove)}, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove expired entries
    now = System.monotonic_time(:second)
    
    {expired, valid} = Map.split_with(state.cache, fn {_key, {_value, expires_at, _persistent}} ->
      expires_at != :infinity and now >= expires_at
    end)
    
    # Delete expired from disk
    if state.config.enable_disk do
      Enum.each(expired, fn {key, {_value, _expires, persistent}} ->
        if persistent do
          delete_from_disk(key, state.config.persist_dir)
        end
      end)
    end
    
    new_state = %{state |
      cache: valid,
      size: map_size(valid)
    }
    
    # Schedule next cleanup
    schedule_cleanup(state.config.cleanup_interval)
    
    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  defp save_to_disk(key, value, dir) do
    file = Path.join(dir, "#{Base.url_encode64(key, padding: false)}.json")
    
    data = %{
      key: key,
      value: value,
      saved_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    File.write!(file, Jason.encode!(data))
  end

  defp load_from_disk(key) do
    dir = @default_config.persist_dir
    file = Path.join(dir, "#{Base.url_encode64(key, padding: false)}.json")
    
    case File.read(file) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, data} -> {:ok, data.value}
          {:error, reason} -> {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_from_disk(key, dir) do
    file = Path.join(dir, "#{Base.url_encode64(key, padding: false)}.json")
    File.rm_rf(file)
  end

  defp generate_id do
    Zixir.Utils.generate_id(bytes: 8)
  end

  defp estimate_memory_usage(cache) do
    # Rough estimate based on number of entries
    # In production, you'd use :erlang.term_to_binary/1 to get actual size
    entry_count = map_size(cache)
    estimate = entry_count * 1024  # Assume 1KB per entry on average
    
    Zixir.Utils.format_bytes(estimate)
  end
end
