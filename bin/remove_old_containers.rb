#!/usr/bin/env ruby

class RemoveOldContainers

  def initialize
    require 'docker'
    require 'yaml'
    require 'mongoid'
    require_relative '../models/ip_forwarding'
    require_relative '../lib/docker_cont_state'
    require_relative '../lib/stagings_activity'
    require_relative '../lib/stagings_ttl'
    require_relative '../lib/port_forwarding'
    @work_dir      = File.expand_path($0).split('/bin/remove_old_containers.rb')[0]
    @config        = YAML.load_file("#{@work_dir}/config.yml")
    @containers_ttl = StagingsTtl.new(redis_host: @config['redis_host'],
                                      port: @config['redis_port'],
                                      redis_db: @config['redis_db'],
                                      container_ttl: @config['container_ttl'],
                                      container_max_ttl: @config['container_max_ttl'])
    Mongoid.load!("#{@work_dir}/mongoid.yml", :production)
  end

  def clean_old_containers
    docker = DockerContState.new
    stagings_activity = StagingsActivity.new(host: @config['redis_host'],
                                             port: @config['redis_port'],
                                             db: @config['redis_db'],
                                             redis_ttl: @config['redis_ttl'])
    Docker::Container.all.each do |container|
      if container.info['Names'][0].include?('-staging-')
        project = container.info['Names'][0].split('-staging-')[0].split('/')[1]
        db_name = container.info['Names'][0].split('-staging-')[1]
        if Time.now.to_i - container.info['Created'] > @containers_ttl.get_ttl_seconds(project, db_name)
          puts "Container #{container.info['Names']} has been run more than max ttl: #{@containers_ttl.get_ttl_seconds(project, db_name)}, removing"
          docker.remove_mysql_db(project, db_name)
          container.stop
          container.remove
          PortForwarding.rm_all_from_iptables(project, db_name)
          File.delete("/etc/nginx/conf.d/#{project}-staging-#{db_name}.conf")
          stagings_activity.add_action(project: project, branch: db_name, email: 'cron', type: 'remove')
        end
      end
    end
    Process.spawn('sudo /etc/init.d/nginx reload')
  end
end

container_cleaner = RemoveOldContainers.new
container_cleaner.clean_old_containers
