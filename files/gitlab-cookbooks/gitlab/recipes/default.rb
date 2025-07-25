#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# Copyright:: Copyright (c) 2014 GitLab Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'openssl'
require_relative '../../package/libraries/settings_dsl.rb'

# Default location of install-dir is /opt/gitlab/. This path is set during build time.
# DO NOT change this value unless you are building your own GitLab packages
install_dir = node['package']['install-dir']
ENV['PATH'] = "#{install_dir}/bin:#{install_dir}/embedded/bin:#{ENV['PATH']}"

include_recipe 'gitlab::config'

OmnibusHelper.check_deprecations
OmnibusHelper.check_environment
OmnibusHelper.check_locale

# Setup additional postgresql attributes
include_recipe 'postgresql::directory_locations'

directory "/etc/gitlab" do
  owner "root"
  group "root"
  mode "0775"
  only_if { node['gitlab']['manage_storage_directories']['manage_etc'] }
end.run_action(:create)

node.default['gitlab']['bootstrap']['enable'] = false if File.exist?("/var/opt/gitlab/bootstrapped")

directory "Create /var/opt/gitlab" do
  path "/var/opt/gitlab"
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

directory "Create /var/log/gitlab" do
  path "/var/log/gitlab"
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

directory "#{install_dir}/embedded/etc" do
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

# This recipe needs to run before gitlab-rails
# because we add `gitlab-www` user to some groups created by that recipe
include_recipe "gitlab::web-server"

# We attempt to create and manage users/groups by default. If users wish to
# disable it, they can set `manage_accounts['enable']` to `false`, and
# `account` custom resource will not create them.
include_recipe "gitlab::users"

include_recipe "gitlab::gitlab-rails" if node['gitlab']['gitlab_rails']['enable']

include_recipe "gitlab::selinux"

# add trusted certs recipe
include_recipe "gitlab::add_trusted_certs"

# Create dummy services to receive notifications, in case
# the corresponding service recipe is not loaded below.
%w(
  puma
  sidekiq
  mailroom
).each do |dummy|
  service "create a temporary #{dummy} service" do
    service_name dummy
    supports []
  end
end

# Install our runit instance
include_recipe "package::runit"

# Install shell after runit so `gitlab-sshd` comes up
include_recipe "gitlab::gitlab-shell" if node['gitlab']['gitlab_rails']['enable']

# Make global sysctl commands available
include_recipe "package::sysctl"

# Configure Pre-migration services
# Postgresql depends on Redis because of `rake db:seed_fu`
# Gitaly and/or Praefect must be available before migrations
%w(
  logrotate
  redis
  gitaly
  postgresql
  praefect
  gitlab-kas
).each do |service|
  node_attribute_key = SettingsDSL::Utils.node_attribute_key(service)
  if node[node_attribute_key]['enable']
    include_recipe "#{service}::enable"
  else
    include_recipe "#{service}::disable"
  end
end

if node['gitlab']['gitlab_rails']['enable'] && !(node.key?('pgbouncer') && node['pgbouncer']['enable'])
  include_recipe "gitlab::database_migrations"

  # We need to deal with initial root password only if the DB migrations were
  # applied.
  OmnibusHelper.new(node).print_root_account_details if node['gitlab']['gitlab_rails']['auto_migrate']
end

OmnibusHelper.cleanup_root_password_file

# crond is used by database reindexing and LetsEncrypt auto-renew.  If
# neither are on, we disable crond to prevent stale config files from
# being used.
if node['gitlab']['gitlab_rails']['database_reindexing']['enable'] || (node['letsencrypt']['enable'] && node['letsencrypt']['auto_renew'])
  include_recipe "crond::enable"
else
  include_recipe "crond::disable"
end

# Configure Services
%w[
  puma
  sidekiq
  gitlab-workhorse
  mailroom
  nginx
  remote-syslog
  bootstrap
  storage-check
].each do |service|
  node_attribute_key = SettingsDSL::Utils.node_attribute_key(service)
  if node["gitlab"][node_attribute_key]["enable"]
    include_recipe "gitlab::#{service}"
  else
    include_recipe "gitlab::#{service}_disable"
  end
end

%w(
  gitlab-pages
  registry
  mattermost
  gitlab-kas
  letsencrypt
).each do |cookbook|
  node_attribute_key = SettingsDSL::Utils.node_attribute_key(cookbook)
  if node[node_attribute_key]["enable"]
    include_recipe "#{cookbook}::enable"
  else
    include_recipe "#{cookbook}::disable"
  end
end
# Configure healthcheck if we have nginx or workhorse enabled
include_recipe "gitlab::gitlab-healthcheck" if node['gitlab']['nginx']['enable'] || node["gitlab"]["gitlab_workhorse"]["enable"]

# Recipe which handles all prometheus related services
include_recipe "monitoring"

# Recipe for gitlab-backup-cli tool
if node['gitlab']['gitlab_backup_cli']['enable']
  include_recipe "gitlab::gitlab-backup-cli"
else
  include_recipe "gitlab::gitlab-backup-cli_disable"
end

if node['gitlab']['gitlab_rails']['database_reindexing']['enable']
  include_recipe 'gitlab::database_reindexing_enable'
else
  include_recipe 'gitlab::database_reindexing_disable'
end

OmnibusHelper.is_deprecated_os?

# Report on any deprecations we encountered at the end of the run
# There are three possible exits for a reconfigure run
# 1. Normal cinc-client run completion
# 2. cinc-client failed due to an exception
# 3. cinc-client failed for some other reason
# 1 and 3 are handled below. 2 is handled in our custom exception handler
# defined at files/gitlab-cookbooks/package/libraries/handlers/gitlab.rb
Chef.event_handler do
  on :run_completed do
    OmnibusHelper.on_exit
  end

  on :run_failed do
    OmnibusHelper.on_exit
  end
end
