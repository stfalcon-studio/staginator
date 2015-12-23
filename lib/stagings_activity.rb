class StagingsActivity

  def initialize(opts)
    require 'redis'
    require 'json'
    require 'date'
    @redis_client = Redis.new(host: opts[:redis_host], port: opts[:redis_port], db: opts[:redis_db])
    @record_ttl   = opts[:redis_ttl]
  end

  # {project: 'google-com', branch: 'dev', email: 'root@example.com', type: 'build, remove, project_create'}
  def add_action(opts)
    action = opts
    action[:date] = DateTime.now
    add_key('all', action)
    add_key(action[:project], action)
  end

  def all_activity
    get_keys('all_')
  end

  def all_activity_for_user(allowed_projects)
    activity = all_activity
    if activity
      activity.map! { |action| action if allowed_projects.include?(action['project']) }
      activity.compact
    end
  end

  def project_activity(project)
    get_keys(project)
  end

  private

  def add_key(prefix, action)
    @redis_client.set("#{prefix}_#{action[:date].to_time.to_i}", action.to_json, ex: @record_ttl)
    begin
      @redis_client.save
    rescue Redis::CommandError
      puts 'save to Redis already in progress, skipping'
    end
  end

  def get_keys(prefix)
    keys     = []
    activity = []
    @redis_client.keys.sort.reverse.each { |key| keys << key if (key.include?(prefix)) and not(key.include?('ttl_'))}
    keys.each do |key|
      current_key = JSON.parse(@redis_client.get(key))
      current_key['date'] = DateTime.iso8601(current_key['date'])
      activity << current_key
    end
    if activity.length > 0
      activity
    else
      nil
    end
  end

end