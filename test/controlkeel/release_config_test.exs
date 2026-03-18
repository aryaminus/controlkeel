defmodule ControlKeel.ReleaseConfigTest do
  use ExUnit.Case, async: true

  test "project release config includes burrito targets" do
    release = Mix.Project.config()[:releases][:controlkeel]

    assert release[:burrito][:targets] == [
             macos: [os: :darwin, cpu: :x86_64],
             macos_silicon: [os: :darwin, cpu: :aarch64],
             linux: [os: :linux, cpu: :x86_64],
             windows: [os: :windows, cpu: :x86_64]
           ]
  end
end
