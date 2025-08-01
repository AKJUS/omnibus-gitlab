#
## Copyright:: Copyright (c) 2014 GitLab Inc.
## License:: Apache License, Version 2.0
##
## Licensed under the Apache License, Version 2.0 (the 'License');
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
## http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an 'AS IS' BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
#

require "#{Omnibus::Config.project_root}/lib/gitlab/version"
require 'time'

name 'redis-exporter'
version = Gitlab::Version.new('redis-exporter', '1.74.0')
default_version version.print

license 'MIT'
license_file 'LICENSE'

source git: version.remote

relative_path 'src/github.com/oliver006/redis_exporter'

build do
  env = {
    'GOPATH' => "#{Omnibus::Config.source_dir}/redis-exporter",
    'GO111MODULE' => 'on',
    'GOTOOLCHAIN' => 'local',
  }

  ldflags = [
    "-X main.BuildVersion=#{version.print(false)}",
    "-X main.BuildDate=''",
    "-X main.BuildCommitSha=''",
    "-s",
    "-w"
  ].join(' ')

  command "go build -ldflags '#{ldflags}'", env: env

  mkdir "#{install_dir}/embedded/bin"
  copy 'redis_exporter', "#{install_dir}/embedded/bin/"

  command "license_finder report --enabled-package-managers godep gomodules --decisions-file=#{Omnibus::Config.project_root}/support/dependency_decisions.yml --format=json --columns name version licenses texts notice --save=license.json"
  copy "license.json", "#{install_dir}/licenses/redis-exporter.json"
end
