class ApiLimit

  def initialize(opts)
    require 'redis'
    @redis_client      = Redis.new(host: opts[:redis_host], port: opts[:redis_port], db: opts[:redis_db])
    @record_ttl        = opts[:api_limit_ttl]
    @api_request_limit = opts[:api_request_limit]
  end

  def limit_reached?(ip)
    if get_key(ip) < @api_request_limit
      false
    else
      true
    end
  end

  def register_request(ip)
    incr_key(ip)
  end

  private

  def add_key(ip)
    @redis_client.set("api_limit_#{ip}", 0, ex: @record_ttl)
  end

  def get_key(ip)
    limit = @redis_client.get("api_limit_#{ip}")
    if limit
      limit.to_i
    else
      add_key(ip)
      0
    end
  end

  def incr_key(ip)
    if get_key(ip)
      @redis_client.incr("api_limit_#{ip}")
    else
      add_key(ip)
      @redis_client.incr("api_limit_#{ip}")
    end
  end
end