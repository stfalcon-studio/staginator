class DockerContState

  def initialize(options = { :docker_host => 'unix:///var/run/docker.sock'})
    @docker_host = options[:docker_host]
    require 'docker'
  end

  def project_image_exist?(p_name)
    Docker::Image.all.each { |image| return true if image.info['RepoTags'][0].split(':')[0] == "#{p_name}-staging" }
    return false
  end

  def all_images
    project_images = []
    Docker::Image.all.each { |img| project_images << img.info['RepoTags'][0].split(':')[0]}
    project_images
  end

  def running_project_containers(p_name)
    containers = []
    Docker::Container.all.each do |cont|
      if cont.info['Names'][0].include?("#{p_name}-staging")
        container = {}
        container[:name] = cont.info['Names'][0].split('/')[1]
        container[:uptime] = cont.info['Status']
        containers << container
      end
    end
    containers # returns array with hash {:name=>"google-com-staging-cool-feature", :uptime=>"Up 17 hours"}
  end

  def running_project_branches(p_name)
    project_containers = running_project_containers(p_name)
    containers = []
    project_containers.each do |cont|
      container = {}
      container[:name]   = cont[:name].split('-staging-')[1]
      container[:uptime] = cont[:uptime]
      containers << container
    end
    containers # returns array with hash {:name=>"cool-feature", :uptime=>"Up 17 hours"}
  end

  def logs(p_name, branch)
    logs = []
    container = find_container(p_name, branch)
    container.streaming_logs(stdout: true) { |stream, chunk| logs << chunk }
    logs
  end

  def ip(p_name, branch)
    container = find_container(p_name, branch)
    container.json['NetworkSettings']['IPAddress']
  end

  def remove_mysql_db(project, branch)
    mysql_container = Docker::Container.all.each { |c| break c if c.info['Names'].include?("/#{project}-mysql")}
    db_name = Digest::MD5.hexdigest(branch)
    mysql_password = mysql_container.json['Config']['Env'].each { |env| break env.split('MYSQL_ROOT_PASSWORD=')[1] if env.include?('MYSQL_ROOT_PASSWORD') }
    command = ['bash', '-c', "mysql -u root -p#{mysql_password} -e 'DROP DATABASE `#{db_name}`;'"]
    mysql_container.exec(command, tty: true)
  end

  def mysql_container_password(project)
    mysql_container = Docker::Container.all.each { |c| break c if c.info['Names'].include?("/#{project}-mysql")}
    if mysql_container.class == Docker::Container
      if mysql_container.json['Config']['Env'].count == 1
        return nil
      end
      mysql_container.json['Config']['Env'].each { |env| break env.split('MYSQL_ROOT_PASSWORD=')[1] if env.include?('MYSQL_ROOT_PASSWORD') }
    else
      nil
    end
  end

  private

  def find_container(p_name, branch)
    container = nil
    Docker::Container.all.each { |c| container = c if c.info['Names'][0] == "/#{p_name}-staging-#{branch}" }
    if container == nil
      raise ContainerNotFound, 'Docker container not found for specified project and branch name!'
    else
      container
    end
  end

end

class ContainerNotFound < StandardError
  attr_reader :message

  def initialize(message)
    super
    @message = message
  end
end