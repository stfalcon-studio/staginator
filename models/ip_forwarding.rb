class IpForwarding
  include Mongoid::Document
  store_in collection: "ip_forwarding"

  field :project_name,   type: String
  field :container_name, type: String
  field :container_port, type: Integer
  field :host_port,      type: Integer
  field :added_by,       type: String

  index 'container_name' => 1
  index 'project_name'   => 1
  index 'host_port'      => 1
end