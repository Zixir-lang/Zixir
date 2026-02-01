defmodule Zixir.Modules do
  @moduledoc """
  Module system for Zixir: import resolution, caching, and dependency management.
  
  Supports:
  - Local imports: `import "./local_module"`
  - Standard library: `import "std/math"`
  - Package imports: `import "package_name/module"`
  - Circular import detection
  - Module caching for performance
  """

  use GenServer

  require Logger

  @stdlib_modules %{
    "std/math" => :math,
    "std/string" => :string,
    "std/list" => :list,
    "std/io" => :io,
    "std/json" => :json,
    "std/random" => :random,
    "std/stat" => :stat,
    "std/time" => :time
  }

  # Client API

  @doc """
  Start the Modules service.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Resolve and load a module by path.
  Returns {:ok, module_ast} or {:error, reason}
  """
  @spec resolve(String.t(), String.t() | nil) :: {:ok, term()} | {:error, String.t()}
  def resolve(path, from_file \\ nil) do
    GenServer.call(__MODULE__, {:resolve, path, from_file}, Application.get_env(:zixir, :modules_timeout, 30_000))
  end

  @doc """
  Import a module and merge its public exports into the current scope.
  """
  @spec import_module(String.t(), String.t() | nil) :: {:ok, term()} | {:error, String.t()}
  def import_module(path, from_file \\ nil) do
    case resolve(path, from_file) do
      {:ok, module} -> {:ok, extract_exports(module)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a module is cached.
  """
  @spec cached?(String.t()) :: boolean()
  def cached?(path) do
    GenServer.call(__MODULE__, {:cached?, path})
  end

  @doc """
  Clear the module cache.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  @doc """
  Get cache statistics.
  """
  @spec cache_stats() :: map()
  def cache_stats do
    GenServer.call(__MODULE__, :cache_stats)
  end

  @doc """
  Get the search paths for module resolution.
  """
  @spec search_paths() :: list(String.t())
  def search_paths do
    default_paths = [
      Path.join(File.cwd!(), "lib"),
      Path.join(File.cwd!(), "modules"),
      Path.join(File.cwd!(), "vendor")
    ]
    
    Application.get_env(:zixir, :module_paths, default_paths)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      cache: %{},           # path => {ast, mtime}
      loading: MapSet.new(), # paths currently being loaded (for circular detection)
      import_stack: [],     # stack for error reporting
      stats: %{
        hits: 0,
        misses: 0,
        errors: 0
      }
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:resolve, path, from_file}, _from, state) do
    case do_resolve(path, from_file, state) do
      {:ok, ast, new_state} ->
        {:reply, {:ok, ast}, new_state}
      
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call({:cached?, path}, _from, state) do
    cached = Map.has_key?(state.cache, path)
    {:reply, cached, state}
  end

  def handle_call(:cache_stats, _from, state) do
    stats = Map.put(state.stats, :size, map_size(state.cache))
    {:reply, stats, state}
  end

  @impl true
  def handle_cast(:clear_cache, state) do
    {:noreply, %{state | cache: %{}}}
  end

  # Private Functions

  defp do_resolve(path, from_file, state) do
    # Check for circular imports
    if MapSet.member?(state.loading, path) do
      error = "Circular import detected: #{path}"
      Logger.error(error)
      {:error, error, update_stats(state, :errors)}
    else
      # Check cache first
      case Map.get(state.cache, path) do
        {ast, mtime} ->
          # Verify file hasn't changed
          case get_file_mtime(path) do
            {:ok, current_mtime} when current_mtime == mtime ->
              # Cache hit
              {:ok, ast, update_stats(state, :hits)}
            
            _ ->
              # Cache stale, reload
              load_module(path, from_file, state)
          end
        
        nil ->
          # Cache miss
          load_module(path, from_file, update_stats(state, :misses))
      end
    end
  end

  defp load_module(path, from_file, state) do
    # Mark as loading
    state = %{state | loading: MapSet.put(state.loading, path)}
    
    result = case resolve_path(path, from_file) do
      {:ok, full_path} ->
        case File.read(full_path) do
          {:ok, source} ->
            case parse_and_compile(source, full_path) do
              {:ok, ast} ->
                # Cache the result
                {:ok, mtime} = get_file_mtime(full_path)
                cache = Map.put(state.cache, path, {ast, mtime})
                {:ok, ast, %{state | cache: cache}}
              
              {:error, reason} ->
                {:error, "Failed to compile #{path}: #{reason}", state}
            end
          
          {:error, reason} ->
            {:error, "Cannot read #{path}: #{reason}", state}
        end
      
      {:error, reason} ->
        {:error, "Cannot resolve #{path}: #{reason}", state}
    end
    
    # Unmark as loading
    {status, ast_or_error, final_state} = result
    final_state = %{final_state | loading: MapSet.delete(final_state.loading, path)}
    
    {status, ast_or_error, final_state}
  end

  defp resolve_path(path, from_file) do
    cond do
      # Absolute path
      Path.type(path) == :absolute ->
        find_file(path)
      
      # Relative path
      String.starts_with?(path, "./") or String.starts_with?(path, "../") ->
        base = if from_file, do: Path.dirname(from_file), else: File.cwd!()
        find_file(Path.join(base, path))
      
      # Standard library
      String.starts_with?(path, "std/") ->
        resolve_stdlib(path)
      
      # Package/module search
      true ->
        search_in_paths(path)
    end
  end

  defp find_file(path) do
    extensions = [".zr", ".zixir", ""]
    
    found = Enum.find_value(extensions, fn ext ->
      full = path <> ext
      if File.exists?(full), do: full, else: nil
    end)
    
    if found do
      {:ok, found}
    else
      Zixir.Errors.file_not_found(path)
    end
  end

  defp resolve_stdlib(path) do
    case Map.get(@stdlib_modules, path) do
      nil ->
        # Generate built-in module AST
        {:ok, generate_stdlib_module(path)}
      
      _module_name ->
        {:ok, generate_stdlib_module(path)}
    end
  end

  defp generate_stdlib_module("std/math") do
    {:program, [
      # Trigonometric functions
      {:function, "sin", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "cos", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "tan", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "asin", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "acos", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "atan", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      # Hyperbolic functions
      {:function, "sinh", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "cosh", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "tanh", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      # Power and logarithmic functions
      {:function, "sqrt", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "pow", [{"x", {:type, :Float}}, {"y", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}, {:var, "y", 1, 1}]}, true, 1, 1},
      {:function, "log", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "log10", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "log2", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "exp", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "exp2", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      # Rounding functions
      {:function, "floor", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "ceil", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "round", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "trunc", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      # Other functions
      {:function, "abs", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "sign", [{"x", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "factorial", [{"n", {:type, :Int}}], {:type, :Int}, 
       {:call, {:var, "python", 1, 1}, [{:var, "n", 1, 1}]}, true, 1, 1},
      # Constants
      {:function, "pi", [], {:type, :Float}, 
       {:number, 3.141592653589793, 1, 1}, true, 1, 1},
      {:function, "e", [], {:type, :Float}, 
       {:number, 2.718281828459045, 1, 1}, true, 1, 1}
    ]}
  end

  defp generate_stdlib_module("std/list") do
    {:program, [
      # Transform
      {:function, "map", [{"list", {:type, :Array, {:type, :Float}}}, {"f", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "map2", [{"l1", {:type, :Array, {:type, :Float}}}, {"l2", {:type, :Array, {:type, :Float}}}, {"f", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "l1", 1, 1}, {:var, "l2", 1, 1}]}, true, 1, 1},
      {:function, "flat_map", [{"list", {:type, :Array, {:type, :Float}}}, {"f", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      # Filter
      {:function, "filter", [{"list", {:type, :Array, {:type, :Float}}}, {"pred", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "filter_map", [{"list", {:type, :Array, {:type, :Float}}}, {"pred", {:type, :Function}}, {"f", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "reject", [{"list", {:type, :Array, {:type, :Float}}}, {"pred", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      # Reduce/Aggregate
      {:function, "sum", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "product", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "reduce", [{"list", {:type, :Array, {:type, :Float}}}, {"acc", {:type, :Float}}, {"f", {:type, :Function}}], 
       {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}, {:var, "acc", 1, 1}]}, true, 1, 1},
      {:function, "foldl", [{"list", {:type, :Array, {:type, :Float}}}, {"acc", {:type, :Float}}, {"f", {:type, :Function}}], 
       {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}, {:var, "acc", 1, 1}]}, true, 1, 1},
      {:function, "foldr", [{"list", {:type, :Array, {:type, :Float}}}, {"acc", {:type, :Float}}, {"f", {:type, :Function}}], 
       {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}, {:var, "acc", 1, 1}]}, true, 1, 1},
      # Query
      {:function, "length", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Int}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "head", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "tail", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "last", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "at", [{"list", {:type, :Array, {:type, :Float}}}, {"n", {:type, :Int}}], {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}, {:var, "n", 1, 1}]}, true, 1, 1},
      # Check
      {:function, "empty?", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Bool}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "member?", [{"list", {:type, :Array, {:type, :Float}}}, {"x", {:type, :Float}}], {:type, :Bool}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}, {:var, "x", 1, 1}]}, true, 1, 1},
      {:function, "all?", [{"list", {:type, :Array, {:type, :Float}}}, {"pred", {:type, :Function}}], {:type, :Bool}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "any?", [{"list", {:type, :Array, {:type, :Float}}}, {"pred", {:type, :Function}}], {:type, :Bool}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      # Sort
      {:function, "sort", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "sort_by", [{"list", {:type, :Array, {:type, :Float}}}, {"f", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "uniq", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      # Combine
      {:function, "append", [{"l1", {:type, :Array, {:type, :Float}}}, {"l2", {:type, :Array, {:type, :Float}}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "l1", 1, 1}, {:var, "l2", 1, 1}]}, true, 1, 1},
      {:function, "concat", [{"list", {:type, :Array, {:type, :Array, {:type, :Float}}}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "zip", [{"l1", {:type, :Array, {:type, :Float}}}, {"l2", {:type, :Array, {:type, :Float}}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "l1", 1, 1}, {:var, "l2", 1, 1}]}, true, 1, 1},
      # Take/Drop
      {:function, "take", [{"list", {:type, :Array, {:type, :Float}}}, {"n", {:type, :Int}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}, {:var, "n", 1, 1}]}, true, 1, 1},
      {:function, "drop", [{"list", {:type, :Array, {:type, :Float}}}, {"n", {:type, :Int}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}, {:var, "n", 1, 1}]}, true, 1, 1},
      {:function, "take_while", [{"list", {:type, :Array, {:type, :Float}}}, {"pred", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "drop_while", [{"list", {:type, :Array, {:type, :Float}}}, {"pred", {:type, :Function}}], 
       {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1}
    ]}
  end

  defp generate_stdlib_module("std/string") do
    {:program, [
      {:function, "length", [{"s", {:type, :String}}], {:type, :Int}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "uppercase", [{"s", {:type, :String}}], {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "lowercase", [{"s", {:type, :String}}], {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "trim", [{"s", {:type, :String}}], {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "split", [{"s", {:type, :String}}, {"sep", {:type, :String}}], 
       {:type, :Array, {:type, :String}}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}, {:var, "sep", 1, 1}]}, true, 1, 1},
      {:function, "join", [{"list", {:type, :Array, {:type, :String}}}, {"sep", {:type, :String}}], 
       {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "list", 1, 1}, {:var, "sep", 1, 1}]}, true, 1, 1},
      {:function, "replace", [{"s", {:type, :String}}, {"old", {:type, :String}}, {"new", {:type, :String}}], 
       {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}, {:var, "old", 1, 1}, {:var, "new", 1, 1}]}, true, 1, 1},
      {:function, "contains?", [{"s", {:type, :String}}, {"sub", {:type, :String}}], {:type, :Bool}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}, {:var, "sub", 1, 1}]}, true, 1, 1},
      {:function, "starts_with?", [{"s", {:type, :String}}, {"prefix", {:type, :String}}], {:type, :Bool}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}, {:var, "prefix", 1, 1}]}, true, 1, 1},
      {:function, "ends_with?", [{"s", {:type, :String}}, {"suffix", {:type, :String}}], {:type, :Bool}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}, {:var, "suffix", 1, 1}]}, true, 1, 1},
      {:function, "slice", [{"s", {:type, :String}}, {"start", {:type, :Int}}, {"len", {:type, :Int}}], 
       {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}, {:var, "start", 1, 1}, {:var, "len", 1, 1}]}, true, 1, 1},
      {:function, "to_int", [{"s", {:type, :String}}], {:type, :Int}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "to_float", [{"s", {:type, :String}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "reverse", [{"s", {:type, :String}}], {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1}
    ]}
  end

  defp generate_stdlib_module("std/io") do
    {:program, [
      {:function, "print", [{"s", {:type, :String}}], {:type, :Void}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "println", [{"s", {:type, :String}}], {:type, :Void}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "read_line", [], {:type, :String}, 
       {:call, {:var, "engine", 1, 1}, []}, true, 1, 1},
      {:function, "read_all", [], {:type, :String}, 
       {:call, {:var, "engine", 1, 1}, []}, true, 1, 1}
    ]}
  end

  defp generate_stdlib_module("std/json") do
    {:program, [
      {:function, "encode", [{"data", {:type, :Dynamic}}], {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "data", 1, 1}]}, true, 1, 1},
      {:function, "decode", [{"s", {:type, :String}}], {:type, :Dynamic}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}]}, true, 1, 1},
      {:function, "encode_pretty", [{"data", {:type, :Dynamic}}], {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "data", 1, 1}]}, true, 1, 1}
    ]}
  end

  defp generate_stdlib_module("std/random") do
    {:program, [
      {:function, "uniform", [], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, []}, true, 1, 1},
      {:function, "uniform", [{"n", {:type, :Int}}], {:type, :Int}, 
       {:call, {:var, "python", 1, 1}, [{:var, "n", 1, 1}]}, true, 1, 1},
      {:function, "uniform_range", [{"a", {:type, :Float}}, {"b", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "a", 1, 1}, {:var, "b", 1, 1}]}, true, 1, 1},
      {:function, "normal", [{"mean", {:type, :Float}}, {"std", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "mean", 1, 1}, {:var, "std", 1, 1}]}, true, 1, 1},
      {:function, "shuffle", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Array, {:type, :Float}}, 
       {:call, {:var, "python", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "seed", [{"n", {:type, :Int}}], {:type, :Void}, 
       {:call, {:var, "python", 1, 1}, [{:var, "n", 1, 1}]}, true, 1, 1}
    ]}
  end

  defp generate_stdlib_module("std/stat") do
    {:program, [
      {:function, "mean", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "engine", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "median", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "variance", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "std_dev", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "mode", [{"list", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "list", 1, 1}]}, true, 1, 1},
      {:function, "percentile", [{"list", {:type, :Array, {:type, :Float}}}, {"p", {:type, :Float}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "list", 1, 1}, {:var, "p", 1, 1}]}, true, 1, 1},
      {:function, "correlation", [{"l1", {:type, :Array, {:type, :Float}}}, {"l2", {:type, :Array, {:type, :Float}}}], {:type, :Float}, 
       {:call, {:var, "python", 1, 1}, [{:var, "l1", 1, 1}, {:var, "l2", 1, 1}]}, true, 1, 1}
    ]}
  end

  defp generate_stdlib_module("std/time") do
    {:program, [
      {:function, "now", [], {:type, :Int}, 
       {:call, {:var, "python", 1, 1}, []}, true, 1, 1},
      {:function, "sleep", [{"ms", {:type, :Int}}], {:type, :Void}, 
       {:call, {:var, "python", 1, 1}, [{:var, "ms", 1, 1}]}, true, 1, 1},
      {:function, "format_timestamp", [{"ts", {:type, :Int}}, {"fmt", {:type, :String}}], {:type, :String}, 
       {:call, {:var, "python", 1, 1}, [{:var, "ts", 1, 1}, {:var, "fmt", 1, 1}]}, true, 1, 1},
      {:function, "parse_timestamp", [{"s", {:type, :String}}, {"fmt", {:type, :String}}], {:type, :Int}, 
       {:call, {:var, "python", 1, 1}, [{:var, "s", 1, 1}, {:var, "fmt", 1, 1}]}, true, 1, 1}
    ]}
  end

  defp generate_stdlib_module(_path) do
    # Default empty module
    {:program, []}
  end

  defp search_in_paths(path) do
    paths = search_paths()
    
    found = Enum.find_value(paths, fn dir ->
      case find_file(Path.join(dir, path)) do
        {:ok, full} -> full
        _ -> nil
      end
    end)
    
    if found do
      {:ok, found}
    else
      Zixir.Errors.file_not_found_in_paths(path, [])
    end
  end

  defp parse_and_compile(source, path) do
    case Zixir.Compiler.Parser.parse(source) do
      {:ok, ast} ->
        # Process imports within the module
        {:ok, processed_ast} = process_imports(ast, path)
        {:ok, processed_ast}
      
      {:error, error} ->
        {:error, "Parse error in #{path}: #{error.message}"}
    end
  end

  defp process_imports({:program, statements}, path) do
    {imports, other} = Enum.split_with(statements, fn
      {:import, _, _, _} -> true
      _ -> false
    end)
    
    # Resolve all imports
    resolved_imports = Enum.reduce(imports, [], fn {:import, import_path, _line, _col}, acc ->
      case resolve(import_path, path) do
        {:ok, module} -> [{import_path, module} | acc]
        {:error, reason} -> 
          Logger.warning("Failed to import #{import_path}: #{reason}")
          acc
      end
    end)
    
    # Create new program with resolved imports
    {:ok, {:program, other, imports: resolved_imports}}
  end

  defp get_file_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> {:ok, mtime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_stats(state, key) do
    %{state | stats: Map.update!(state.stats, key, &(&1 + 1))}
  end

  defp extract_exports({:program, statements, _opts}) do
    Enum.filter(statements, fn
      {:function, _, _, _, _, is_pub, _, _} -> is_pub
      {:type_def, _, _, _, _} -> true
      _ -> false
    end)
  end

  defp extract_exports({:program, statements}) do
    Enum.filter(statements, fn
      {:function, _, _, _, _, is_pub, _, _} -> is_pub
      {:type_def, _, _, _, _} -> true
      _ -> false
    end)
  end
end
