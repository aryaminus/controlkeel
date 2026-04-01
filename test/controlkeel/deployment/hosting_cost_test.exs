defmodule ControlKeel.Deployment.HostingCostTest do
  use ControlKeel.DataCase

  alias ControlKeel.Deployment.HostingCost

  test "estimate returns costs for all platforms sorted by total" do
    assert {:ok, estimates} = HostingCost.estimate()
    assert length(estimates) == 9

    costs = Enum.map(estimates, & &1.total_monthly_cents)
    assert costs == Enum.sort(costs)
  end

  test "estimate with database requirement includes db costs" do
    {:ok, no_db} = HostingCost.estimate(needs_db: false)
    {:ok, with_db} = HostingCost.estimate(needs_db: true, db_tier: :managed_small)

    no_db_map = Map.new(no_db, &{&1.id, &1})
    with_db_map = Map.new(with_db, &{&1.id, &1})

    for id <- [:fly_io, :render, :heroku] do
      assert with_db_map[id].total_monthly_cents >= no_db_map[id].total_monthly_cents
    end
  end

  test "estimate respects stack fit" do
    {:ok, estimates} = HostingCost.estimate(stack: :phoenix)

    fly = Enum.find(estimates, &(&1.id == :fly_io))
    assert fly.fits_stack == true

    netlify = Enum.find(estimates, &(&1.id == :netlify))
    assert netlify.fits_stack == false
  end

  test "estimate includes breakdown" do
    {:ok, estimates} = HostingCost.estimate(stack: :phoenix, needs_db: true)

    for e <- estimates do
      assert is_map(e.breakdown)
      assert is_integer(e.breakdown.compute)
      assert is_integer(e.breakdown.database)
      assert is_integer(e.breakdown.bandwidth)
      assert is_integer(e.breakdown.storage)
    end
  end

  test "estimate with high bandwidth charges extra" do
    {:ok, low_bw} = HostingCost.estimate(expected_bandwidth_gb: 10)
    {:ok, high_bw} = HostingCost.estimate(expected_bandwidth_gb: 500)

    low_bw_map = Map.new(low_bw, &{&1.id, &1})
    high_bw_map = Map.new(high_bw, &{&1.id, &1})

    assert high_bw_map[:netlify].total_monthly_cents > low_bw_map[:netlify].total_monthly_cents
  end

  test "available_platforms returns all platforms" do
    platforms = HostingCost.available_platforms()
    assert length(platforms) == 9
    assert Enum.all?(platforms, &(&1.id != nil))
  end

  test "available_tiers returns tier definitions" do
    tiers = HostingCost.available_tiers()
    assert Map.has_key?(tiers, :free)
    assert Map.has_key?(tiers, :performance)
  end

  test "available_database_tiers returns database tiers" do
    tiers = HostingCost.available_database_tiers()
    assert Map.has_key?(tiers, :none)
    assert Map.has_key?(tiers, :managed_large)
  end

  test "Heroku has unlimited bandwidth" do
    {:ok, estimates} = HostingCost.estimate(expected_bandwidth_gb: 10_000)
    heroku = Enum.find(estimates, &(&1.id == :heroku))
    assert heroku.breakdown.bandwidth == 0
  end

  test "Vercel has no database or storage" do
    {:ok, estimates} = HostingCost.estimate(needs_db: true)
    vercel = Enum.find(estimates, &(&1.id == :vercel))
    assert vercel.breakdown.database == 0
    assert vercel.breakdown.storage == 0
  end
end
