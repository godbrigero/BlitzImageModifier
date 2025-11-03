#!/bin/bash


DEFAULT_PI_NAME="blitz-pi-random-name-1234"

cd ~/Documents

git clone https://github.com/PinewoodRobotics/B.L.I.T.Z.git
cd B.L.I.T.Z
git submodule update --init --recursive

bash scripts/install.sh --name "$DEFAULT_PI_NAME"
