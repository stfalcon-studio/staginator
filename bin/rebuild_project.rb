#!/usr/bin/env ruby
# usage: ./rebuild_project.rb gitlab_token template_name project_name notify_to@email.com

gitlab_token   = ARGV[0]
template_name  = ARGV[1]
project_name   = ARGV[2]
notify_address = ARGV[3]
work_dir       = File.expand_path($0).split('/bin/rebuild_project.rb')[0]

pid = Process.spawn("#{work_dir}/bin/remove_project.rb #{gitlab_token} #{project_name}")
Process.wait pid

pid = Process.spawn("#{work_dir}/bin/create_new_image.rb #{gitlab_token} #{template_name} #{project_name} #{notify_address}")
Process.wait pid