#
# Copyright:: Copyright (c) 2024 GitLab Inc.
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

account_helper = AccountHelper.new(node)
gitlab_user = account_helper.gitlab_user
gitlab_group = account_helper.gitlab_group

# Holds git-data, by default one shard at /var/opt/gitlab/git-data
# Can be changed by user using git_data_dirs option
Mash.new(Gitlab['git_data_dirs']).each do |_name, git_data_directory|
  next unless git_data_directory['path']

  storage_directory git_data_directory['path'] do
    owner gitlab_user
    group gitlab_group
    mode "2770"
  end
end

# Create the Git storage directories. There may be no directories if external Gitaly is used.
repositories_storages = Gitlab['gitaly'].dig('configuration', 'storage') || []
repositories_storages.each do |repositories_storage|
  storage_directory repositories_storage[:path] do
    owner gitlab_user
    group gitlab_group
    mode "2770"
  end
end
