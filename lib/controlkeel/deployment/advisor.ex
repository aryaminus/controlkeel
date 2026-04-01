defmodule ControlKeel.Deployment.Advisor do
  @moduledoc false

  @platforms [
    %{
      id: :fly_io,
      name: "Fly.io",
      url: "https://fly.io",
      docs: "https://fly.io/docs",
      stack_fit: [:phoenix, :rails, :node, :python, :static],
      tier: %{name: "Free", monthly_low: 0, monthly_high: 0},
      notes: "Best for Phoenix/Elixir apps. Native IPv6, free tier available."
    },
    %{
      id: :railway,
      name: "Railway",
      url: "https://railway.app",
      docs: "https://docs.railway.app",
      stack_fit: [:phoenix, :rails, :node, :python, :react],
      tier: %{name: "Hobby", monthly_low: 0, monthly_high: 5},
      notes: "Easy deploy from CLI. Good for rapid prototyping."
    },
    %{
      id: :render,
      name: "Render",
      url: "https://render.com",
      docs: "https://render.com/docs",
      stack_fit: [:phoenix, :rails, :node, :python, :react, :static],
      tier: %{name: "Free", monthly_low: 0, monthly_high: 0},
      notes: "Free tier for static sites. Good for Phoenix, React, and Node apps."
    },
    %{
      id: :vercel,
      name: "Vercel",
      url: "https://vercel.com",
      docs: "https://vercel.com/docs",
      stack_fit: [:react, :static],
      tier: %{name: "Hobby", monthly_low: 0, monthly_high: 0},
      notes: "Best for Next.js/React frontend apps. Serverless functions."
    },
    %{
      id: :heroku,
      name: "Heroku",
      url: "https://heroku.com",
      docs: "https://devcenter.heroku.com",
      stack_fit: [:phoenix, :rails, :node, :python],
      tier: %{name: "Eco", monthly_low: 7, monthly_high: 7},
      notes: "Good for Rails/Phoenix apps. Has eco dyno tier."
    },
    %{
      id: :aws,
      name: "AWS (Elastic Beanstalk)",
      url: "https://aws.amazon.com/elasticbeanstalk",
      docs: "https://docs.aws.amazon.com/elasticbeanstalk",
      stack_fit: [:phoenix, :rails, :node, :python, :react, :static],
      tier: %{name: "Free Tier", monthly_low: 0, monthly_high: 0},
      notes: "Most features. Free tier includes 750 hours EC2 per month."
    },
    %{
      id: :gcp,
      name: "Google Cloud Run",
      url: "https://cloud.google.com/run",
      docs: "https://cloud.google.com/run/docs",
      stack_fit: [:phoenix, :rails, :node, :python, :react, :static],
      tier: %{name: "Free Tier", monthly_low: 0, monthly_high: 0},
      notes: "Serverless containers. Good for any stack. Generous free tier."
    },
    %{
      id: :digitalocean,
      name: "DigitalOcean App Platform",
      url: "https://www.digitalocean.com/products/app-platform",
      docs: "https://docs.digitalocean.com/products/app-platform",
      stack_fit: [:phoenix, :rails, :node, :python, :react, :static],
      tier: %{name: "Basic", monthly_low: 5, monthly_high: 5},
      notes: "Good for small apps. Simple pricing."
    },
    %{
      id: :netlify,
      name: "Netlify",
      url: "https://www.netlify.com",
      docs: "https://docs.netlify.com",
      stack_fit: [:static, :react],
      tier: %{name: "Starter", monthly_low: 0, monthly_high: 0},
      notes: "Best for static sites and JAMstack. Free tier."
    }
  ]

  def analyze(project_root) do
    root = Path.expand(project_root)
    files = list_project_files(root)
    stack = detect_stack(root, files)
    platforms = filter_platforms(stack)
    cost_range = estimate_monthly_cost(stack)

    generators = [
      %{
        name: "Dockerfile",
        filename: "Dockerfile",
        content: dockerfile(stack, root)
      },
      %{
        name: "docker-compose.yml",
        filename: "docker-compose.yml",
        content: docker_compose(stack, root)
      },
      %{
        name: "CI Pipeline",
        filename: ".github/workflows/ci.yml",
        content: ci_pipeline(stack)
      },
      %{
        name: "Environment Template",
        filename: ".env.example",
        content: env_template(stack, root)
      }
    ]

    {:ok,
     %{
       stack: stack,
       platforms: platforms,
       monthly_cost_range: cost_range,
       generators: generators
     }}
  end

  def generate_files(project_root, generators, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    overwrite = Keyword.get(opts, :overwrite, false)

    results =
      Enum.map(generators, fn gen ->
        path = Path.join(project_root, gen.filename)
        content = String.trim(gen.content || "")

        if dry_run do
          {:ok, gen.name, path, content, :skipped}
        else
          dir = Path.dirname(path)
          File.mkdir_p!(dir)

          if File.exists?(path) and not overwrite do
            {:ok, gen.name, path, content, :skipped}
          else
            File.write(path, content)
            {:ok, gen.name, path, content, :written}
          end
        end
      end)

    {:ok, results}
  end

  defp list_project_files(root) do
    extensions =
      ~w(.ex .exs .json .yml .yaml .toml .lock .conf .rb .py .js .ts .tsx .jsx .rs .go .mod .html .heex .eex .sh .bash .zsh .fish .ps1 .gemfile .dockerignore .env.local .env.example)

    root_files =
      extensions
      |> Enum.flat_map(fn ext ->
        root
        |> Path.join("**#{ext}")
        |> Path.wildcard()
      end)

    config_files =
      ~w(mix.exs config/config.exs config/dev.exs config/prod.exs config/test.exs)
      |> Enum.map(&Path.join(root, &1))
      |> Enum.filter(&File.exists?/1)

    root_files ++ config_files
  end

  defp detect_stack(root, files) do
    has_mix = Enum.any?(files, &String.ends_with?(&1, "/mix.exs"))

    has_phoenix =
      Enum.any?(files, &String.contains?(&1, "phoenix")) or
        file_contains?(root, "mix.exs", "phoenix")

    has_pkg = Enum.any?(files, &String.ends_with?(&1, "/package.json"))
    has_react_dep = file_contains?(root, "package.json", "react")

    has_gemfile =
      Enum.any?(files, &String.ends_with?(&1, "/Gemfile")) or
        File.exists?(Path.join(root, "Gemfile"))

    has_requirements =
      Enum.any?(files, &String.ends_with?(&1, "/requirements.txt")) or
        File.exists?(Path.join(root, "requirements.txt"))

    has_flask =
      file_contains?(root, "requirements.txt", "Flask") ||
        file_contains?(root, "requirements.txt", "flask")

    has_django =
      file_contains?(root, "requirements.txt", "Django") ||
        file_contains?(root, "requirements.txt", "django")

    cond do
      has_mix and has_phoenix -> :phoenix
      has_pkg and has_react_dep -> :react
      has_gemfile -> :rails
      has_pkg -> :node
      has_requirements and (has_flask or has_django) -> :python
      true -> :static
    end
  end

  defp file_contains?(root, filename, pattern) do
    path = Path.join(root, filename)

    case File.read(path) do
      {:ok, content} -> String.contains?(content, pattern)
      {:error, _} -> false
    end
  end

  defp filter_platforms(stack) do
    Enum.filter(@platforms, fn p -> stack in p.stack_fit end)
    |> Enum.sort_by(fn p ->
      cond do
        stack == :phoenix and p.id == :fly_io -> 0
        stack == :react and p.id == :vercel -> 0
        stack == :static and p.id == :netlify -> 0
        true -> 1
      end
    end)
  end

  defp estimate_monthly_cost(stack) do
    case stack do
      :phoenix -> %{low: 0, high: 50, currency: "USD"}
      :react -> %{low: 0, high: 20, currency: "USD"}
      :rails -> %{low: 7, high: 50, currency: "USD"}
      :node -> %{low: 0, high: 20, currency: "USD"}
      :python -> %{low: 0, high: 25, currency: "USD"}
      :static -> %{low: 0, high: 0, currency: "USD"}
    end
  end

  defp dockerfile(:phoenix, root), do: phoenix_dockerfile(root)
  defp dockerfile(:react, _root), do: react_dockerfile()
  defp dockerfile(:rails, _root), do: rails_dockerfile()
  defp dockerfile(:node, _root), do: node_dockerfile()
  defp dockerfile(:python, _root), do: python_dockerfile()
  defp dockerfile(:static, _root), do: static_dockerfile()

  defp docker_compose(:phoenix, root), do: phoenix_docker_compose(root)
  defp docker_compose(:react, _root), do: react_docker_compose()
  defp docker_compose(:rails, _root), do: rails_docker_compose()
  defp docker_compose(:node, _root), do: node_docker_compose()
  defp docker_compose(:python, _root), do: python_docker_compose()
  defp docker_compose(:static, _root), do: static_docker_compose()

  defp ci_pipeline(:phoenix), do: phoenix_ci()
  defp ci_pipeline(:react), do: react_ci()
  defp ci_pipeline(:rails), do: rails_ci()
  defp ci_pipeline(:node), do: node_ci()
  defp ci_pipeline(:python), do: python_ci()
  defp ci_pipeline(:static), do: static_ci()

  defp env_template(:phoenix, root), do: phoenix_env(root)
  defp env_template(:react, _root), do: react_env()
  defp env_template(:rails, _root), do: rails_env()
  defp env_template(:node, _root), do: node_env()
  defp env_template(:python, _root), do: python_env()
  defp env_template(:static, _root), do: static_env()

  defp app_name(root), do: root |> Path.basename() |> String.replace("-", "_")

  defp otp_version(root) do
    case File.read(Path.join(root, ".tool-versions")) do
      {:ok, content} ->
        case Regex.run(~r/erlang\s+(\d+)/, content) do
          [_, ver] -> ver
          _ -> "27"
        end

      {:error, _} ->
        "27"
    end
  end

  defp phoenix_dockerfile(root) do
    name = app_name(root)
    otp = otp_version(root)

    """
    # Generated by ControlKeel Deployment Advisor
    # ---- Build Stage ----
    FROM hexpm/elixir:#{otp}-erlang-#{otp}-alpine-3.20.1 AS build
    RUN apk add --no-cache build-base git python3
    WORKDIR /app
    RUN mix local.hex --force && mix local.rebar --force
    ENV MIX_ENV=prod
    COPY mix.exs mix.lock ./
    RUN mix deps.get --only prod
    RUN mkdir config
    COPY config/config.exs config/prod.exs config/
    RUN mix deps.compile
    COPY lib lib
    COPY priv priv
    RUN mix compile
    COPY config/runtime.exs config/
    RUN mix release

    # ---- Runtime Stage ----
    FROM alpine:3.20.1 AS app
    RUN apk add --no-cache libstdc++ openssl ncurses-libs
    WORKDIR /app
    RUN chown nobody /app
    ENV MIX_ENV=prod
    COPY --from=build --chown=nobody:root /app/_build/prod/#{name}_release.tar.gz .
    RUN tar xzf #{name}_release.tar.gz -C .
    RUN rm #{name}_release.tar.gz
    USER nobody
    ENV PHX_SERVER=true
    CMD ["/app/bin/#{name}", "start"]
    """
  end

  defp phoenix_docker_compose(root) do
    name = app_name(root)

    """
    # Generated by ControlKeel Deployment Advisor
    services:
      app:
        build: .
        ports:
          - "4000:4000"
        environment:
          DATABASE_URL: ${DATABASE_URL}
          SECRET_KEY_BASE: ${SECRET_KEY_BASE}
          PHX_HOST: ${PHX_HOST:-localhost}
        depends_on:
          db:
            condition: service_healthy
        restart: unless-stopped
      db:
        image: postgres:16-alpine
        environment:
          POSTGRES_USER: ${POSTGRES_USER:-postgres}
          POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
          POSTGRES_DB: #{name}_dev
        ports:
          - "5432:5432"
        volumes:
          - db-data:/var/lib/postgresql/data
        restart: unless-stopped
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U postgres"]
          interval: 5s
          timeout: 5s
          retries: 5
    volumes:
      db-data:
    """
  end

  defp phoenix_ci do
    """
    # Generated by ControlKeel Deployment Advisor
    name: CI
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
    jobs:
      test:
        runs-on: ubuntu-latest
        services:
          postgres:
            image: postgres:16-alpine
            env:
              POSTGRES_USER: postgres
              POSTGRES_PASSWORD: postgres
              POSTGRES_DB: app_test
            ports:
              - 5432:5432
            options: >-
              --health-cmd pg_isready
              --health-interval 10s
              --health-timeout 5s
              --health-retries 5
        steps:
          - uses: actions/checkout@v6
          - uses: erlef/setup-beam@v1.23.0
            with:
              elixir-version: "1.19.5"
              otp-version: "27.3.4.3"
          - name: Install dependencies
            run: mix deps.get
          - name: Compile
            run: mix compile --warnings-as-errors
          - name: Check formatting
            run: mix format --check-formatted
          - name: Run tests
            run: mix test
            env:
              MIX_ENV: test
              DATABASE_URL: "postgres://postgres:postgres@localhost/app_test"
    """
  end

  defp phoenix_env(root) do
    name = app_name(root)

    """
    # Generated by ControlKeel Deployment Advisor
    # IMPORTANT: Never commit real secrets. Use .env for local, platform secrets for prod.

    # Application
    APP_NAME=#{name}
    PHX_HOST=localhost
    PORT=4000
    SECRET_KEY_BASE=CHANGE_ME_GENERATE_WITH_mix_phx.gen.secret

    # Database
    DATABASE_URL=postgres://postgres:postgres@localhost/#{name}_dev
    POOL_SIZE=10
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=postgres
    POSTGRES_DB=#{name}_dev
    POSTGRES_HOST=db
    POSTGRES_PORT=5432
    """
  end

  defp react_dockerfile do
    """
    # Generated by ControlKeel Deployment Advisor
    FROM node:20-alpine AS build
    WORKDIR /app
    COPY package*.json ./
    RUN npm ci
    COPY . .
    RUN npm run build

    FROM node:20-alpine AS runtime
    WORKDIR /app
    COPY --from=build /app/.next/standalone ./
    COPY --from=build /app/.next/static ./.next/static
    COPY --from=build /app/public ./public
    ENV NODE_ENV=production
    ENV PORT=3000
    EXPOSE 3000
    CMD ["node", "server.js"]
    """
  end

  defp react_docker_compose do
    """
    # Generated by ControlKeel Deployment Advisor
    services:
      app:
        build: .
        ports:
          - "3000:3000"
        environment:
          DATABASE_URL: ${DATABASE_URL}
          NEXT_PUBLIC_API_URL: ${NEXT_PUBLIC_API_URL}
        restart: unless-stopped
    """
  end

  defp react_ci do
    """
    # Generated by ControlKeel Deployment Advisor
    name: CI
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
    jobs:
      test:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-node@v4
            with:
              node-version: 20
              cache: npm
          - run: npm ci
          - run: npm run lint
          - run: npm run build
          - run: npm test
    """
  end

  defp react_env do
    """
    # Generated by ControlKeel Deployment Advisor
    # IMPORTANT: Never commit real secrets.

    # Application
    NEXT_PUBLIC_API_URL=http://localhost:3000/api
    DATABASE_URL=change_me
    NEXTAUTH_SECRET=change_me
    """
  end

  defp rails_dockerfile do
    """
    # Generated by ControlKeel Deployment Advisor
    FROM ruby:3.3-alpine AS build
    RUN apk add --no-cache build-base postgresql-dev tzdata
    WORKDIR /app
    COPY Gemfile Gemfile.lock ./
    RUN bundle config set --local deployment true
    RUN bundle install --jobs 4
    COPY . .
    RUN bundle exec rake assets:precompile

    FROM ruby:3.3-alpine AS runtime
    RUN apk add --no-cache postgresql-client tzdata
    WORKDIR /app
    COPY --from=build /app .
    ENV RAILS_ENV=production
    ENV RACK_ENV=production
    EXPOSE 3000
    CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
    """
  end

  defp rails_docker_compose do
    """
    # Generated by ControlKeel Deployment Advisor
    services:
      app:
        build: .
        ports:
          - "3000:3000"
        environment:
          DATABASE_URL: ${DATABASE_URL}
          RAILS_ENV: ${RAILS_ENV:-production}
          SECRET_KEY_BASE: ${SECRET_KEY_BASE}
        depends_on:
          db:
            condition: service_healthy
        restart: unless-stopped
      db:
        image: postgres:16-alpine
        environment:
          POSTGRES_USER: ${POSTGRES_USER:-postgres}
          POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
          POSTGRES_DB: app_development
        ports:
          - "5432:5432"
        volumes:
          - db-data:/var/lib/postgresql/data
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U postgres"]
          interval: 5s
          timeout: 5s
          retries: 5
    volumes:
      db-data:
    """
  end

  defp rails_ci do
    """
    # Generated by ControlKeel Deployment Advisor
    name: CI
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
    jobs:
      test:
        runs-on: ubuntu-latest
        services:
          postgres:
            image: postgres:16-alpine
            env:
              POSTGRES_USER: postgres
              POSTGRES_PASSWORD: postgres
              POSTGRES_DB: app_test
            ports:
              - 5432:5432
            options: >-
              --health-cmd pg_isready
              --health-interval 10s
              --health-timeout 5s
              --health-retries 5
        steps:
          - uses: actions/checkout@v4
          - uses: ruby/setup-ruby@v1
            with:
              ruby-version: "3.3"
              bundler-cache: true
          - run: bundle install
          - run: bundle exec rake test
          - run: bundle exec rubocop
    """
  end

  defp rails_env do
    """
    # Generated by ControlKeel Deployment Advisor
    # IMPORTANT: Never commit real secrets.

    RAILS_ENV=development
    DATABASE_URL=postgres://postgres:postgres@localhost:5432/app_development
    SECRET_KEY_BASE=change_me
    """
  end

  defp node_dockerfile do
    """
    # Generated by ControlKeel Deployment Advisor
    FROM node:20-alpine AS build
    WORKDIR /app
    COPY package*.json ./
    RUN npm ci --only=production
    COPY . .
    RUN npm run build

    FROM node:20-alpine AS runtime
    WORKDIR /app
    COPY --from=build /app .
    ENV NODE_ENV=production
    EXPOSE 3000
    CMD ["node", "server.js"]
    """
  end

  defp node_docker_compose do
    """
    # Generated by ControlKeel Deployment Advisor
    services:
      app:
        build: .
        ports:
          - "3000:3000"
        environment:
          NODE_ENV: production
          PORT: 3000
        restart: unless-stopped
    """
  end

  defp node_ci do
    """
    # Generated by ControlKeel Deployment Advisor
    name: CI
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
    jobs:
      test:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-node@v4
            with:
              node-version: 20
              cache: npm
          - run: npm ci
          - run: npm test
    """
  end

  defp node_env do
    """
    # Generated by ControlKeel Deployment Advisor
    # IMPORTANT: Never commit real secrets.

    PORT=3000
    NODE_ENV=development
    """
  end

  defp python_dockerfile do
    """
    # Generated by ControlKeel Deployment Advisor
    FROM python:3.12-slim AS build
    WORKDIR /app
    COPY requirements.txt .
    RUN pip install --no-cache-dir -r requirements.txt gunicorn
    COPY . .

    FROM python:3.12-slim AS runtime
    WORKDIR /app
    COPY --from=build /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
    COPY --from=build /app .
    EXPOSE 5000
    CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
    """
  end

  defp python_docker_compose do
    """
    # Generated by ControlKeel Deployment Advisor
    services:
      app:
        build: .
        ports:
          - "5000:5000"
        environment:
          DATABASE_URL: ${DATABASE_URL}
          FLASK_ENV: production
        restart: unless-stopped
    """
  end

  defp python_ci do
    """
    # Generated by ControlKeel Deployment Advisor
    name: CI
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
    jobs:
      test:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-python@v5
            with:
              python-version: "3.12"
              cache: pip
          - run: pip install -r requirements.txt
          - run: pytest
    """
  end

  defp python_env do
    """
    # Generated by ControlKeel Deployment Advisor
    # IMPORTANT: Never commit real secrets.

    FLASK_ENV=development
    DATABASE_URL=sqlite:///data/app.db
    SECRET_KEY=change_me
    """
  end

  defp static_dockerfile do
    """
    # Generated by ControlKeel Deployment Advisor
    FROM node:20-alpine AS build
    WORKDIR /app
    COPY package*.json ./
    RUN npm ci
    COPY . .
    RUN npm run build

    FROM nginx:alpine AS runtime
    COPY --from=build /app/dist /usr/share/nginx/html
    EXPOSE 80
    """
  end

  defp static_docker_compose do
    """
    # Generated by ControlKeel Deployment Advisor
    services:
      app:
        build: .
        ports:
          - "80:80"
        restart: unless-stopped
    """
  end

  defp static_ci do
    """
    # Generated by ControlKeel Deployment Advisor
    name: CI
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-node@v4
            with:
              node-version: 20
              cache: npm
          - run: npm ci
          - run: npm run build
    """
  end

  defp static_env do
    """
    # Generated by ControlKeel Deployment Advisor
    # No environment variables needed for static sites.
    """
  end

  def dns_ssl_guide(stack) do
    %{
      dns_setup: dns_steps(stack),
      ssl_setup: ssl_steps(stack),
      domain_registrars: [
        %{
          name: "Cloudflare Registrar",
          url: "https://www.cloudflare.com/products/registrar/",
          price: "at-cost pricing"
        },
        %{name: "Namecheap", url: "https://www.namecheap.com", price: "from $5.98/yr"},
        %{
          name: "Google Domains (Squarespace)",
          url: "https://domains.squarespace.com",
          price: "from $12/yr"
        }
      ],
      free_ssl: %{
        letsencrypt: "Free SSL via Let's Encrypt. Auto-renewed by most platforms.",
        cloudflare: "Free SSL via Cloudflare proxy. Set DNS to Cloudflare, enable orange cloud.",
        platform_provided:
          "Most hosting platforms (Render, Heroku, Fly.io, Railway, Vercel, Netlify) provide free SSL automatically."
      }
    }
  end

  defp dns_steps(:phoenix) do
    [
      "1. Buy a domain from a registrar (Cloudflare, Namecheap, etc.)",
      "2. Point DNS to your hosting platform (e.g., for Fly.io: add A record to your app's IP)",
      "3. Set PHX_HOST env var to your domain name",
      "4. Fly.io: run `fly certs add yourdomain.com` — SSL is automatic via Let's Encrypt",
      "5. Render/Heroku: add custom domain in dashboard — SSL is automatic",
      "6. Verify with: curl -I https://yourdomain.com"
    ]
  end

  defp dns_steps(:react) do
    [
      "1. Buy a domain from a registrar (Cloudflare, Namecheap, etc.)",
      "2. In Vercel/Netlify dashboard, go to Settings > Domains and add your domain",
      "3. Add the DNS records shown in the dashboard to your registrar's DNS settings",
      "4. SSL/HTTPS is configured automatically — no extra steps needed",
      "5. Verify with: curl -I https://yourdomain.com"
    ]
  end

  defp dns_steps(_) do
    [
      "1. Buy a domain from a registrar (Cloudflare, Namecheap, etc.)",
      "2. Add a CNAME record pointing to your hosting platform's URL, or an A record to its IP",
      "3. Most platforms (Render, Heroku, Fly.io, Railway) provide automatic SSL via Let's Encrypt",
      "4. Add the custom domain in your platform's dashboard",
      "5. Verify with: curl -I https://yourdomain.com"
    ]
  end

  defp ssl_steps(_stack) do
    [
      "Most modern hosting platforms provide free, automatic SSL certificates:",
      "- Fly.io: Automatic via Let's Encrypt when you add a custom domain",
      "- Render: Automatic HTTPS on all plans including free tier",
      "- Railway: Automatic HTTPS via Let's Encrypt",
      "- Heroku: Automatic SSL on all dynos",
      "- Vercel: Automatic HTTPS on all plans",
      "- Netlify: Automatic HTTPS on all plans",
      "- AWS/GCP: Use AWS Certificate Manager (free) or Google-managed certificates (free)",
      "",
      "For self-hosted: Use Certbot (Let's Encrypt) for free SSL certificates.",
      "Install: apt install certbot && certbot --nginx (or --apache)"
    ]
  end

  def db_migration_guide(stack) do
    %{
      stack: stack,
      steps: db_migration_steps(stack),
      rollback:
        "Always test migrations on a staging database first. Keep backups before running migrations in production.",
      backup_before:
        "Run: pg_dump -U postgres dbname > backup_$(date +%Y%m%d).sql before migrating."
    }
  end

  defp db_migration_steps(:phoenix) do
    [
      "Ecto migrations for Phoenix apps:",
      "",
      "# Generate a new migration:",
      "mix ecto.gen.migration add_your_table",
      "",
      "# Run migrations locally:",
      "mix ecto.migrate",
      "",
      "# Run migrations in production (on Fly.io):",
      "fly ssh console -C \"app/bin/your_app eval \\\"YourApp.Release.migrate()\\\"\"",
      "",
      "# Run migrations in production (generic):",
      "MIX_ENV=prod mix ecto.migrate",
      "",
      "# Rollback last migration:",
      "mix ecto.rollback --step 1"
    ]
  end

  defp db_migration_steps(:rails) do
    [
      "ActiveRecord migrations for Rails apps:",
      "",
      "# Generate a new migration:",
      "rails generate migration AddYourTable field:type",
      "",
      "# Run migrations locally:",
      "rails db:migrate",
      "",
      "# Run migrations in production:",
      "RAILS_ENV=production rails db:migrate",
      "",
      "# Rollback last migration:",
      "rails db:rollback"
    ]
  end

  defp db_migration_steps(:node) do
    [
      "Node.js database migrations (using Prisma, Drizzle, or Knex):",
      "",
      "# Prisma:",
      "npx prisma migrate dev --name your_migration",
      "npx prisma migrate deploy  # production",
      "",
      "# Drizzle:",
      "npx drizzle-kit generate",
      "npx drizzle-kit push  # production",
      "",
      "# Knex:",
      "npx knex migrate:make your_migration",
      "npx knex migrate:latest  # production"
    ]
  end

  defp db_migration_steps(:python) do
    [
      "Python database migrations (using Alembic for Flask/SQLAlchemy):",
      "",
      "# Generate a new migration:",
      "flask db migrate -m 'your description'",
      "",
      "# Run migrations:",
      "flask db upgrade",
      "",
      "# Rollback:",
      "flask db downgrade",
      "",
      "# Django:",
      "python manage.py makemigrations",
      "python manage.py migrate"
    ]
  end

  defp db_migration_steps(_) do
    ["Static sites typically don't need database migrations."]
  end

  def scaling_guide(stack) do
    %{
      stack: stack,
      vertical_scaling: vertical_scaling(stack),
      horizontal_scaling: horizontal_scaling(stack),
      database_scaling: database_scaling(stack),
      caching: caching_recommendations(stack),
      monitoring: monitoring_recommendations(stack),
      concurrent_users_guide: concurrent_users_breakdown()
    }
  end

  defp vertical_scaling(:phoenix) do
    %{
      description: "Increase VM size for the BEAM runtime",
      tiers: [
        %{users: "~100", tier: "1 vCPU, 1GB RAM", cost: "$5-10/mo"},
        %{users: "~1,000", tier: "2 vCPU, 4GB RAM", cost: "$25-50/mo"},
        %{users: "~10,000", tier: "4 vCPU, 8GB RAM", cost: "$85-170/mo"}
      ],
      note:
        "Elixir/BEAM is extremely efficient — a single 1GB instance can handle thousands of concurrent WebSocket connections."
    }
  end

  defp vertical_scaling(:react) do
    %{
      description: "React apps are typically served as static files or via serverless functions",
      tiers: [
        %{users: "~1,000", tier: "Vercel/Netlify free tier", cost: "$0/mo"},
        %{users: "~100,000", tier: "Vercel Pro or CDN", cost: "$20/mo"},
        %{users: "~1M+", tier: "Vercel Enterprise or CloudFront CDN", cost: "$40+/mo"}
      ],
      note: "React/Next.js apps benefit most from CDN caching. Server-side rendering costs more."
    }
  end

  defp vertical_scaling(_stack) do
    %{
      description: "Scale up the compute resources",
      tiers: [
        %{users: "~100", tier: "1 vCPU, 1GB RAM", cost: "$5-10/mo"},
        %{users: "~1,000", tier: "2 vCPU, 4GB RAM", cost: "$25-50/mo"},
        %{users: "~10,000", tier: "4+ vCPU, 8+GB RAM", cost: "$85+/mo"}
      ],
      note: "Start small and scale up based on actual traffic."
    }
  end

  defp horizontal_scaling(:phoenix) do
    "Phoenix scales horizontally naturally. Deploy 2+ instances behind a load balancer. Fly.io does this automatically with `fly scale count 2`. Use Phoenix PubSub with PostgreSQL adapter for cross-node messaging."
  end

  defp horizontal_scaling(:react) do
    "React static assets scale via CDN automatically (Vercel/Netlify/Cloudflare). For SSR, increase serverless function concurrency."
  end

  defp horizontal_scaling(:rails) do
    "Rails scales horizontally with multiple Puma workers. Use `WEB_CONCURRENCY` env var. Add a load balancer (Nginx, AWS ALB). Use SolidQueue or Sidekiq for background jobs."
  end

  defp horizontal_scaling(_) do
    "Most platforms support auto-scaling. Set min/max instance counts. Use a load balancer to distribute traffic. Consider container orchestration (Kubernetes, ECS) for >10k users."
  end

  defp database_scaling(:phoenix) do
    "Start with managed Postgres (Supabase, Neon, Render, Fly.io Postgres). For high traffic: add PgBouncer for connection pooling, read replicas for query offloading. Ecto supports connection pools natively via POOL_SIZE."
  end

  defp database_scaling(:rails) do
    "Start with managed Postgres (Supabase, Neon, Render). Add PgBouncer for connection pooling. Use ActiveRecord read replicas for query offloading. Consider SolidCache for Rails 7.1+."
  end

  defp database_scaling(_) do
    "Start with a managed database (Supabase free tier, Neon free tier, Render starter). Add connection pooling (PgBouncer) when approaching connection limits. Add read replicas for read-heavy workloads."
  end

  defp caching_recommendations(_stack) do
    [
      %{
        type: "Application-level",
        recommendation: "Cache expensive query results in memory (Elixir :ets, Redis, Memcached)"
      },
      %{
        type: "HTTP/CDN",
        recommendation: "Use Cloudflare (free tier) or platform CDN for static assets"
      },
      %{
        type: "Database",
        recommendation:
          "Add database-level query caching. Use EXPLAIN ANALYZE to find slow queries."
      },
      %{
        type: "API response",
        recommendation:
          "Set appropriate Cache-Control headers. Use ETags for conditional requests."
      }
    ]
  end

  defp monitoring_recommendations(_stack) do
    [
      %{
        type: "Uptime",
        tool: "UptimeRobot (free) or Pingdom",
        setup: "Monitor https://yourdomain.com/health every 1 minute"
      },
      %{
        type: "Errors",
        tool: "Sentry (free tier) or AppSignal (Elixir)",
        setup: "Add sentry package, set DSN env var"
      },
      %{
        type: "Performance",
        tool: "AppSignal (Elixir) or New Relic",
        setup: "Add agent, get APM dashboards"
      },
      %{
        type: "Logs",
        tool: "Platform built-in logs or Loki/ELK",
        setup: "Most platforms show logs in dashboard. For custom: use Logflare or Papertrail."
      },
      %{
        type: "Alerts",
        tool: "PagerDuty or Opsgenie",
        setup: "Connect uptime monitor to alert channel (Slack, email, SMS)"
      }
    ]
  end

  defp concurrent_users_breakdown do
    [
      %{users: "1-100", infrastructure: "Single instance, free tier database", cost: "$0-10/mo"},
      %{users: "100-1,000", infrastructure: "2 instances, managed DB, CDN", cost: "$20-50/mo"},
      %{
        users: "1,000-10,000",
        infrastructure: "4+ instances, read replicas, cache layer",
        cost: "$100-300/mo"
      },
      %{
        users: "10,000+",
        infrastructure: "Auto-scaling cluster, dedicated DB, multi-region",
        cost: "$300+/mo"
      }
    ]
  end
end
