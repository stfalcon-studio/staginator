class Staginator

  def initialize
    # unless @instance
    #   @session = session
    # end
    @instance ||= self
  end

  class << self

    def projects_without_stagings(user_projects, docker)
      projects_without_staging = []
      project_images = docker.all_images
      user_projects.each do |repo|
        projects_without_staging << repo unless project_images.any? { |img| img.include?(repo['name']) }
      end
      projects_without_staging
    end

    def projects_with_stagings(user_projects, docker)
      projects_without_staging = projects_without_stagings(user_projects, docker)
      user_projects.map! { |project| project unless projects_without_staging.include?(project)}
      user_projects.compact!
    end

    def cpu_cores_count
      require 'facter'
      Facter.value('processors')['count']
    end

    def cpu_cores_to_bind(count)
      max_cores = cpu_cores_count
      if count > max_cores
        raise 'Check your config.yml: container_maxcpu should not be greater than cores of your cpu'
      end
      cores = []
      while cores.length < count
        random_core = Random.rand(max_cores)
        cores << random_core unless cores.include?(random_core)
      end
      cores.join(',')
    end

    def is_numeric?(obj)
      obj.to_s.match(/\A[+-]?\d+?(\.\d+)?\Z/) == nil ? false : true
    end

  end

end