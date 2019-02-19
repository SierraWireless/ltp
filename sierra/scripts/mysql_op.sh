#!/bin/bash

# example
# 1. get all the devices information
# ./mysql_op.sh query

# 2. take/release the raspberry with PI_IP. If username is nobody, it will release raspberry; or else username will take raspberry.
# ./mysql_op.sh modify username PI_IP

touch user_data
chmod 777 user_data
MYSQL="mysql -uroot -p123456 --default-character-set=utf8 -A -N"
if [ $1 = "query" ]; then
    sql="select * from atlas_user_db.devices_deviceinfo"
    result="$($MYSQL -e "$sql")"
    echo -e "$result" > user_data
fi

if [ ${1} = "modify" ]; then
    sql="update atlas_user_db.devices_deviceinfo set username='${2}' where IP='${3}'"
    ${MYSQL} -e "${sql}"
fi

