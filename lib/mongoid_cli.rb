require 'mongoid'
require 'require_all'
require_all '../models'

Mongoid.load!('../mongoid.yml', :development)