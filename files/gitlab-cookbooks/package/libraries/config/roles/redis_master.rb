# Copyright:: Copyright (c) 2017 GitLab Inc.
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

module RedisMasterRole
  def self.load_role
    master_role = Gitlab['redis_master_role']['enable']
    replica_role = Gitlab['redis_replica_role']['enable']

    return unless master_role || replica_role

    raise 'Cannot define both redis_master_role and redis_replica_role in the same machine.' if master_role && replica_role

    # Do not run GitLab Rails related recipes unless explicitly enabled
    Gitlab['gitlab_rails']['enable'] ||= false

    Services.enable_group('redis_node') if master_role || replica_role
  end
end
