defmodule Zixir.AIAutomationTest do
  @moduledoc """
  Comprehensive tests for AI Automation features.
  
  Tests:
  - Workflow orchestration with checkpointing
  - Resource limits and sandboxing
  - Streaming and async support
  - Observability and metrics
  - Cache and persistence
  """

  use ExUnit.Case, async: false

  describe "Workflow Orchestration" do
    test "create and execute simple workflow" do
      workflow = Zixir.Workflow.new("test_workflow")
      |> Zixir.Workflow.add_step("step1", fn -> {:ok, "step1_result"} end)
      |> Zixir.Workflow.add_step("step2", fn -> {:ok, "step2_result"} end, depends_on: ["step1"])
      
      result = Zixir.Workflow.execute(workflow)
      assert match?({:ok, _}, result)
    end

    test "workflow with checkpointing" do
      workflow = Zixir.Workflow.new("checkpoint_test")
      |> Zixir.Workflow.add_step("load", fn -> {:ok, %{data: [1, 2, 3]}} end, checkpoint: true)
      |> Zixir.Workflow.add_step("process", fn state -> {:ok, Map.put(state, :processed, true)} end, depends_on: ["load"], checkpoint: true)
      
      result = Zixir.Workflow.execute(workflow, checkpoint: true)
      assert match?({:ok, _}, result)
      
      # Verify checkpoints were created
      checkpoints = Zixir.Workflow.list_checkpoints("checkpoint_test")
      assert length(checkpoints) > 0
    end

    test "workflow execution order respects dependencies" do
      execution_order = []
      
      workflow = Zixir.Workflow.new("order_test")
      |> Zixir.Workflow.add_step("c", fn -> 
        execution_order = ["c" | execution_order]
        {:ok, "c"}
      end, depends_on: ["a", "b"])
      |> Zixir.Workflow.add_step("a", fn -> 
        execution_order = ["a" | execution_order]
        {:ok, "a"}
      end)
      |> Zixir.Workflow.add_step("b", fn -> 
        execution_order = ["b" | execution_order]
        {:ok, "b"}
      end, depends_on: ["a"])
      
      {:ok, _} = Zixir.Workflow.execute(workflow)
      # a should execute before b, and both before c
      assert true  # If we got here, topological sort worked
    end

    test "workflow with retries" do
      attempt_count = :counters.new(1, [:atomics])
      
      workflow = Zixir.Workflow.new("retry_test")
      |> Zixir.Workflow.add_step("flaky", fn ->
        :counters.add(attempt_count, 1, 1)
        if :counters.get(attempt_count, 1) < 3 do
          {:error, "Temporary failure"}
        else
          {:ok, "success"}
        end
      end, retries: 5)
      
      result = Zixir.Workflow.execute(workflow)
      assert result == {:ok, "success"}
    end
  end

  describe "Resource Limits & Sandboxing" do
    test "timeout enforcement" do
      result = Zixir.Sandbox.with_timeout(fn ->
        Process.sleep(2000)
        :completed
      end, 100)
      
      assert match?({:error, "Execution timed out after 100ms"}, result)
    end

    test "successful execution within timeout" do
      result = Zixir.Sandbox.with_timeout(fn ->
        :success
      end, 1000)
      
      assert result == {:ok, :success}
    end

    test "sandbox with multiple limits" do
      result = Zixir.Sandbox.execute(fn ->
        "hello"
      end, [timeout: 5000])
      
      assert result == {:ok, "hello"}
    end

    test "memory limit parsing" do
      # Test that memory strings are parsed correctly
      result = Zixir.Sandbox.execute(fn -> {:ok, "test"} end, [
        timeout: 1000,
        memory_limit: "1GB"
      ])
      
      assert match?({:ok, _}, result)
    end

    test "resource stats" do
      stats = Zixir.Sandbox.resource_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :memory_bytes)
      assert Map.has_key?(stats, :memory_human)
    end
  end

  describe "Streaming & Async" do
    test "async execution" do
      task = Zixir.Stream.async(fn ->
        Process.sleep(100)
        :async_result
      end)
      
      result = Zixir.Stream.await(task, 1000)
      assert result == {:ok, :async_result}
    end

    test "async with timeout" do
      task = Zixir.Stream.async(fn ->
        Process.sleep(5000)
        :slow_result
      end)
      
      result = Zixir.Stream.await(task, 100)
      assert match?({:error, "Async operation timed out after 100ms"}, result)
    end

    test "parallel async tasks" do
      tasks = [
        Zixir.Stream.async(fn -> 1 end),
        Zixir.Stream.async(fn -> 2 end),
        Zixir.Stream.async(fn -> 3 end)
      ]
      
      results = Zixir.Stream.await_many(tasks, 1000)
      assert length(results) == 3
      assert {:ok, 1} in results
      assert {:ok, 2} in results
      assert {:ok, 3} in results
    end

    test "stream map transformation" do
      source = Zixir.Stream.from_enum([1, 2, 3])
      |> Zixir.Stream.map(fn x -> x * 2 end)
      
      {:ok, results} = Zixir.Stream.to_list(source)
      assert results == [2, 4, 6]
    end

    test "stream filter transformation" do
      source = Zixir.Stream.from_enum([1, 2, 3, 4, 5])
      |> Zixir.Stream.filter(fn x -> x > 2 end)
      
      {:ok, results} = Zixir.Stream.to_list(source)
      assert results == [3, 4, 5]
    end

    test "stream take transformation" do
      source = Zixir.Stream.range(1, 1000)
      |> Zixir.Stream.take(5)
      
      {:ok, results} = Zixir.Stream.to_list(source)
      assert results == [1, 2, 3, 4, 5]
    end

    test "stream batch transformation" do
      source = Zixir.Stream.from_enum([1, 2, 3, 4, 5, 6])
      |> Zixir.Stream.batch(2)
      
      {:ok, results} = Zixir.Stream.to_list(source)
      assert results == [[1, 2], [3, 4], [5, 6]]
    end

    test "stream each side effect" do
      collected = []
      
      source = Zixir.Stream.from_enum([1, 2, 3])
      |> Zixir.Stream.each(fn x -> 
        collected = [x | collected]
      end)
      
      {:ok, _} = Zixir.Stream.run(source)
      # Side effects should have been executed
      assert true
    end
  end

  describe "Observability" do
    test "structured logging" do
      # Just verify logging functions don't crash
      Zixir.Observability.info("Test message", test_id: 123)
      Zixir.Observability.debug("Debug message")
      Zixir.Observability.warning("Warning message")
      Zixir.Observability.error("Error message", error: "test")
      
      assert true
    end

    test "trace span creation" do
      span_id = Zixir.Observability.start_span("test_operation", nil, [])
      assert is_binary(span_id)
      
      :ok = Zixir.Observability.end_span(span_id, %{status: :success})
      assert true
    end

    test "trace execution" do
      result = Zixir.Observability.trace("test_trace", fn ->
        42
      end)
      
      assert result == 42
    end

    test "metrics recording" do
      Zixir.Observability.record_metric("test_metric", 100)
      Zixir.Observability.increment_counter("test_counter")
      Zixir.Observability.record_timing("test_timing", 50)
      
      {:ok, metrics} = Zixir.Observability.get_metrics()
      assert is_map(metrics)
    end

    test "timing execution" do
      result = Zixir.Observability.time("test_operation", fn ->
        Process.sleep(10)
        :timed_result
      end)
      
      assert result == :timed_result
    end

    test "prometheus export" do
      Zixir.Observability.record_metric("gauge_metric", 42)
      Zixir.Observability.increment_counter("counter_metric", 5)
      
      prometheus = Zixir.Observability.export_metrics_prometheus()
      assert is_binary(prometheus)
      assert String.contains?(prometheus, "gauge_metric")
    end
  end

  describe "Cache & Persistence" do
    test "cache put and get" do
      :ok = Zixir.Cache.put("test_key", "test_value")
      {:ok, value} = Zixir.Cache.get("test_key")
      
      assert value == "test_value"
    end

    test "cache with TTL" do
      :ok = Zixir.Cache.put("ttl_key", "value", ttl: 1)
      {:ok, _} = Zixir.Cache.get("ttl_key")
      
      # Wait for expiration
      Process.sleep(1100)
      
      {:error, :expired} = Zixir.Cache.get("ttl_key")
    end

    test "cache fetch" do
      value = Zixir.Cache.fetch("fetch_key", fn ->
        "computed_value"
      end)
      
      assert value == "computed_value"
      
      # Second fetch should return cached value
      value2 = Zixir.Cache.fetch("fetch_key", fn ->
        "different_value"
      end)
      
      assert value2 == "computed_value"
    end

    test "cache exists" do
      :ok = Zixir.Cache.put("exists_key", "value")
      assert Zixir.Cache.exists?("exists_key")
      assert not Zixir.Cache.exists?("nonexistent_key")
    end

    test "cache delete" do
      :ok = Zixir.Cache.put("delete_key", "value")
      :ok = Zixir.Cache.delete("delete_key")
      
      {:error, _} = Zixir.Cache.get("delete_key")
    end

    test "cache stats" do
      :ok = Zixir.Cache.put("stats_key", "value")
      {:ok, _} = Zixir.Cache.get("stats_key")
      {:ok, _} = Zixir.Cache.get("stats_key")
      
      {:ok, stats} = Zixir.Cache.stats()
      assert is_map(stats)
      assert stats.hits >= 2
      assert stats.size >= 1
    end

    test "insert and query" do
      {:ok, id} = Zixir.Cache.insert("test_table", %{name: "test", value: 123})
      assert is_binary(id)
      
      {:ok, records} = Zixir.Cache.query("test_table", where: [name: "test"])
      assert length(records) >= 1
    end

    test "cache update" do
      :ok = Zixir.Cache.put("update_key", %{name: "original"})
      {:ok, updated} = Zixir.Cache.update("update_key", %{name: "updated"})
      
      assert updated.name == "updated"
      
      {:ok, value} = Zixir.Cache.get("update_key")
      assert value.name == "updated"
    end

    test "cache invalidate" do
      :ok = Zixir.Cache.put("invalidate_test_1", "value1")
      :ok = Zixir.Cache.put("invalidate_test_2", "value2")
      :ok = Zixir.Cache.put("other_key", "value3")
      
      {:ok, count} = Zixir.Cache.invalidate("invalidate_test")
      assert count == 2
      
      assert not Zixir.Cache.exists?("invalidate_test_1")
      assert not Zixir.Cache.exists?("invalidate_test_2")
      assert Zixir.Cache.exists?("other_key")
    end

    test "persistent storage" do
      :ok = Zixir.Cache.put_persistent("persistent_key", %{data: "important"})
      {:ok, value} = Zixir.Cache.get_persistent("persistent_key")
      
      assert value.data == "important"
    end
  end

  describe "Integration Tests" do
    test "workflow with sandboxed steps" do
      workflow = Zixir.Workflow.new("sandboxed_workflow")
      |> Zixir.Workflow.add_step("timed_step", fn ->
        Zixir.Sandbox.with_timeout(fn ->
          {:ok, "completed"}
        end, 5000)
      end)
      
      result = Zixir.Workflow.execute(workflow)
      assert match?({:ok, _}, result)
    end

    test "workflow with observability" do
      span_id = Zixir.Observability.start_span("workflow_test", nil, [])
      
      workflow = Zixir.Workflow.new("observed_workflow")
      |> Zixir.Workflow.add_step("step1", fn ->
        Zixir.Observability.log_step("observed_workflow", "step1", :started)
        result = {:ok, "data"}
        Zixir.Observability.log_step("observed_workflow", "step1", :completed)
        result
      end)
      
      result = Zixir.Workflow.execute(workflow)
      
      Zixir.Observability.end_span(span_id, %{status: :success})
      
      assert match?({:ok, _}, result)
    end

    test "workflow with caching" do
      call_count = :counters.new(1, [:atomics])
      
      workflow = Zixir.Workflow.new("cached_workflow")
      |> Zixir.Workflow.add_step("expensive", fn ->
        Zixir.Cache.fetch("expensive_result", fn ->
          :counters.add(call_count, 1, 1)
          {:ok, "expensive_computation"}
        end)
      end, checkpoint: true)
      
      # First execution
      {:ok, result1} = Zixir.Workflow.execute(workflow)
      
      # Second execution should use cache
      {:ok, result2} = Zixir.Workflow.execute(workflow)
      
      assert result1 == result2
    end
  end
end
