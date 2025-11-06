#!/bin/bash

ARG=$1

chmod +x ./$ARG
./$ARG

bash ./installation_common.sh
bash ./installation_blitz.sh
bash ./installation_autobahn.sh

mkdir -p /opt/blitz/

bash ./post_install.sh