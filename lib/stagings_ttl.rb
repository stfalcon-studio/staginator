class StagingsTtl
  def initialize(opts)
    require 'redis'
    require 'json'
    require 'date'
    @redis_client = Redis.new(host: opts[:redis_host], port: opts[:redis_port], db: opts[:redis_db] + '_ttl')
    @record_ttl   = opts[:container_max_ttl]
    @default_container_ttl = opts[:container_ttl]
  end

  def get_ttl(project, branch)
    ttl = @redis_client.get("ttl_#{project}_#{branch}")
    if ttl
      ttl
    else
      (@default_container_ttl / 60 / 60 / 24).to_i
    end
  end

  def get_ttl_seconds(project, branch)
    (get_ttl(project, branch).to_i * 60 * 60 * 24).to_i
  end

  def set_ttl(project, branch, ttl)
    @redis_client.set("ttl_#{project}_#{branch}", ttl, ex: @record_ttl)
    begin
      @redis_client.save
    rescue Redis::CommandError
      puts 'save to Redis already in progress, skipping'
    end
  end
end