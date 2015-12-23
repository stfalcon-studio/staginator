#!/usr/bin/env ruby
# usage: ./remove_project.rb gitlab_token project_name

class RemoveProject

  def initialize(opts)
    @opts = opts
    require 'yaml'
    require 'mongoid'
    require_relative '../models/ip_forwarding'
    require_relative '../lib/gitlab_api'
    require_relative '../lib/docker_cont_state'
    require_relative '../lib/terminal_security'
    require_relative '../lib/webhook_security'
    require_relative '../lib/port_forwarding'
    @work_dir       = File.expand_path($0).split('/bin/remove_project.rb')[0]
    @config         = YAML.load_file("#{@work_dir}/config.yml")
    Mongoid.load!("#{@work_dir}/mongoid.yml", :production)
  end

  def remove_webhook
    gitlab = GitlabApi.new( gitlab_host: @config['gitlab_host'],
                            gitlab_protocol: @config['gitlab_protocol'],
                            webhook_secret: @config['webhook_secret'],
                            webhook_domain: @config['webhook_domain'])
    project_id = gitlab.project_id_by_name(@opts[:gitlab_token], @opts[:project_name])
    gitlab.remove_webhook(@opts[:gitlab_token], project_id, @opts[:project_name])
  end

  def remove_all_containers
    docker = DockerContState.new
    docker.running_project_branches(@opts[:project_name]).each do |branch|
      pid = Process.spawn("sudo /usr/local/bin/remove_container.sh #{@opts[:project_name]} #{branch[:name]}")
      PortForwarding.rm_all_for_container(@opts[:project_name], branch[:name])
      Process.wait pid
    end
  end

  def remove_mysql
    pid = Process.spawn("/usr/local/bin/docker stop #{@opts[:project_name]}-mysql")
    Process.wait pid
    pid = Process.spawn("/usr/local/bin/docker rm #{@opts[:project_name]}-mysql")
    Process.wait pid
  end

  def remove_image
    pid = Process.spawn("/usr/local/bin/docker rmi #{@opts[:project_name]}-staging")
    Process.wait pid
  end

  def remove_phpmyadmin_conf
    pid = Process.spawn("rm /etc/phpmyadmin/conf.d/#{@opts[:project_name]}.php")
    Process.wait pid
  end
end

rm =  RemoveProject.new(gitlab_token: ARGV[0], project_name: ARGV[1])

rm.remove_webhook
rm.remove_all_containers
rm.remove_mysql
rm.remove_image
rm.remove_phpmyadmin_conf