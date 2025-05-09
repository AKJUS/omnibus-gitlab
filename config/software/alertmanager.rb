#
## Copyright:: Copyright (c) 2018 GitLab Inc.
## License:: Apache License, Version 2.0
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
## http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
#

require "#{Omnibus::Config.project_root}/lib/gitlab/version"
require "#{Omnibus::Config.project_root}/lib/gitlab/prometheus_helper"

name 'alertmanager'
version = Gitlab::Version.new('alertmanager', '0.28.1')
default_version version.print

license 'APACHE-2.0'
license_file 'LICENSE'
license_file 'NOTICE'

skip_transitive_dependency_licensing true

source git: version.remote

go_source = 'github.com/prometheus/alertmanager'
relative_path "src/#{go_source}"

build do
  env = {
    'GOPATH' => "#{Omnibus::Config.source_dir}/alertmanager",
    'GO111MODULE' => 'on',
    'GOTOOLCHAIN' => 'local',
  }
  exporter_source_dir = "#{Omnibus::Config.source_dir}/alertmanager"
  cwd = "#{exporter_source_dir}/src/#{go_source}"

  prom_version = Prometheus::VersionFlags.new(version)

  command "go build -ldflags '#{prom_version.print_ldflags}' ./cmd/alertmanager", env: env, cwd: cwd

  mkdir "#{install_dir}/embedded/bin/"
  copy 'alertmanager', "#{install_dir}/embedded/bin/"

  command "license_finder report --enabled-package-managers godep gomodules --decisions-file=#{Omnibus::Config.project_root}/support/dependency_decisions.yml --format=json --columns name version licenses texts notice --save=license.json"
  copy "license.json", "#{install_dir}/licenses/alertmanager.json"
end
