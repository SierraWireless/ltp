#!/usr/bin/python
import os
import time
import sys

endline="Hostname:"
PI_IP=sys.argv[1]

print "test machine: "+PI_IP

lastline=0
testend=False
count=0

# sleep for a while before get results
time.sleep(10)
log_file=sys.argv[1]

# print the test results
while True:
    time.sleep(2)
    try:
        f = open(log_file)
        lines=f.readlines()
        totalline=len(lines)
        for i in range(lastline, totalline):
            print lines[i]
            if lines[i].find(endline) >= 0:
                testend=True
        if lastline == totalline:
            count = count+1
        else:
            count = 0
        # it should be failed if no new log produce in 10 minutes
        if count > 300:
            os.system("./mysql_op.sh modify nobody " + PI_IP)
            print PI_IP+" test failed! maybe system crushed."
            sys.exit(1)
        lastline = totalline
        if testend == True:
            break
    except IOError:
        count = count + 1
        if count > 60:
            os.system("./mysql_op.sh modify nobody " + PI_IP)
            print PI_IP+" test failed! maybe system crushed."
            sys.exit(1)
        print "can not read "+log_file

os.system("./mysql_op.sh modify nobody " + PI_IP)

