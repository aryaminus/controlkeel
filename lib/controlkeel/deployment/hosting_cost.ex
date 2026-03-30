defmodule ControlKeel.Deployment.HostingCost do
  @moduledoc false

  @tiers %{
    free: %{cpu: 0.25, memory_gb: 0.5, disk_gb: 1, label: "Free"},
    hobby: %{cpu: 0.5, memory_gb: 1, disk_gb: 5, label: "Hobby"},
    standard_1x: %{cpu: 1, memory_gb: 2, disk_gb: 10, label: "Standard 1X"},
    standard_2x: %{cpu: 2, memory_gb: 4, disk_gb: 20, label: "Standard 2X"},
    performance: %{cpu: 4, memory_gb: 8, disk_gb: 50, label: "Performance"},
    dedicated: %{cpu: 8, memory_gb: 16, disk_gb: 100, label: "Dedicated"}
  }

  @database_tiers %{
    none: %{monthly_cents: 0, label: "None"},
    shared_small: %{monthly_cents: 0, label: "Shared Small"},
    managed_small: %{monthly_cents: 1500, label: "Managed Small (256MB)"},
    managed_medium: %{monthly_cents: 3000, label: "Managed Medium (1GB)"},
    managed_large: %{monthly_cents: 9000, label: "Managed Large (4GB)"},
    managed_xl: %{monthly_cents: 36000, label: "Managed XL (16GB)"}
  }

  @platforms %{
    fly_io: %{
      name: "Fly.io",
      url: "https://fly.io",
      compute: %{
        free: %{monthly_cents: 0, included_hours: 160},
        shared_cpu_1x: %{monthly_cents: 191, per_gb_memory: 114},
        dedicated_cpu_1x: %{monthly_cents: 870},
        dedicated_cpu_2x: %{monthly_cents: 1740}
      },
      database: %{
        shared_small: %{monthly_cents: 0},
        managed_small: %{monthly_cents: 1720},
        managed_medium: %{monthly_cents: 5200},
        managed_large: %{monthly_cents: 16800}
      },
      bandwidth: %{free_gb: 160, per_gb_cents: 2},
      persistent_storage: %{per_gb_cents: 3},
      best_for: [:phoenix, :rails],
      notes: "Free 160h/month shared-cpu-1x. Best for Elixir/Phoenix."
    },
    railway: %{
      name: "Railway",
      url: "https://railway.app",
      compute: %{
        free: %{monthly_cents: 500, included_credits: 500},
        hobby: %{monthly_cents: 500, per_vcpu_hour: 28, per_gb_hour: 7},
        standard: %{monthly_cents: 2000, per_vcpu_hour: 28, per_gb_hour: 7}
      },
      database: %{
        managed_small: %{monthly_cents: 100},
        managed_medium: %{monthly_cents: 500},
        managed_large: %{monthly_cents: 2500}
      },
      bandwidth: %{free_gb: 100, per_gb_cents: 10},
      persistent_storage: %{per_gb_cents: 2},
      best_for: [:phoenix, :rails, :node, :python, :react],
      notes: "Usage-based pricing. $5/mo hobby plan includes credits."
    },
    render: %{
      name: "Render",
      url: "https://render.com",
      compute: %{
        free: %{monthly_cents: 0, hours_limit: 750},
        starter: %{monthly_cents: 700},
        standard: %{monthly_cents: 2500},
        pro: %{monthly_cents: 8500}
      },
      database: %{
        starter: %{monthly_cents: 700, storage_gb: 1},
        standard: %{monthly_cents: 2000, storage_gb: 10},
        pro: %{monthly_cents: 6500, storage_gb: 50}
      },
      bandwidth: %{free_gb: 100, per_gb_cents: 10},
      persistent_storage: %{per_gb_cents: 2},
      best_for: [:phoenix, :rails, :node, :python, :react, :static],
      notes: "Free static sites. Starter at $7/mo for web services."
    },
    vercel: %{
      name: "Vercel",
      url: "https://vercel.com",
      compute: %{
        free: %{monthly_cents: 0, bandwidth_gb: 100, serverless_invocations: 100_000},
        pro: %{monthly_cents: 2000, bandwidth_gb: 1000, serverless_invocations: 1_000_000},
        enterprise: %{monthly_cents: 0, custom: true}
      },
      database: %{none: %{monthly_cents: 0}},
      bandwidth: %{free_gb: 100, per_gb_cents: 15},
      persistent_storage: nil,
      best_for: [:react, :static],
      notes: "Free for hobby. Best for Next.js/React. Serverless model."
    },
    heroku: %{
      name: "Heroku",
      url: "https://heroku.com",
      compute: %{
        eco: %{monthly_cents: 500},
        basic: %{monthly_cents: 700},
        standard_1x: %{monthly_cents: 2500},
        standard_2x: %{monthly_cents: 5000},
        performance_m: %{monthly_cents: 25000}
      },
      database: %{
        mini: %{monthly_cents: 500, storage_gb: 1},
        basic: %{monthly_cents: 900, storage_gb: 4},
        standard_0: %{monthly_cents: 7000, storage_gb: 10},
        standard_2: %{monthly_cents: 17500, storage_gb: 50}
      },
      bandwidth: %{free_gb: :unlimited, per_gb_cents: 0},
      persistent_storage: nil,
      best_for: [:phoenix, :rails, :node, :python],
      notes: "Eco dynos at $5/mo. Mini Postgres at $5/mo."
    },
    aws_eb: %{
      name: "AWS Elastic Beanstalk",
      url: "https://aws.amazon.com/elasticbeanstalk",
      compute: %{
        free_tier: %{monthly_cents: 0, hours: 750, instance: "t2.micro"},
        small: %{monthly_cents: 850, instance: "t3.small"},
        medium: %{monthly_cents: 3400, instance: "t3.medium"},
        large: %{monthly_cents: 6800, instance: "t3.large"}
      },
      database: %{
        free_tier: %{monthly_cents: 0, storage_gb: 20, hours: 750},
        small: %{monthly_cents: 1400, instance: "db.t3.micro"},
        medium: %{monthly_cents: 3200, instance: "db.t3.small"}
      },
      bandwidth: %{free_gb: 100, per_gb_cents: 9},
      persistent_storage: %{per_gb_cents: 1},
      best_for: [:phoenix, :rails, :node, :python, :react],
      notes: "Free tier: t2.micro 750h/mo + RDS micro 750h/mo + 5GB S3."
    },
    gcp_run: %{
      name: "Google Cloud Run",
      url: "https://cloud.google.com/run",
      compute: %{
        free_tier: %{monthly_cents: 0, vcpu_hours: 180_000, gb_memory_hours: 360_000},
        paygo: %{per_vcpu_hour: 7, per_gb_memory_hour: 1}
      },
      database: %{
        free_tier: %{monthly_cents: 0, instance: "db-f1-micro"},
        small: %{monthly_cents: 800, instance: "db-custom-1-3840"},
        medium: %{monthly_cents: 2700, instance: "db-custom-2-7680"}
      },
      bandwidth: %{free_gb: 200, per_gb_cents: 9},
      persistent_storage: %{per_gb_cents: 2},
      best_for: [:phoenix, :rails, :node, :python, :react, :static],
      notes: "Serverless containers. Pay per use. Generous free tier."
    },
    digitalocean: %{
      name: "DigitalOcean App Platform",
      url: "https://www.digitalocean.com/products/app-platform",
      compute: %{
        static: %{monthly_cents: 0},
        basic_512: %{monthly_cents: 500},
        basic_1gb: %{monthly_cents: 1000},
        pro_2gb: %{monthly_cents: 2000}
      },
      database: %{
        dev: %{monthly_cents: 700, storage_gb: 1},
        basic: %{monthly_cents: 1500, storage_gb: 10}
      },
      bandwidth: %{free_gb: 3, per_gb_cents: 10},
      persistent_storage: nil,
      best_for: [:phoenix, :rails, :node, :python, :react, :static],
      notes: "Free static sites. Basic starts at $5/mo. Simple pricing."
    },
    netlify: %{
      name: "Netlify",
      url: "https://www.netlify.com",
      compute: %{
        free: %{monthly_cents: 0, bandwidth_gb: 100, build_minutes: 300},
        pro: %{monthly_cents: 1900, bandwidth_gb: 1000, build_minutes: 25_000}
      },
      database: %{none: %{monthly_cents: 0}},
      bandwidth: %{free_gb: 100, per_gb_cents: 20},
      persistent_storage: nil,
      best_for: [:static, :react],
      notes: "Free for static sites. JAMstack specialist."
    }
  }

  def estimate(opts \\ []) do
    stack = Keyword.get(opts, :stack, :static)
    tier = Keyword.get(opts, :tier, :free)
    needs_db = Keyword.get(opts, :needs_db, false)
    db_tier = Keyword.get(opts, :db_tier, :managed_small)
    expected_bandwidth_gb = Keyword.get(opts, :expected_bandwidth_gb, 10)
    expected_storage_gb = Keyword.get(opts, :expected_storage_gb, 1)

    estimates =
      @platforms
      |> Enum.map(fn {id, platform} ->
        compute_cost = compute_monthly(platform, tier)
        db_cost = if needs_db, do: database_monthly(platform, db_tier), else: 0
        bandwidth_cost = bandwidth_monthly(platform, expected_bandwidth_gb)
        storage_cost = storage_monthly(platform, expected_storage_gb)

        total = compute_cost + db_cost + bandwidth_cost + storage_cost

        %{
          id: id,
          name: platform.name,
          url: platform.url,
          fits_stack: stack in platform.best_for,
          breakdown: %{
            compute: compute_cost,
            database: db_cost,
            bandwidth: bandwidth_cost,
            storage: storage_cost
          },
          total_monthly_cents: total,
          total_monthly_usd: total / 100,
          notes: platform.notes
        }
      end)
      |> Enum.sort_by(& &1.total_monthly_cents)

    {:ok, estimates}
  end

  def available_platforms do
    @platforms
    |> Enum.map(fn {id, p} ->
      %{id: id, name: p.name, url: p.url, best_for: p.best_for}
    end)
    |> Enum.sort_by(& &1.name)
  end

  def available_tiers do
    @tiers
  end

  def available_database_tiers do
    @database_tiers
  end

  defp compute_monthly(platform, tier) do
    tier_key = tier
    compute = platform.compute

    case Map.get(compute, tier_key) do
      nil ->
        compute
        |> Map.values()
        |> Enum.map(&Map.get(&1, :monthly_cents, 0))
        |> Enum.min()

      tier_data ->
        Map.get(tier_data, :monthly_cents, 0)
    end
  end

  defp database_monthly(platform, db_tier) do
    case Map.get(platform.database, db_tier) do
      nil ->
        platform.database
        |> Map.values()
        |> Enum.map(&Map.get(&1, :monthly_cents, 0))
        |> Enum.filter(&(&1 > 0))
        |> case do
          [] -> 0
          costs -> Enum.min(costs)
        end

      tier_data ->
        Map.get(tier_data, :monthly_cents, 0)
    end
  end

  defp bandwidth_monthly(platform, expected_gb) do
    case platform.bandwidth do
      %{free_gb: :unlimited} ->
        0

      %{free_gb: free, per_gb_cents: per_gb} ->
        billable = max(0, expected_gb - free)
        billable * per_gb

      _ ->
        0
    end
  end

  defp storage_monthly(platform, expected_gb) do
    case platform.persistent_storage do
      %{per_gb_cents: per_gb} -> expected_gb * per_gb
      _ -> 0
    end
  end
end
