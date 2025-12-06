defmodule NsaiGatewayTest do
  use ExUnit.Case
  doctest NsaiGateway

  test "returns version" do
    version = NsaiGateway.version()
    assert is_binary(version)
    assert version == "0.1.0"
  end
end
