class PortForwarding
  def initialize
    # unless @instance
    #   @session = session
    # end
    @instance ||= self
  end

  class << self

    def rm_all_for_container(project, container_name)
      rm_all(project, container_name, drop_mongo_record = true)
    end

    def rm_all_from_iptables(project, container_name)
      rm_all(project, container_name, drop_mongo_record = false)
    end

    def restore_iptables_rules(project, container_name, public_ip)
      ip_forwardings = find_mongo_records(project, container_name)
      if ip_forwardings.count > 0
        require_relative 'docker_cont_state'
        docker = DockerContState.new
        ip_forwardings.each do |ip_forwarding|
          container_ip = docker.ip(ip_forwarding.project_name, ip_forwarding.container_name)
          add_to_iptables(ip_forwarding.container_port, ip_forwarding.host_port, container_ip, public_ip)
        end
      end
    end

    def add_to_iptables(src_port, dst_port, container_ip, public_ip)
      Process.spawn("sudo /sbin/iptables -t nat -A PREROUTING -p tcp -m tcp --dport #{dst_port.to_i} -j DNAT --to-destination #{container_ip}:#{src_port}")
    end

    def rm_from_iptables(dst_port)
      rule_number = rule_number_by_port(dst_port)
      Process.spawn("sudo /sbin/iptables -t nat -D PREROUTING #{rule_number}")
    end

    def random_tcp_port(public_ip)
      min_tcp_port = 10001
      max_tcp_port = 16000
      rnd = Random.new
      while true
        port = rnd.rand(min_tcp_port..max_tcp_port)
        if check_tcp_port(public_ip, port) == 'free'
          return port
        end
      end
    end

    def check_tcp_port(public_ip, port_number)
      require 'mongoid'
      require_relative '../models/ip_forwarding'

      begin
        if IpForwarding.find_by(host_port: port_number)
          return 'busy'
        end
      rescue Mongoid::Errors::DocumentNotFound
      end

      if port_number.to_i < 10000
        return 'busy'
      end
      socket = Socket.new(:INET, :STREAM, 0)
      begin
        if socket.bind(Addrinfo.tcp(public_ip, port_number.to_i))
          socket.close
          return 'free'
        end
      rescue Errno::EADDRINUSE
        return 'busy'
      end
    end

    def rule_number_by_port(dst_port)
      index = iptables_rules.index{|r| r.include?("dpt:#{dst_port}")}
      if index == nil
        raise IptablesRuleNotFound, 'Iptables rule not found'
      end
      index + 1
    end
    def iptables_rules
      pipe_cmd_in, pipe_cmd_out = IO.pipe
      pid = Process.spawn('sudo /sbin/iptables -t nat -L PREROUTING', :out => pipe_cmd_out)
      Process.wait(pid)
      pipe_cmd_out.close
      out = pipe_cmd_in.read.split("\n")
      2.times { out.delete_at(0) }
      out
    end

    private

    def rm_all(project, container_name, drop_mongo_record = false)
      ip_forwardings = find_mongo_records(project, container_name)
      if ip_forwardings.count > 0
        ip_forwardings.each do |ip_forwarding|
          begin
            rule_number_by_port(ip_forwarding.host_port)
            rm_from_iptables(ip_forwarding.host_port)
            ip_forwarding.delete if drop_mongo_record
          rescue IptablesRuleNotFound
            nil
          end
        end
      end
    end

    def find_mongo_records(project, container_name)
      require 'mongoid'
      require_relative '../models/ip_forwarding'
      IpForwarding.where(project_name: project, container_name: container_name)
    end
  end

end

class IptablesRuleNotFound < StandardError
  attr_reader :message

  def initialize(message)
    super
    @message = message
  end
end