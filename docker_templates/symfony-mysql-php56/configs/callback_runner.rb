#!/usr/bin/env ruby

class CallbackRunner

  attr_reader :config

  def initialize(config_path)
    require 'yaml'
    require 'cocaine'
    @config = read_config(config_path)
  end

  def after_clone_repo
    deploy_callbacks('after_clone')
  end

  def before_composer_run
    deploy_callbacks('before_composer')
  end

  def after_composer_run
    deploy_callbacks('after_composer')
  end

  def after_deploy
    deploy_callbacks('after_deploy', '/stag/www')
  end

  def install_packages
    if @config['apt_packages']
      apt_update
      cmd = Cocaine::CommandLine.new("apt-get install -y #{@config['apt_packages'].join(' ')}")
      pid = Process.spawn(cmd.command)
      Process.wait(pid)
    end
  end

  def start_services
    if @config['run_services']
      @config['run_services'].each do |service|
        cmd = Cocaine::CommandLine.new("/etc/init.d/#{service} start")
        pid = Process.spawn(cmd.command)
        Process.wait(pid)
      end
    end
  end

  private

  def read_config(config_path)
    begin
      @config = YAML.load_file(config_path)
    end
  rescue Errno::ENOENT
    @config = false
  end

  def deploy_callbacks(step, pwd = '/stag/new')
    if @config['deploy_callbacks'][step]
      @config['deploy_callbacks'][step].each do |command|
        cmd = Cocaine::CommandLine.new("cd #{pwd} && #{command}")
        pid = Process.spawn(cmd.command)
        Process.wait(pid)
      end
    end
  end

  def apt_update
    pid = Process.spawn('apt-get update')
    Process.wait(pid)
  end

end

if __FILE__==$0
  runner = CallbackRunner.new(ARGV[0]) # ./callback_runner.rb /path/to/staginator.yml stage
  runner.send(ARGV[1]) if runner.config
end