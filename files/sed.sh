#!/usr/bin/env bash

sudo sed -i '25s/\[ ${NETWORKING} = "no" \] && exit 0/\[[ ${NETWORKING} = "no" \]] \&\& exit 0/' /etc/init.d/knockd

sudo sed -i '23a\sleep 30' /etc/init.d/knockd
