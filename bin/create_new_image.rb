#!/usr/bin/env ruby
# usage: ./create_new_image.rb gitlab_token template_name project_name notify_to@email.com

class CreateNewImage

  def initialize(opts)
    require 'socket'
    require 'securerandom'
    require 'fileutils'
    require 'pony'
    require 'sshkey'
    require 'yaml'
    require 'erb'
    require_relative '../lib/gitlab_api'
    @mysql_tcp_port = free_tcp_port
    @mysql_password = generate_password(12)
    @task_identify  = generate_password(6)
    @ssh_key        = generate_ssh_key
    @work_dir       = File.expand_path($0).split('/bin/create_new_image.rb')[0]
    @config         = YAML.load_file("#{@work_dir}/config.yml")
    @template_name  = opts[:template_name]
    @gitlab_token   = opts[:gitlab_token]
    @project_name   = opts[:project_name]
    @repo_url       = "git@#{@config['gitlab_host']}:#{@project_name}.git"
    @notify_email   = opts[:notify_email]
  end

  def run_mysql_container
    Process.spawn("/usr/local/bin/docker run -d --name #{@project_name}-mysql -p 127.0.0.1:#{@mysql_tcp_port}:3306 -e MYSQL_ROOT_PASSWORD=#{@mysql_password} mysql-server")
  end

  def run_mongodb_container
    Process.spawn("/usr/local/bin/docker run -d --name #{@project_name}-mysql -p 127.0.0.1:#{@mysql_tcp_port}:27017 mongodb")
  end

  def build_project_image
    copy_template_to_tmp
    render_update_script
    unless @template_name == 'angular' or @template_name == 'generic-mongodb-php56'
      render_mysql_password_script
      render_phpmyadmin_config
    end
    save_ssh_key
    gitlab = GitlabApi.new(gitlab_protocol: @config['gitlab_protocol'], gitlab_host: @config['gitlab_host'])
    project_id = gitlab.project_id_by_name(@gitlab_token, @project_name)
    gitlab.add_deploy_key(@gitlab_token, project_id, @ssh_key.ssh_public_key)
    pid = Process.spawn("cd /tmp/staging-#{@task_identify} && /usr/local/bin/docker build -t #{@project_name}-staging .")
    Process.wait(pid)
    clean_tmp
  end

  def send_info
    Pony.mail(:to        => @notify_email,
              :from      => "noreply@#{@config['app_hostname']}",
              :subject   => "Stagings group is ready for #{@project_name}",
              :html_body => "Your project is ready. For now you can run some containers in staginator.<br>Staginator url: <a href='http://#{@config['app_hostname']}/project/#{@project_name}'>http://#{@config['app_hostname']}/project/#{@project_name}</a>")
  end

  private

  def free_tcp_port
    socket = Socket.new(:INET, :STREAM, 0)
    socket.bind(Addrinfo.tcp('127.0.0.1', 0))
    free_port = socket.local_address.ip_port
    socket.close
    free_port
  end

  def generate_password(length)
    SecureRandom.hex(length)
  end

  def copy_template_to_tmp
    FileUtils.cp_r("#{@work_dir}/docker_templates/#{@template_name}/", "/tmp/staging-#{@task_identify}")
  end

  def clean_tmp
    FileUtils.rm_r("/tmp/staging-#{@task_identify}")
  end

  def render_update_script
    script = ERB.new(File.read("/tmp/staging-#{@task_identify}/update.erb"), 0, '-').result(binding)
    File.open("/tmp/staging-#{@task_identify}/configs/update.sh", 'w') { |f| f.write(script) }
  end

  def render_mysql_password_script
    script = ERB.new(File.read("/tmp/staging-#{@task_identify}/mysql_password.erb"), 0, '-').result(binding)
    File.open("/tmp/staging-#{@task_identify}/configs/mysql_password", 'w') { |f| f.write(script) }
  end

  def render_phpmyadmin_config
    config = ERB.new(File.read("/tmp/staging-#{@task_identify}/phpmyadmin.erb"), 0, '-').result(binding)
    File.open("/etc/phpmyadmin/conf.d/#{@project_name}.php", 'w') { |f| f.write(config) }
  end

  def generate_ssh_key
    SSHKey.generate(type: 'DSA', bits: 1024, comment: 'staginator@docker')
  end

  def save_ssh_key
    File.open("/tmp/staging-#{@task_identify}/ssh/id_dsa", 'w') { |f| f.write(@ssh_key.private_key) }
    File.open("/tmp/staging-#{@task_identify}/ssh/id_dsa.pub", 'w') { |f| f.write(@ssh_key.ssh_public_key) }
  end

end

staging_set =  CreateNewImage.new(gitlab_token: ARGV[0],
                                  template_name: ARGV[1],
                                  project_name: ARGV[2],
                                  notify_email: ARGV[3])

unless ARGV[1] == 'angular' or ARGV[1] == 'generic-mongodb-php56'
  staging_set.run_mysql_container
end
if ARGV[1] == 'generic-mongodb-php56'
  staging_set.run_mongodb_container
end
staging_set.build_project_image
staging_set.send_info