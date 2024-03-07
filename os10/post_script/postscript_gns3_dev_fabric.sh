#!/bin/bash

## Set SFDMODE to 1 converts switch to SFD managed, set to 0 puts in normal mode
MGTPREFIX="192.168.1"
MGTNET=0
TFTP_HOST=1
declare -i GW=$MGTNET+1
MGTMASK="/24"
TFTPSERVER="${MGTPREFIX}.${TFTP_HOST}"
TFTP_PATH="tftpboot"
CALLBACK_PATH="callback"
STAGING_FINISHED=/ztp_finished
OOB_INT=eth0
USER_NAME=admin
TMP=/tmp
HOME=/home
ADMIN_HOME="${HOME}/${USER_NAME}"
PASSWORD=admin
MGMT_IP=localhost
APP=https://
GREP=`type -tP grep`
CURL=`type -tP curl`
SED=`type -tP sed`
ZTD_LOGFILE=post_script.log
LOG=$TMP/$ZTD_LOGFILE
ZTP_HOSTNAME="ZTP_NO_NAME_FOUND"
ZTPFINISH="_ztp.finished"


## Find DHCP client IP received
DHCP_IP=`grep fixed-address /var/lib/dhcp/dhclient.eth0.leases | tail -1 | sed 's/.* //g' | sed 's/;//'`

echo "DHCP IP Address received : $DHCP_IP" 2>&1 | tee -a $LOG && sleep 2
echo "gateway received : $GW" 2>&1 | tee -a $LOG && sleep 2

## Extract the mac address of the switch
MAC=`ip link show eth0 | grep -o -P "(?<=ether ).*(?= brd)" | sed 's/:/_/g'`

echo "MAC address switch mgt interface : $MAC" 2>&1 | tee -a $LOG && sleep 2

echo "Fetching file $MAC.txt to discover my hostname..." 2>&1 | tee -a $LOG && sleep 2

if hostname=`curl -s -f --interface ${OOB_INT} http://${TFTPSERVER}/${TFTP_PATH}/${CALLBACK_PATH}/${MAC}.txt`
   then
      echo "Succesfully found hostname : $hostname" 2>&1 | tee -a $LOG
      SWITCHNAME=$hostname
   else
      SWITCHNAME=$ZTP_HOSTNAME
      echo "Did not find hostname for mac $MAC, hostname will be : $SWITCHNAME" 2>&1 | tee -a $LOG
fi

sleep 2

## Set hostname
echo "Configuring hostname $SWITCHNAME via API..." 2>&1 | tee -a $LOG && sleep 2
apicall=`curl -f -s -i -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d'{"dell-system:system":{"hostname": "'"$SWITCHNAME"'" }}' -X PATCH $APP$MGMT_IP/restconf/data/dell-system:system`

## Save config
apicall=`curl -f -s -i -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d '{"yuma-netconf:input":{"target":{"startup":[null]},"source":{"running":[null]}}}' -X POST $APP$MGMT_IP/restconf/operations/copy-config`

## Upload ZTP staging complete file to web server
ZTPFINISHFILE=`echo ${DHCP_IP}`${ZTPFINISH}
echo $SWITCHNAME > $TMP/${ZTPFINISHFILE} 
$CURL --interface $OOB_INT -T $TMP/$ZTPFINISHFILE tftp://${TFTPSERVER}${STAGING_FINISHED}/${ZTPFINISHFILE} 2>&1 | tee -a $LOG
echo "ZTP has finished. Uploading file '$ZTPFINISHFILE' to server 'tftp://${TFTPSERVER}${STAGING_FINISHED}/${ZTPFINISHFILE}'" 2>&1 | tee -a $LOG && sleep 2


