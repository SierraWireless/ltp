
# flash the images to AR module
adb reboot bootloader
if [ "$?" != "0" ]; then echo "adb error"; exit 1; fi
fastboot flash sierra-dual-system spkg_rw.cwe
if [ "$?" != "0" ]; then echo "failed to  flash spkg_rw.cwe"; exit 1; fi
fastboot erase lefwkro
if [ "$?" != "0" ]; then echo "failed to erase lefwkro"; exit 1; fi
fastboot erase lefwkro2
if [ "$?" != "0" ]; then echo "failed to erase lefwkro2"; exit 1; fi
fastboot erase customer2
if [ "$?" != "0" ]; then echo "failed to erase customer2"; exit 1; fi
fastboot reboot
if [ "$?" != "0" ]; then echo "fastboot reboot failed"; exit 1; fi

count=0
while :
do
    sleep 10s
    feed_back=$(adb get-state)
    if [ "${feed_back}" = "device" ]; then break; fi
    count=$(expr ${count} + 1)
    if [ "${count}" = "10" ]; then exit 1; fi
done

# sleep 5 seconds to wait all the target app stared
sleep 5s

# connect to our company network
nohup adb shell "/etc/init.d/start_QCMAP_ConnectionManager_le stop; udhcpc -i eth0; sleep 1s; udhcpc -i eth0; sleep 1s; mkdir -p /home/root/ltpliteDemo; mount -t nfs -o rw,nolock ${HOST_IP}:${CURRENT_TEST_DIR} /home/root/ltpliteDemo; chmod 777 /tmp/; cd /home/root/ltpliteDemo/; ./runltplite.sh -p -q -l ltpliteResults -o ltplitelog.txt" &


