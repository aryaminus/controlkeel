defmodule ControlKeelWeb.Plugs.IpRateLimitTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Cloud.RateLimiter
  alias ControlKeelWeb.Plugs.IpRateLimit

  setup do
    RateLimiter.reset()
    :ok
  end

  defp conn(ip), do: %{build_conn(:post, "/") | remote_ip: ip}

  test "passes the request through while the bucket has tokens" do
    conn = IpRateLimit.call(conn({192, 0, 2, 1}), bucket: "plug-test", burst: 2)

    refute conn.halted
  end

  test "halts with 429 and Retry-After when the bucket is exhausted" do
    opts = [bucket: "plug-exhausted", burst: 1, refill_per_sec: 0.001]

    assert %{halted: false} = IpRateLimit.call(conn({192, 0, 2, 2}), opts)

    conn = IpRateLimit.call(conn({192, 0, 2, 2}), opts)

    assert conn.halted
    assert conn.status == 429
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) >= 1
    assert conn.resp_body =~ "rate_limited"
  end

  test "separate client IPs have independent buckets" do
    opts = [bucket: "plug-ip-isolation", burst: 1, refill_per_sec: 0.001]

    assert %{halted: false} = IpRateLimit.call(conn({192, 0, 2, 3}), opts)
    assert %{halted: false} = IpRateLimit.call(conn({192, 0, 2, 4}), opts)
    assert %{halted: true} = IpRateLimit.call(conn({192, 0, 2, 3}), opts)
  end

  test "separate bucket names have independent budgets" do
    ip = {192, 0, 2, 5}
    opts = [burst: 1, refill_per_sec: 0.001]

    assert %{halted: false} = IpRateLimit.call(conn(ip), [bucket: "bucket-a"] ++ opts)
    assert %{halted: false} = IpRateLimit.call(conn(ip), [bucket: "bucket-b"] ++ opts)
    assert %{halted: true} = IpRateLimit.call(conn(ip), [bucket: "bucket-a"] ++ opts)
  end

  test "buckets proxied requests by forwarded client IP, not the proxy IP" do
    opts = [bucket: "plug-proxy", burst: 2, refill_per_sec: 0.001]
    proxy_ip = {10, 0, 0, 1}

    forwarded = fn client_ip ->
      build_conn(:post, "/")
      |> Map.put(:remote_ip, proxy_ip)
      |> put_req_header("x-forwarded-for", client_ip)
    end

    # Two visitors share the edge proxy but must not share a bucket.
    assert %{halted: false} = IpRateLimit.call(forwarded.("198.51.100.1"), opts)
    assert %{halted: false} = IpRateLimit.call(forwarded.("198.51.100.2"), opts)
    assert %{halted: false} = IpRateLimit.call(forwarded.("198.51.100.1"), opts)

    # The first visitor is now exhausted; the second still has a token.
    assert %{halted: true} = IpRateLimit.call(forwarded.("198.51.100.1"), opts)
    assert %{halted: false} = IpRateLimit.call(forwarded.("198.51.100.2"), opts)
  end
end
