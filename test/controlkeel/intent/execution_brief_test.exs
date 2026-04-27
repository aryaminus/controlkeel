defmodule ControlKeel.Intent.ExecutionBriefTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Intent
  alias ControlKeel.Intent.ExecutionBrief

  import ControlKeel.IntentFixtures

  test "provider schema and changeset accept all supported domain packs" do
    supported = Intent.supported_packs()

    assert supported == [
             "software",
             "healthcare",
             "education",
             "finance",
             "hr",
             "legal",
             "marketing",
             "sales",
             "realestate",
             "government",
             "insurance",
             "ecommerce",
             "logistics",
             "manufacturing",
             "nonprofit",
             "security",
             "gdpr"
           ]

    schema_packs = get_in(ExecutionBrief.provider_schema(), ["properties", "domain_pack", "enum"])
    assert schema_packs == supported

    Enum.each(supported, fn pack ->
      attrs =
        provider_brief_payload(%{
          "occupation" => Intent.pack_label(pack),
          "domain_pack" => pack
        })

      metadata =
        compiler_metadata(%{
          "occupation" => pack,
          "domain_pack" => pack
        })

      assert {:ok, brief} = ExecutionBrief.from_provider_response(attrs, metadata)
      assert brief.domain_pack == pack
    end)
  end
end
