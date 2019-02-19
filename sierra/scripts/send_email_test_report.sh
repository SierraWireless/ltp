#!/bin/bash

YOCTO_VERSION=$1
REPORT_FILE=$2
diff_time=$3

failed_cases=""
fail=$(cat ${REPORT_FILE} | grep FAIL)
if [ "$fail" ]; then
    title="test Fail ${YOCTO_VERSION}! ! !"
    failed_cases="Failed cases: \n$(cat ${REPORT_FILE}|grep FAIL)"
else
    title="test success ${YOCTO_VERSION}"
fi

from_name="LTP_report"
from="ltp_report@autotest.com"

while read line
do
    to="${to}${line} "
done < email.lst

content="Summary: \nTag: ${YOCTO_VERSION} \nElapsed time: ${diff_time} minutes \n$(tail -n 7 ${REPORT_FILE}) \n\n ${failed_cases}\n\nfor more information please refer URL: http://10.22.52.217:8000/ltp-backup/${YOCTO_VERSION}"
subject=${title}

echo -e "To: ${title} ${to}\nFrom: \"${from_name}\" <${from}>\nSubject: ${subject}\n\n ${content}" | sendmail -t
