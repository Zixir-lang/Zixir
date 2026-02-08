defmodule Zixir.Playground.Memory do
  @moduledoc """
  Manages conversation history and persistent insights for the AI Playground.

  Provides:
  - Session-based conversation tracking
  - Persistent storage of key insights across sessions
  - Semantic search over conversation history
  - Context retrieval for AI assistant

  ## Usage

      # Save conversation message
      Zixir.Playground.Memory.save_message(session_id, :user, "How many workflows?")
      
      # Get recent conversation
      messages = Zixir.Playground.Memory.get_conversation_history(session_id)
      
      # Store important insight
      Zixir.Playground.Memory.remember_insight("User frequently queries order data")
      
      # Recall relevant insights
      insights = Zixir.Playground.Memory.recall_relevant_insights("workflow questions")

  """

  alias Zixir.{Cache, Agent.Memory}
  require Logger

  @agent_id "playground_assistant"
  @session_ttl :timer.hours(24)

  @doc """
  Save a conversation message.
  """
  @spec save_message(String.t(), :user | :assistant, String.t(), map()) :: :ok | {:error, term()}
  def save_message(session_id, role, content, metadata \\ %{}) do
    message = %{
      id: generate_id(),
      role: role,
      content: content,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
    
    # Get existing messages
    key = "playground:session:#{session_id}:messages"
    messages = case Cache.get(key) do
      {:ok, msgs} when is_list(msgs) -> msgs
      _ -> []
    end
    
    # Add new message and save
    updated = [message | messages] |> Enum.take(100)  # Keep last 100
    Cache.put(key, updated, ttl: @session_ttl)
  end

  @doc """
  Get conversation history for a session.
  """
  @spec get_conversation_history(String.t(), integer()) :: [map()]
  def get_conversation_history(session_id, limit \\ 50) do
    key = "playground:session:#{session_id}:messages"
    
    case Cache.get(key) do
      {:ok, messages} when is_list(messages) ->
        messages
        |> Enum.reverse()  # Oldest first
        |> Enum.take(limit)
      
      _ ->
        []
    end
  end

  @doc """
  Clear conversation history for a session.
  """
  @spec clear_conversation(String.t()) :: :ok
  def clear_conversation(session_id) do
    key = "playground:session:#{session_id}:messages"
    Cache.delete(key)
  end

  @doc """
  Store an important insight in persistent memory.
  """
  @spec remember_insight(String.t(), map()) :: :ok | {:error, term()}
  def remember_insight(insight, metadata \\ %{}) do
    # Use the Agent.Memory system for persistence
    entry = %{
      content: insight,
      timestamp: DateTime.utc_now(),
      metadata: metadata,
      type: :insight
    }
    
    # Store in both short-term and long-term memory
    with :ok <- Memory.remember(@agent_id, :insight, entry, persistent: true),
         :ok <- Cache.put("playground:insights:recent", entry, ttl: @session_ttl) do
      :ok
    else
      error ->
        Logger.warning("Failed to store insight: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Recall insights relevant to a query.
  """
  @spec recall_relevant_insights(String.t(), integer()) :: [map()]
  def recall_relevant_insights(query, top_k \\ 5) do
    try do
      case Memory.semantic_search(@agent_id, query, top_k: top_k) do
        {:ok, results} -> results
        _ -> []
      end
    rescue
      _ -> []
    end
  end

  @doc """
  Get all recent insights.
  """
  @spec get_recent_insights(integer()) :: [map()]
  def get_recent_insights(limit \\ 10) do
    case Cache.get("playground:insights:recent") do
      {:ok, insights} when is_list(insights) ->
        Enum.take(insights, limit)
      
      _ ->
        []
    end
  end

  @doc """
  Summarize conversation for context window.
  """
  @spec summarize_conversation(String.t()) :: String.t()
  def summarize_conversation(session_id) do
    messages = get_conversation_history(session_id, 20)
    
    if length(messages) == 0 do
      "No previous conversation in this session."
    else
      message_count = length(messages)
      user_msgs = Enum.count(messages, &(&1.role == :user))
      
      "This session contains #{message_count} messages (#{user_msgs} from user). " <>
      "Recent topics: #{extract_topics(messages)}"
    end
  end

  @doc """
  Get conversation statistics.
  """
  @spec get_stats(String.t()) :: map()
  def get_stats(session_id) do
    messages = get_conversation_history(session_id, 1000)
    
    %{
      total_messages: length(messages),
      user_messages: Enum.count(messages, &(&1.role == :user)),
      assistant_messages: Enum.count(messages, &(&1.role == :assistant)),
      has_database_queries: Enum.any?(messages, &(&1.metadata[:sql])),
      has_workflow_discussions: Enum.any?(messages, &(String.contains?(&1.content, "workflow")))
    }
  end

  @doc """
  Export conversation to text format.
  """
  @spec export_conversation(String.t()) :: String.t()
  def export_conversation(session_id) do
    messages = get_conversation_history(session_id, 1000)
    
    messages
    |> Enum.map(fn msg ->
      role = if msg.role == :user, do: "User", else: "Assistant"
      time = msg.timestamp |> DateTime.to_string()
      "[#{time}] #{role}:\n#{msg.content}\n"
    end)
    |> Enum.join("\n---\n\n")
  end

  # Private functions

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp extract_topics(messages) do
    # Simple topic extraction based on keywords
    topics = messages
    |> Enum.filter(&(&1.role == :user))
    |> Enum.map(& &1.content)
    |> Enum.join(" ")
    |> String.downcase()
    
    keywords = []
    keywords = if String.contains?(topics, "workflow"), do: ["workflows" | keywords], else: keywords
    keywords = if String.contains?(topics, "database"), do: ["databases" | keywords], else: keywords
    keywords = if String.contains?(topics, "query"), do: ["queries" | keywords], else: keywords
    keywords = if String.contains?(topics, "table"), do: ["tables" | keywords], else: keywords
    
    case keywords do
      [] -> "general inquiries"
      list -> Enum.join(list, ", ")
    end
  end
end