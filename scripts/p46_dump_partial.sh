#!/bin/sh
set -u
echo "########## 核心 partial: base_bootgrid_table.volt ##########"
cat /usr/local/opnsense/mvc/app/views/layout_partials/base_bootgrid_table.volt | sed 's/^/  /'
