defmodule Mix.Tasks.Ck.HostAudit do
  use Mix.Task

  alias ControlKeel.HostAudit

  @shortdoc "Checks public host/package/install surfaces for ecosystem drift"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    include_unverified? = Enum.member?(args, "--include-unverified")
    report = HostAudit.run(include_unverified: include_unverified?)

    Enum.each(HostAudit.render(report), fn line -> Mix.shell().info(line) end)

    if report.summary.error > 0 do
      Mix.raise("Host audit found failing public surfaces.")
    end
  end
end
