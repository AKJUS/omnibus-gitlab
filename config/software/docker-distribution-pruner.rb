#
# Copyright:: Copyright (c) 2019 GitLab Inc.
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
require "#{Omnibus::Config.project_root}/lib/gitlab/version"
version = Gitlab::Version.new('docker-distribution-pruner', '0.3.2')

name 'docker-distribution-pruner'
default_version version.print

license 'MIT'
license_file 'LICENSE'

skip_transitive_dependency_licensing true

source git: version.remote
relative_path 'src/gitlab.com/gitlab-org/docker-distribution-pruner'

build do
  env = {
    'GOPATH' => "#{Omnibus::Config.source_dir}/docker-distribution-pruner",
    'GOTOOLCHAIN' => 'local',
  }

  command "go build -ldflags '-s -w' ./cmds/docker-distribution-pruner", env: env

  mkdir "#{install_dir}/embedded/bin/"
  copy 'docker-distribution-pruner', "#{install_dir}/embedded/bin/"

  command "license_finder report --enabled-package-managers godep gomodules --decisions-file=#{Omnibus::Config.project_root}/support/dependency_decisions.yml --format=json --columns name version licenses texts notice --save=license.json"
  copy "license.json", "#{install_dir}/licenses/docker-distribution-pruner.json"
end
