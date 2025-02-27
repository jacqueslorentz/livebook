defmodule LivebookProto.DeploymentGroup do
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :id, 1, type: :string
  field :name, 2, type: :string
  field :mode, 3, type: :string
  field :secrets, 4, repeated: true, type: LivebookProto.DeploymentGroupSecret
  field :clustering, 5, type: :string
  field :zta_provider, 6, type: :string, json_name: "ztaProvider"
  field :zta_key, 7, type: :string, json_name: "ztaKey"
  field :agent_keys, 8, repeated: true, type: LivebookProto.AgentKey, json_name: "agentKeys"

  field :deployed_apps, 9,
    repeated: true,
    type: LivebookProto.DeployedApp,
    json_name: "deployedApps"
end
