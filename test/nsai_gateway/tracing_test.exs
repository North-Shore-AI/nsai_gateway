defmodule NsaiGateway.TracingTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias NsaiGateway.Tracing

  describe "ensure_trace_headers/1" do
    test "generates trace headers when missing" do
      conn = conn(:get, "/test")
      conn = Tracing.ensure_trace_headers(conn)

      assert Tracing.get_trace_id(conn) != nil
      assert Tracing.get_request_id(conn) != nil
    end

    test "preserves existing trace headers" do
      existing_trace_id = "existing-trace-123"

      conn =
        conn(:get, "/test")
        |> put_req_header("x-trace-id", existing_trace_id)
        |> Tracing.ensure_trace_headers()

      assert Tracing.get_trace_id(conn) == existing_trace_id
    end

    test "adds trace headers to response" do
      conn =
        conn(:get, "/test")
        |> Tracing.ensure_trace_headers()
        |> send_resp(200, "ok")

      trace_id = Tracing.get_trace_id(conn)
      assert get_resp_header(conn, "x-trace-id") == [trace_id]
    end
  end

  describe "extract_trace_headers/1" do
    test "extracts all trace headers" do
      conn =
        conn(:get, "/test")
        |> put_req_header("x-trace-id", "trace-123")
        |> put_req_header("x-request-id", "request-456")
        |> put_req_header("x-correlation-id", "corr-789")

      headers = Tracing.extract_trace_headers(conn)

      assert headers["x-trace-id"] == "trace-123"
      assert headers["x-request-id"] == "request-456"
      assert headers["x-correlation-id"] == "corr-789"
    end

    test "omits missing headers" do
      conn = conn(:get, "/test")
      headers = Tracing.extract_trace_headers(conn)

      # Should have generated headers but not nil values
      refute Map.has_key?(headers, nil)
    end
  end

  describe "as plug" do
    test "adds trace context to logger metadata" do
      _conn =
        conn(:get, "/test")
        |> Tracing.call([])

      # Logger metadata should be set
      metadata = Logger.metadata()
      assert metadata[:trace_id] != nil
      assert metadata[:method] == "GET"
      assert metadata[:path] == "/test"
    end
  end
end
