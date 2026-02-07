defmodule ZixirWeb.SSEController do
  @moduledoc """
  Server-Sent Events (SSE) controller for real-time dashboard updates.
  
  Replaces polling with push-based updates for a fluid, responsive UI.
  
  ## Endpoints
  
  - `GET /api/events` - Main SSE stream (all topics)
  - `GET /api/events/:topic` - SSE stream for a specific topic
  
  ## Usage in HTML (with HTMX)
  
      <div hx-ext="sse" sse-connect="/api/events" sse-swap="metrics">
        <!-- Content updates in real-time -->
      </div>
  
  ## Event Format
  
      event: metrics
      data: {"workflows_active": 5, "connections_active": 3, ...}
      
      event: workflows
      data: [{"id": "wf_123", "status": "running", ...}]
  """
  
  use Phoenix.Controller, namespace: ZixirWeb
  require Logger
  
  @heartbeat_interval 30_000  # 30 seconds
  
  @doc """
  Main SSE endpoint - streams all topics.
  """
  def stream(conn, params) do
    topics = parse_topics(params)
    
    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> put_resp_header("x-accel-buffering", "no")  # Disable nginx buffering
    |> send_chunked(200)
    |> subscribe_and_stream(topics)
  end
  
  @doc """
  Topic-specific SSE endpoint.
  """
  def stream_topic(conn, %{"topic" => topic}) do
    stream(conn, %{"topics" => topic})
  end
  
  # Private functions
  
  defp parse_topics(%{"topics" => topics}) when is_binary(topics) do
    topics |> String.split(",") |> Enum.map(&String.trim/1)
  end
  defp parse_topics(_), do: Zixir.Events.topics()
  
  defp subscribe_and_stream(conn, topics) do
    # Subscribe to requested topics
    Enum.each(topics, fn topic ->
      Zixir.Events.subscribe(topic)
    end)
    
    # Send initial connection event
    case send_sse_event(conn, "connected", %{topics: topics, timestamp: DateTime.utc_now()}) do
      {:ok, conn} ->
        # Start heartbeat timer
        schedule_heartbeat()
        
        # Enter the streaming loop
        stream_loop(conn, topics)
        
      {:error, _reason} ->
        # Client disconnected immediately
        cleanup(topics)
        conn
    end
  end
  
  defp stream_loop(conn, topics) do
    receive do
      {:sse_event, topic, data} ->
        case send_sse_event(conn, topic, data) do
          {:ok, conn} -> 
            stream_loop(conn, topics)
          {:error, _reason} ->
            # Client disconnected
            cleanup(topics)
            conn
        end
        
      :heartbeat ->
        case send_sse_comment(conn, "heartbeat") do
          {:ok, conn} ->
            schedule_heartbeat()
            stream_loop(conn, topics)
          {:error, _reason} ->
            cleanup(topics)
            conn
        end
        
      {:DOWN, _, _, _, _} ->
        cleanup(topics)
        conn
        
    after
      60_000 ->
        # Timeout - send keepalive
        case send_sse_comment(conn, "keepalive") do
          {:ok, conn} -> stream_loop(conn, topics)
          {:error, _} ->
            cleanup(topics)
            conn
        end
    end
  end
  
  defp send_sse_event(conn, event_type, data) do
    json_data = Jason.encode!(data)
    
    chunk_data = """
    event: #{event_type}
    data: #{json_data}
    
    """
    
    case Plug.Conn.chunk(conn, chunk_data) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp send_sse_comment(conn, comment) do
    case Plug.Conn.chunk(conn, ": #{comment}\n\n") do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end
  
  defp cleanup(topics) do
    Enum.each(topics, fn topic ->
      Zixir.Events.unsubscribe(topic)
    end)
  end
end
