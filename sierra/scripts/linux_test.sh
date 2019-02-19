#!/bin/bash

# build_env was created by jenkins, it contains TAG_VERSION  RELEASE_BASELINE
source ./build_env

# some definitions
HOST_IP=$(ifconfig eth1 | grep "inet addr:" | cut -f 2 -d ":" | cut -f 1 -d " ")

# get yocto version and HW_TYPE
YOCTO_VERSION=${TAG_VERSION}
ar758x=$(echo ${YOCTO_VERSION} | grep AR758x)
ar759x=$(echo ${YOCTO_VERSION} | grep AR759x)
yocto_22=$(echo ${YOCTO_VERSION} | grep "LXSWI2.2")
yocto_17=$(echo ${YOCTO_VERSION} | grep "LXSWI1.7")

HW_TYPE="invalid"
SPKG_DIR="invalid"
if [ ${ar758x} ]; then
    HW_TYPE="mdm9x28"
elif [ ${ar759x} ]; then
    HW_TYPE="mdm9x40"
else
    exit 1
fi

# get the images to test
HOST_PSSWD="123456"
AUTO_LTP_DIR="$(pwd)"
LTP_ROOT_DIR="${AUTO_LTP_DIR}/../../"
BACKUP_DIR="/home/jenkins/backup-log/ltp-backup"
CURRENT_BACKUP_DIR=${BACKUP_DIR}/${YOCTO_VERSION}
mkdir -p ${CURRENT_BACKUP_DIR}
chmod 777 ${CURRENT_BACKUP_DIR}
mv ${BUILD_ROOT_DIR}/spkg_rw.cwe  ${LTP_ROOT_DIR}/

# create raspberry.sh
touch raspberry.sh
chmod 777 raspberry.sh
echo "#!/bin/bash" > raspberry.sh
echo "" >> raspberry.sh
echo "HOST_IP=$HOST_IP" >> raspberry.sh
echo "CURRENT_TEST_DIR=${LTP_ROOT_DIR}" >> raspberry.sh
cat raspberry_m.sh >>  raspberry.sh
mv raspberry.sh  ${LTP_ROOT_DIR}/raspberry.sh

# replace test file "ltplite"
TEST_FILE="${LTP_ROOT_DIR}/runtest/ltplite"
rm -rf ${TEST_FILE}
if [ "$ar758x" ] && [ "$yocto_22" ]; then
    NEW_TEST_FILE="${AUTO_LTP_DIR}/cases/LXSWI2.2_AR758x_ltplite.lst"
elif [ "$ar758x" ] && [ "$yocto_17" ]; then
    NEW_TEST_FILE="${AUTO_LTP_DIR}/cases/LXSWI1.7_AR758x_ltplite.lst"
elif [ "$ar759x" ] && [ "$yocto_22" ]; then
    NEW_TEST_FILE="${AUTO_LTP_DIR}/cases/LXSWI2.2_AR759x_ltplite.lst"
elif [ "$ar759x" ] && [ "$yocto_17" ]; then
    NEW_TEST_FILE="${AUTO_LTP_DIR}/cases/LXSWI1.7_AR759x_ltplite.lst"
else
    exit 1
fi
cp ${NEW_TEST_FILE} ${TEST_FILE}

# get the raspberry PI
count=0
IS_TEST_CMD_SEND="false"
PI_IP="0.0.0.0"

while :
do
    ./mysql_op.sh query
    while read line
    do
        device_info=$(echo ${line} | grep nobody)
        if [ "${device_info}" ]; then
            PI_IP=$(echo ${device_info} | cut -f 5 -d " ")
            echo $PI_IP
            ssh -o ConnectTimeout=1 -n root@${PI_IP} "cd /opt/rpi/target_info/; source ./get_info.bashrc"
            if [ "$?" != "0" ]; then continue; fi
            scp -o ConnectTimeout=1 -r root@${PI_IP}:/opt/rpi/target_info/device_info.dat ./
            if [ "$?" = "0" ]; then
                hw_type=$(cat device_info.dat | grep ${HW_TYPE})
                echo "hw_type: ${hw_type}"
                echo "HW_TYPE: ${HW_TYPE}"
                if [ "${hw_type}" ]; then
                    echo "start test"
                    ssh -n root@${PI_IP} "cd /opt/; if [ ! -d ltp ]; then mkdir ltp; fi; umount -lf ltp;  mount -o rw ${HOST_IP}:${LTP_ROOT_DIR} ltp; cd ltp/; ./raspberry.sh" &
                    echo "cmd sent"
                    IS_TEST_CMD_SEND="true"
                    break
                fi
            fi
        fi
    done < user_data

    if [ "$IS_TEST_CMD_SEND" = "true" ]; then
        echo "PI_IP : "${PI_IP}
        ./mysql_op.sh modify jenkins ${PI_IP}
        sleep 2m
        echo "test machine is running ... "
        break;
    fi
    echo "waite $count minutes"
    sleep 1m
    # every 20 minutes send a alarm email
    if [ $(expr $count % 20) = 0 ]; then
        ./send_email_alarm.sh
    fi
    count=$(expr $count + 1)
done

# count test time
start_time=$(expr $(date -d "$(date "+%Y-%m-%d %H:%M:%S")" +%s) / 60)

# get the progress
LOG_FILE="${LTP_ROOT_DIR}/results/ltpliteResults"
python ./test_process.py ${LOG_FILE}
if [ "$?" != "0" ]; then exit $?; fi

# count test time
end_time=$(expr $(date -d "$(date "+%Y-%m-%d %H:%M:%S")" +%s) / 60)
diff_time=$(expr ${end_time} - ${start_time})

# release raspberry
./mysql_op.sh modify nobody ${PI_IP}

# backup log
MNT_DIR="/home/jenkins/mnt"
cp ${LOG_FILE}   ${CURRENT_BACKUP_DIR}
cp ${LTP_ROOT_DIR}/testcases/bin/ltplitelog.txt   ${CURRENT_BACKUP_DIR}
echo 123456 | sudo -S python3 result_save.py ${YOCTO_VERSION} ${MODEM_VERSION} ${diff_time} ${MNT_DIR} ${LOG_FILE}

echo "test time: ${diff_time} minutes"
echo "you can find test log in following links:"
echo "http://10.22.52.217:8000/ltp-backup/${YOCTO_VERSION}"

# send report email
REPORT_FILE=${CURRENT_BACKUP_DIR}/ltpliteResults
./send_email_test_report.sh ${YOCTO_VERSION} ${REPORT_FILE} ${diff_time}

echo "TEST DONE"
exit 0

