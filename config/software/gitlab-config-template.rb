#
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

name 'gitlab-config-template'

license 'Apache-2.0'
license_file File.expand_path('LICENSE', Omnibus::Config.project_root)

skip_transitive_dependency_licensing true

source path: File.expand_path('files/gitlab-config-template', Omnibus::Config.project_root)

build do
  mkdir "#{install_dir}/etc"
  sync './', "#{install_dir}/etc/"
end
