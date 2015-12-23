class GitlabApi

  def initialize(options = {})
    require 'rest-client'
    require 'json'
    @gitlab_host     = options[:gitlab_host]
    @gitlab_protocol = options[:gitlab_protocol]
    @webhook_secret  = options[:webhook_secret]
    @webhook_domain  = options[:webhook_domain]
  end

  def auth_user(email, password)
    client = RestClient.post("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/session", "email=#{email}&password=#{password}")
    JSON.parse(client)["private_token"]
  end

  def user_projects(private_token)
    client = RestClient.get("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/projects?private_token=#{private_token}&per_page=100000")
    JSON.parse(client)
  end

  def user_permission_level(private_token, project_id, user_email)
    members = JSON.parse RestClient.get("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/projects/#{project_id}/members?private_token=#{private_token}&per_page=100000")
    members.each { |member| return member['access_level'] if member['email'] == user_email }
  end

  def project_id_by_name(private_token, project_name)
    project = JSON.parse RestClient.get("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/projects/#{project_name}?private_token=#{private_token}")
    project['id']
  end

  def project_branches(private_token, project_id)
    client = RestClient.get("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/projects/#{project_id}/repository/branches?private_token=#{private_token}&per_page=100000")
    JSON.parse(client)
  end

  def add_deploy_key(private_token, project_id, public_key)
    RestClient.post("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/projects/#{project_id}/keys?private_token=#{private_token}", { 'id' => project_id, 'title' => 'staginator-key', 'key' => public_key }.to_json, :content_type => :json, :accept => :json)
  end

  def add_webhook(private_token, project_id, project_name)
    token = WebhookSecurity.new(@webhook_secret).security_token(project_name)
    url = "http://#{@webhook_domain}/webhook/gitlab/#{project_name}?sec=#{token}"
    RestClient.post("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/projects/#{project_id}/hooks?private_token=#{private_token}", { 'id' => project_id, 'url' => url }.to_json, :content_type => :json, :accept => :json)
  end

  def remove_webhook(private_token, project_id, project_name)
    token = WebhookSecurity.new(@webhook_secret).security_token(project_name)
    url = "http://#{@webhook_domain}/webhook/gitlab/#{project_name}?sec=#{token}"
    get_webhooks(private_token, project_name).each do |webhook|
      RestClient.delete("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/projects/#{project_id}/hooks/#{webhook['id']}?private_token=#{private_token}") if webhook['url'] == url
    end
  end

  def staginator_webhook_present?(private_token, project_name)
    token = WebhookSecurity.new(@webhook_secret).security_token(project_name)
    url = "http://#{@webhook_domain}/webhook/gitlab/#{project_name}?sec=#{token}"
    present_urls = []
    get_webhooks(private_token, project_name).each { |webhook| present_urls << webhook['url']}
    if present_urls.include?(url)
      true
    else
      false
    end
  end

  def user_info_by_id(private_token, user_id)
    user = RestClient.get("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/users/#{user_id}?private_token=#{private_token}")
    JSON.parse(user)
  end

  private

  def get_webhooks(private_token, project_name)
    client = RestClient.get("#{@gitlab_protocol}://#{@gitlab_host}/api/v3/projects/#{project_name}/hooks?private_token=#{private_token}")
    JSON.parse(client)
  end

end