#!/usr/bin/env ruby

require 'sinatra'
require 'sinatra/config_file'
require 'json'
require 'cocaine'
require 'rack-flash'
require 'digest'
require 'socket'
require 'require_all'
require 'mongoid'
require_all 'models'
require_relative 'lib/gitlab_api'
require_relative 'lib/docker_cont_state'
require_relative 'lib/staginator'
require_relative 'lib/terminal_security'
require_relative 'lib/webhook_security'
require_relative 'lib/stagings_activity'
require_relative 'lib/stagings_ttl'
require_relative 'lib/api_limit'
require_relative 'lib/port_forwarding'

config_file 'config.yml'

configure do
  enable :sessions
  use Rack::Flash
  Mongoid.load!('./mongoid.yml')
  if settings.environment == :production
    Mongoid.logger.level = Logger::ERROR
    Mongo::Logger.logger.level = Logger::ERROR
  end
end

gitlab = GitlabApi.new( gitlab_host: settings.gitlab_host,
                        gitlab_protocol: settings.gitlab_protocol,
                        webhook_secret: settings.webhook_secret,
                        webhook_domain: settings.webhook_domain)
docker = DockerContState.new
term_sec = TerminalSecurity.new(settings.terminal_secret)
webhook_sec = WebhookSecurity.new(settings.webhook_secret)
stagings_activity = StagingsActivity.new(redis_host: settings.redis_host,
                                         redis_port: settings.redis_port,
                                         redis_db: settings.redis_db,
                                         redis_ttl: settings.redis_ttl)
api_limit = ApiLimit.new(redis_host: settings.redis_host,
                         redis_port: settings.redis_port,
                         redis_db: settings.redis_db,
                         api_limit_ttl: settings.api_limit_ttl,
                         api_request_limit: settings.api_request_limit)

container_ttl = StagingsTtl.new(redis_host: settings.redis_host,
                                port: settings.redis_port,
                                redis_db: settings.redis_db,
                                container_ttl: settings.container_ttl,
                                container_max_ttl: settings.container_max_ttl)
md5sum = Digest::MD5.new

@user_profile_link = settings.gitlab_protocol

def auth_procedure
  if !session[:identity] then
    session[:previous_url] = request.path
    @error = 'Auth required ' + request.path
    status 403
    halt erb(:signin)
  end
end

def validate_branches
  check_param = params[:rebuild] if params[:rebuild]
  check_param = params[:remove] if params[:remove]
  check_param = params[:project_branch] if params[:project_branch]
  unless @project_branches.map { |branch| branch['name'] }.each.include?(check_param)
    halt 404
  end
end

def validate_projects
  unless @user_projects.map { |project| project['name'] }.each.include?(@current_project)
    halt 404
  end
end

def get_or_post(path, opts={}, &block)
  get(path, opts, &block)
  post(path, opts, &block)
end

get '/' do
  auth_procedure
  @username = session[:identity]
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  @activity = stagings_activity.all_activity_for_user(@user_projects.map { |project| project['name'] })
  @stag_prefix = settings.stag_prefix
  erb(:home)
end

get_or_post '/project/:project_name' do
  auth_procedure
  @username = session[:identity]
  @current_project  = params['project_name']
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  validate_projects
  @current_id       = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @phpmyadmin_url = settings.phpmyadmin_url
  @mysql_root_password = docker.mysql_container_password(@current_project)
  @md5 = md5sum
  @max_ttl = (settings.container_max_ttl / 60 / 60 / 24).to_i
  if docker.project_image_exist?(@current_project)
    @docker_image_exists = true
    @project_branches = gitlab.project_branches(session[:gitlab_private_token], @current_id)
    running_containers = docker.running_project_branches(@current_project)
    @project_branches.each do |branch|
      if running_containers.any? { |container| container[:name] == branch['name'] }
        running_containers.each { |container| branch['state'] = container[:uptime] if container[:name] == branch['name'] }
      else
        branch['state'] = 'Down'
      end
      branch['ttl'] = container_ttl.get_ttl(@current_project, branch['name'])
    end
    @stag_prefix = settings.stag_prefix
    @term_token  = term_sec.security_token(@current_project)
  end

  if params[:rebuild]
    validate_branches
    flash[:rebuild] = params[:rebuild]
    stagings_activity.add_action(project: @current_project, branch: params[:rebuild], email: session[:identity], type: 'build', via: 'manually')
    cpu_cores = Staginator.cpu_cores_to_bind(settings.container_maxcpu)
    PortForwarding.rm_all_from_iptables(@current_project, params[:rebuild])
    pid = Process.spawn("sudo /usr/local/bin/create_new_container.sh #{@current_project} #{params[:rebuild]} #{settings.container_maxmem} #{cpu_cores}")
    Thread.new(pid, @current_project, params[:rebuild], settings.public_ip) do |process_id, project, container_name, public_ip|
      Process.wait(process_id)
      PortForwarding.restore_iptables_rules(project, container_name, public_ip)
    end
    redirect to("/project/#{@current_project}")
  end

  if params[:remove]
    validate_branches
    flash[:remove] = params[:remove]
    stagings_activity.add_action(project: @current_project, branch: params[:remove], email: session[:identity], type: 'remove', via: 'manually')
    Process.spawn("sudo /usr/local/bin/remove_container.sh #{@current_project} #{params[:remove]}")
    PortForwarding.rm_all_from_iptables(@current_project, params[:remove])
    redirect to("/project/#{@current_project}")
  end
  @active_item = 'project_page'
  erb(:project_page)
end

get '/project/:project_name/activity' do
  auth_procedure
  @username = session[:identity]
  @current_project  = params['project_name']
  @stag_prefix = settings.stag_prefix
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  validate_projects
  @activity = stagings_activity.project_activity(@current_project)
  @active_project_tab = 'activity'
  @active_item = 'project_page'
  erb(:project_activity)
end

get '/project/:project_name/info' do
  auth_procedure
  @username = session[:identity]
  @current_project  = params['project_name']
  @stag_prefix = settings.stag_prefix
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  validate_projects
  @phpmyadmin_url = settings.phpmyadmin_url
  @mysql_root_password = docker.mysql_container_password(@current_project)
  @active_project_tab = 'info'
  @active_item = 'project_page'
  @gitlab_user_permission = gitlab.user_permission_level(session[:gitlab_private_token], @current_id, @username)
  @webhook_status = gitlab.staginator_webhook_present?(session[:gitlab_private_token], @current_project) if @gitlab_user_permission == 40
  @projects_templates = settings.docker_templates
  erb(:project_info)
end

get '/check_port/:port_number' do
  auth_procedure
  PortForwarding.check_tcp_port(settings.public_ip, params[:port_number].to_i)
end

get '/project/:project_name/port_forwarding' do
  auth_procedure
  @username = session[:identity]
  @current_project  = params['project_name']
  @stag_prefix = settings.stag_prefix
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  validate_projects
  @active_project_tab = 'port_forwarding'
  @active_item = 'project_page'
  @ip_forwardings = IpForwarding.where(project_name: @current_project)
  @public_ip = settings.public_ip
  erb(:port_forwarding)
end

get '/project/:project_name/port_forwarding/create' do
  auth_procedure
  @username = session[:identity]
  @current_project  = params['project_name']
  @stag_prefix = settings.stag_prefix
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  @project_branches = gitlab.project_branches(session[:gitlab_private_token], @current_id)
  running_containers = docker.running_project_branches(@current_project)
  @project_branches.each do |branch|
    if running_containers.any? { |container| container[:name] == branch['name'] }
      running_containers.each { |container| branch['state'] = container[:uptime] if container[:name] == branch['name'] }
    else
      branch['state'] = 'Down'
    end
  end
  validate_projects
  @active_project_tab = 'port_forwarding'
  @active_item = 'project_page'
  erb(:port_forwarding_create)
end

post '/project/:project_name/port_forwarding' do
  auth_procedure
  @username = session[:identity]
  @current_project  = params['project_name']
  @stag_prefix = settings.stag_prefix
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  @project_branches = gitlab.project_branches(session[:gitlab_private_token], @current_id)
  running_containers = docker.running_project_branches(@current_project)
  @project_branches.each do |branch|
    if running_containers.any? { |container| container[:name] == branch['name'] }
      running_containers.each { |container| branch['state'] = container[:uptime] if container[:name] == branch['name'] }
    else
      branch['state'] = 'Down'
    end
  end
  validate_projects
  validate_branches
  if params[:remove]
    ip_forwarding = IpForwarding.find_by(project_name: @current_project, container_name: params[:project_branch], container_port: params[:container_port].to_i, host_port: params[:host_port].to_i)
    ip_forwarding.delete
    PortForwarding.rm_from_iptables(params[:host_port].to_i)
    return 'ok'
  else
    if params[:host_port]
      host_port = params[:host_port]
    else
      host_port = PortForwarding.random_tcp_port(settings.public_ip)
    end
    if PortForwarding.check_tcp_port(settings.public_ip, host_port.to_i) == 'free'
      IpForwarding.create(project_name: @current_project, container_name: params[:project_branch], container_port: params[:container_port].to_i, host_port: host_port.to_i, added_by: @username)
      PortForwarding.add_to_iptables(params[:container_port], host_port, docker.ip(@current_project, params[:project_branch]), settings.public_ip)
    else
      flash[:port_busy] = true
    end

    redirect to("/project/#{@current_project}/port_forwarding")
  end
end

post '/project/:project_name/info/rebuild' do
  auth_procedure
  username = session[:identity]
  @current_project  = params['project_name']
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  validate_projects
  unless settings.docker_templates.include?(params[:base_image])
    halt 500
  end
  if gitlab.user_permission_level(session[:gitlab_private_token], @current_id, username) == 40
    Process.spawn("#{settings.root}/bin/rebuild_project.rb #{session[:gitlab_private_token]} #{params[:base_image]} #{@current_project} #{username}")
    flash[:project_rebuild] = true
    redirect to("/project/#{@current_project}/info")
  else
    render 500
  end
end

post '/project/:project_name/info/remove' do
  auth_procedure
  username = session[:identity]
  @current_project  = params['project_name']
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  validate_projects
  if gitlab.user_permission_level(session[:gitlab_private_token], @current_id, username) == 40
    Process.spawn("#{settings.root}/bin/remove_project.rb #{session[:gitlab_private_token]} #{@username} #{@current_project}")
    flash[:project_remove] = true
    redirect to('/')
  else
    render 500
  end
end

get '/project/:project_name/ttl/:project_branch' do
  auth_procedure
  username = session[:identity]
  @current_project  = params['project_name']
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @project_branches = gitlab.project_branches(session[:gitlab_private_token], @current_id)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)

  validate_projects
  validate_branches
  "#{container_ttl.get_ttl(@current_project, params[:project_branch])}"
end

post '/project/:project_name/ttl/:project_branch' do
  auth_procedure
  username = session[:identity]
  @current_project  = params['project_name']
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @project_branches = gitlab.project_branches(session[:gitlab_private_token], @current_id)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  @max_ttl = (settings.container_max_ttl / 60 / 60 / 24).to_i

  validate_projects
  validate_branches

  if Staginator.is_numeric?(params[:ttl]) and params[:ttl].to_i > 0 and params[:ttl].to_i < @max_ttl
    container_ttl.set_ttl(@current_project, params[:project_branch], params[:ttl].to_i)
  else
    halt 400
  end
end

post '/project/:project_name/info/webhook' do
  auth_procedure
  username = session[:identity]
  current_project  = params['project_name']
  current_id = gitlab.project_id_by_name(session[:gitlab_private_token], current_project)
  if gitlab.user_permission_level(session[:gitlab_private_token], current_id, username) == 40
    if params[:remove] and gitlab.staginator_webhook_present?(session[:gitlab_private_token], current_project)
      gitlab.remove_webhook(session[:gitlab_private_token], current_id, current_project)
    end
    if params[:add] and ( gitlab.staginator_webhook_present?(session[:gitlab_private_token], current_project) == false )
      gitlab.add_webhook(session[:gitlab_private_token], current_id, current_project)
    end
    redirect to("/project/#{current_project}/info")
  else
    render 500
  end
end

get '/project/:project_name/:project_branch/logs' do
  auth_procedure
  @username = session[:identity]
  @current_project = params['project_name']
  @stag_prefix = settings.stag_prefix
  @current_id = gitlab.project_id_by_name(session[:gitlab_private_token], @current_project)
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  @project_branches = gitlab.project_branches(session[:gitlab_private_token], @current_id)
  validate_projects
  validate_branches
  @project_branch = params[:project_branch]
  @container_logs = docker.logs(@current_project, @project_branch)
  @active_item = 'project_page'
  erb(:deploy_log)
end

get '/create_new' do
  auth_procedure
  @username = session[:identity]
  gitlab_projects = gitlab.user_projects(session[:gitlab_private_token])
  @projects_without_staging = Staginator.projects_without_stagings(gitlab_projects, docker)
  @user_projects = Staginator.projects_with_stagings(gitlab_projects, docker)
  @projects_templates = settings.docker_templates
  @active_item = 'create_new'
  erb(:create_new)
end

post '/create_new' do
  auth_procedure
  @username = session[:identity]
  gitlab_projects = gitlab.user_projects(session[:gitlab_private_token])
  @projects_without_staging = Staginator.projects_without_stagings(gitlab_projects, docker)
  @user_projects = Staginator.projects_with_stagings(gitlab_projects, docker)
  @projects_templates = settings.docker_templates

  unless settings.docker_templates.include?(params[:selected_template])
    halt 500
  end
  unless @projects_without_staging.map { |project| project['name'] }.each.include?(params[:selected_repo])
    halt 500
  end
  project_id = gitlab.project_id_by_name(session[:gitlab_private_token], params[:selected_repo])
  if gitlab.user_permission_level(session[:gitlab_private_token], project_id, @username) == 40
    flash[:staging_creating] = true
    gitlab.add_webhook(session[:gitlab_private_token], project_id, params[:selected_repo]) if params[:webhook]
    Process.spawn("#{settings.root}/bin/create_new_image.rb #{session[:gitlab_private_token]} #{params[:selected_template]} #{params[:selected_repo]} #{@username}")
  else
    flash[:permission_error] = true
  end
  # post data:
  # "#{params[:selected_repo]} #{params[:selected_template]} #{params[:webhook]}"

  redirect to('/create_new')
end

get '/help' do
  auth_procedure
  @username = session[:identity]
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  @active_item = 'help'
  @active_article = 'home'
  erb(:help_page)
end

get '/help/:article' do
  auth_procedure
  @username = session[:identity]
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  @active_item = 'help'
  @active_article = params[:article]
  unless ['home', 'cron_task', 'container_customization', 'limits'].include? @active_article
    not_found
  end
  @maxmem = settings.container_maxmem
  @maxcpu = settings.container_maxcpu
  erb(:help_page)
end

get_or_post '/api/v1/project/:project_name/branch/:branch_name' do
  if request.env['HTTP_X_REAL_IP']
    client_ip = request.env['HTTP_X_REAL_IP']
  else
    client_ip = request.ip
  end
  if api_limit.limit_reached? client_ip
    halt 429
  end
  api_limit.register_request client_ip
  projects = Staginator.projects_with_stagings(gitlab.user_projects(settings.gitlab_admin_private_token), docker)
  api_response = { project_exist: false }
  projects.each { |project| api_response[:project_exist] = true if project['name'] == params[:project_name]}
  if api_response[:project_exist]
    api_response[:branch_exist] = false
    project_id = gitlab.project_id_by_name(settings.gitlab_admin_private_token, params[:project_name])
    project_branches = gitlab.project_branches(settings.gitlab_admin_private_token, project_id)
    project_branches.each { |branch| api_response[:branch_exist] = true if branch['name'] == params[:branch_name] }
    if api_response[:branch_exist]
      running_branches_names = []
      docker.running_project_branches(params[:project_name]).each { |branch| running_branches_names << branch[:name] }
      if running_branches_names.include? params[:branch_name]
        api_response[:up] = true
      else
        api_response[:up] = false
      end
    end
  end
  if params[:start] and api_response[:project_exist] and api_response[:branch_exist] and api_response[:up] == false
    stagings_activity.add_action(project: params[:project_name], branch: params[:branch_name], email: 'api', type: 'build')
    cpu_cores = Staginator.cpu_cores_to_bind(settings.container_maxcpu)
    Process.spawn("sudo /usr/local/bin/create_new_container.sh #{params[:project_name]} #{params[:branch_name]} #{settings.container_maxmem} #{cpu_cores}")
  end
  return JSON.pretty_generate(api_response)
end

get '/signin' do
  auth_procedure
  if session[:previous_url] == '/signin'
    redirect to('/')
  else
    redirect to(session[:previous_url])
  end
end

post '/signin' do
  begin
    private_token = gitlab.auth_user(params[:email], params[:password])
  rescue
    @failed_login = true
    auth_procedure
  end
  session[:identity]             = params[:email]
  session[:gitlab_private_token] = private_token
  redirect to(session[:previous_url])
end

get '/logout' do
  session.clear
  redirect to('/')
end

get '/term_sec_auth/:project_name' do
  if params[:token] == term_sec.security_token(params[:project_name])
    status 200
  else
    status 403
  end

end

post '/webhook/gitlab/:project_name' do
  unless docker.project_image_exist?(params[:project_name])
    logger.info("project does not exist: #{params[:project_name]}")
    halt 403
  end
  if params[:sec] != webhook_sec.security_token(params[:project_name])
    logger.info("token verification failed for #{params[:project_name]}")
    halt 403
  end
  webhook = JSON.parse(request.body.read)
  unless webhook['after'] == '0000000000000000000000000000000000000000'
    branch = webhook['ref'].split('/')[2]
    cpu_cores = Staginator.cpu_cores_to_bind(settings.container_maxcpu)
    line = Cocaine::CommandLine.new('sudo /usr/local/bin/create_new_container.sh', ':project :branch :memory_limit :cpu_cores')
    logger.info("webhook create for #{branch} at #{params[:project_name]}")
    user_email = gitlab.user_info_by_id(settings.gitlab_admin_private_token, webhook['user_id'])['email']
    stagings_activity.add_action(project: params[:project_name], branch: branch, email: user_email, type: 'build', via: 'webhook')
    PortForwarding.rm_all_from_iptables(params[:project_name], branch)
    pid = Process.spawn(line.command(project: params[:project_name], branch: branch, memory_limit: settings.container_maxmem, cpu_cores: cpu_cores))
    Thread.new(pid, params[:project_name], branch, settings.public_ip) do |process_id, project, container_name, public_ip|
      Process.wait(process_id)
      PortForwarding.restore_iptables_rules(project, container_name, public_ip)
    end
  end

  if webhook['after'] == '0000000000000000000000000000000000000000'
    branch = webhook['ref'].split('/')[2]
    line = Cocaine::CommandLine.new('sudo /usr/local/bin/remove_container.sh', ':project :branch')
    logger.info("webhook remove for #{branch} at #{params[:project_name]}")
    user_email = gitlab.user_info_by_id(settings.gitlab_admin_private_token, webhook['user_id'])['email']
    stagings_activity.add_action(project: params[:project_name], branch: branch, email: user_email, type: 'remove', via: 'webhook')
    docker.remove_mysql_db(params[:project_name], branch)
    Process.spawn(line.command(project: params[:project_name], branch: branch))
    PortForwarding.rm_all_for_container(params[:project_name], branch)
  end

end

not_found do
  auth_procedure
  @not_found_404 = true
  @username = session[:identity]
  @user_projects = Staginator.projects_with_stagings(gitlab.user_projects(session[:gitlab_private_token]), docker)
  erb(:home)
end

error 500 do
  erb(:internal_server_error)
end

error 400 do
  '{error: true}'
end