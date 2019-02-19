1. these scripts are used by Jenkins to have a Linux test.
2. when submit on gerrit, it will trigger Jenkins to build the project and then call these test scripts.
3.the entry script is linux_test.sh. It is called by Jenkins. The Script on Jenkins as below:
#!/bin/bash


cd $WORKSPACE
mkdir $BUILD_ID
cd $BUILD_ID

# Get tag version
git clone git://cnshz-er-git01/manifest

if ! [ -e $WORKSPACE/$BUILD_ID/manifest ]; then
    echo "Clone manifest failed."
    exit 1
fi
cd $WORKSPACE/$BUILD_ID/manifest


# Auto trigger by gerrit event from https://gerrit-legato
GERRIT_REFSPEC=${GERRIT_REFSPEC:-refs/heads/master}
if [ -z $TAG_VERSION ]; then
    if [ -z $GERRIT_REFSPEC ]; then
        echo "GERRIT_REFSPEC can not be null."
        exit 1
    fi
    echo "Come to GIT FETCH!!!"
    git fetch ssh://aouyang@gerrit-legato:29418/manifest $GERRIT_REFSPEC
    git checkout FETCH_HEAD
    TAG_VERSION=$(git diff-tree --no-commit-id --name-only -r HEAD | head -1 | cut -d'/' -f3 | sed 's/.xml//g')
fi

if [ -z $TAG_VERSION ]; then
    echo "Failed to get TAG_VERSION."
    exit 1
fi

MODEM_VERSION=$(cat $WORKSPACE/$BUILD_ID/manifest/mdm9x28/tags/${TAG_VERSION}.xml | grep amss | cut -d'/' -f3)

cd $WORKSPACE/$BUILD_ID/

echo "TAG_VERSION:"$TAG_VERSION
echo "WORKSPACE:"$WORKSPACE
echo "MODEM_VERSION=$MODEM_VERSION"


echo "export TAG_VERSION=$TAG_VERSION" > $WORKSPACE/$BUILD_ID/build_env
echo "export WORKSPACE=$WORKSPACE" >> $WORKSPACE/$BUILD_ID/build_env
echo "export MODEM_VERSION=$MODEM_VERSION" >> $WORKSPACE/$BUILD_ID/build_env
echo "export BUILD_ROOT_DIR=$(pwd)" >> $WORKSPACE/$BUILD_ID/build_env


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
    SPKG_DIR="core_4k"
elif [ ${ar759x} ]; then
    HW_TYPE="mdm9x40"
    SPKG_DIR="core"
else
    exit 1
fi

YOCTO_IMG_PATH="http://get.legato.sierrawireless.local/${HW_TYPE}/tags/${YOCTO_VERSION}/${SPKG_DIR}/spkg_rw.cwe"
LTP_PKG_PATH="http://get.legato.sierrawireless.local/${HW_TYPE}/tags/${YOCTO_VERSION}/build/yocto/tar/ltp.tar.bz2"

# download spkg_rw.cwe and ltp.tar.bz2
count=0
while :
do
    echo "count: ${count}"
    axel -n 9 -a ${YOCTO_IMG_PATH}
    if [ "$?" != "0" ]; then
        if [ "${count}" = "9" ]; then
            exit 1;
        fi
    else
        break;
    fi
    count=$(expr ${count} + 1)
    sleep 10m
done

axel -n 9 -a ${LTP_PKG_PATH}
if [ "$?" != "0" ]; then exit $?; fi
tar -xjf ltp.tar.bz2
if [ "$?" != "0" ]; then exit $?; fi

# run test scripts
mv build_env  opt/ltp/sierra/scripts/
cd opt/ltp/sierra/scripts/
./linux_test.sh
exit $?

