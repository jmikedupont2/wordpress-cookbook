#
# Cookbook Name:: wordpress
# Recipe:: database
# Author:: Lucas Hansen (<lucash@opscode.com>)
# Author:: Julian C. Dunn (<jdunn@getchef.com>)
# Author:: Craig Tracey (<craigtracey@gmail.com>)
#
# Copyright (C) 2013, Chef Software, Inc.
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

include_recipe 'yum-mysql-community::mysql' + node['wordpress']['db']['mysql_version'].delete('.')

mysql_client 'default' do
  action :create
  not_if { node['platform_family'] == 'windows' }
end

mysql2_chef_gem 'default' do
  action :install
end

::Chef::Resource.send(:include, OpenSSLCookbook::RandomPassword)
::Chef::Recipe.send(:include, Wordpress::Helpers)

db = node['wordpress']['db']

if Chef::Config[:solo]
  dbsecure = node['wordpress']['db']
else
  chef_vault_secret node['wordpress']['vault']['item_name'] do
    data_bag node['wordpress']['vault']['data_bag']
    admins node['wordpress']['vault']['admins']
    clients "name:#{node['fqdn']}"
    search "name:#{node['fqdn']}"
    raw_data('root_password' => db['root_password'].nil? ? random_password : db['root_password'],
             'pass' => db['pass'].nil? ? random_password : db['pass'])
    action :nothing
  end.run_action(:create_if_missing)

  dbsecure = chef_vault_item(node['wordpress']['vault']['data_bag'], node['wordpress']['vault']['item_name'])
end

if is_local_host? db['host']

  # The following is required for the mysql community cookbook to work properly
  include_recipe 'selinux::disabled' if node['platform_family'] == 'rhel'

  mysql_service db['instance_name'] do
    port db['port']
    version db['mysql_version']
    initial_root_password dbsecure['root_password']
    action [:create, :start]
  end

  socket = "/var/run/mysql-#{db['instance_name']}/mysqld.sock"

  if node['platform_family'] == 'debian'
    link '/var/run/mysqld/mysqld.sock' do
      to socket
      not_if 'test -f /var/run/mysqld/mysqld.sock'
    end
  elsif node['platform_family'] == 'rhel'
    link '/var/lib/mysql/mysql.sock' do
      to socket
      not_if 'test -f /var/lib/mysql/mysql.sock'
    end
  end

  mysql_connection_info = {
    host: 'localhost',
    username: 'root',
    socket: socket,
    password: dbsecure['root_password'],
  }

  mysql_database db['name'] do
    connection  mysql_connection_info
    action      :create
  end

  mysql_database_user db['user'] do
    connection    mysql_connection_info
    password      dbsecure['pass']
    host          db['host']
    database_name db['name']
    action        :create
  end

  mysql_database_user db['user'] do
    connection    mysql_connection_info
    database_name db['name']
    password      dbsecure['pass']
    privileges    [:all]
    action        :grant
  end

end
