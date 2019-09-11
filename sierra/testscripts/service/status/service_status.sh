#!/bin/sh

# get the services status
systemctl --failed > tmp_data_file

# output the status to log file
cat tmp_data_file

# check whether there is failed service
status=$(cat tmp_data_file | grep failed)
rm -rf tmp_data_file
if [ status != "" ]; then exit 3; fi
exit 0
