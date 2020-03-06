#!/usr/bin/env bash
# Licensed to the SkyAPM under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash

set -e

var_application_file="/var/nginx/conf.d/nginx.conf"

var_upstream_ip=$(cat /etc/hosts|grep upstream|awk '{print $1'})

apt-get update && apt-get -y install git

echo 'git clone skyalking-nginx-lua lib from https://github.com/apache/skywalking-nginx-lua.git'

git clone https://github.com/apache/skywalking-nginx-lua.git /usr/share/skywalking-nginx-lua \
  && cd /usr/share/skywalking-nginx-lua \
  && git checkout ${SKYWALKING_NINGX_LUA_GIT_COMMIT_ID} \
  && ls ./ \
  && mkdir -p /var/nginx/conf.d


generateNginxConf() {
     cat <<EOT >> ${var_application_file}
worker_processes  1;
daemon off;
error_log /dev/stdout error;

events {
    worker_connections 1024;
}
http {
    lua_package_path "/usr/share/skywalking-nginx-lua/lib/skywalking/?.lua;;";
    # Buffer represents the register inform and the queue of the finished segment
    lua_shared_dict tracing_buffer 100m;

    # Init is the timer setter and keeper
    # Setup an infinite loop timer to do register and trace report.
    init_worker_by_lua_block {
        local metadata_buffer = ngx.shared.tracing_buffer

        metadata_buffer:set('serviceName', 'User_Service_Name')
        -- Instance means the number of Nginx deloyment, does not mean the worker instances
        metadata_buffer:set('serviceInstanceName', 'User_Service_Instance_Name')

        require("client"):startBackendTimer("http://${var_upstream_ip}:12800")
    }
    log_format sw_trace escape=json "$uri $request_body";

    server {
        listen 8080;

        location /nginx/e2e/health-check {

            rewrite_by_lua_block {
                require("tracer"):start("User_Service_Name")
            }

            proxy_pass http://upstream:9090/e2e/health-check;

            body_filter_by_lua_block {
                require("tracer"):finish()
            }

            log_by_lua_block {
                require("tracer"):prepareForReport()
            }
        }
    }
}
EOT
}

generateNginxConf;

echo 'generated nginx.conf:'

cat ${var_application_file}

/usr/bin/openresty -c ${var_application_file}
sync