#!/bin/bash

from_name="LTP(WARNING !!!)"
from="ltp@autotest.com"
to="<aouyang@sierrawireless.com>"
title="LTP test Mail"
content="here is lack of resources to Linux Test, please have a check"
subject="LTP WARNING !!!"

echo -e "To: \"${title}\" <${to}>\nFrom: \"${from_name}\" <${from}>\nSubject: ${subject}\n\n ${content}" | sendmail -t
