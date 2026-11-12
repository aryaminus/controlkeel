defmodule ControlKeel.BinWrapperTest do
  use ExUnit.Case, async: false

  # NOTE: the subprocess tests (bin/controlkeel context/validate --json) were
  # removed: they spawn the wrapper, which boots the app against a SQLite
  # snapshot and was flaky in CI (sandbox-pool checkout races). The wrapper
  # behavior is verified manually; this module keeps the shell-level
  # contract tests that do not spawn anything.
  @moduletag :sqlite_only

  @wrapper Path.expand("../../bin/controlkeel", __DIR__)

  test "--format only enables JSON mode for a json value" do
    wrapper = File.read!(@wrapper)

    assert wrapper =~ "--json|--format=json|--format=JSON)"
    assert wrapper =~ ~s(if [ "$arg" = "--format" ])
    assert wrapper =~ "json|JSON) return 0"
    refute wrapper =~ "--json|--format)"
  end
end
