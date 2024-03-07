#!/bin/bash

## Set SFDMODE to 1 converts switch to SFD managed, set to 0 puts in normal mode
MGTPREFIX="192.168.1"
MGTNET=0
TFTP_HOST=1
declare -i GW=$MGTNET+1
GW_IP=$MGTPREFIX.$GW
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
DHCP_IP=`grep fixed-address /var/lib/dhcp/dhclient.${OOB_INT}.leases | tail -1 | sed 's/.* //g' | sed 's/;//'`
IP_AND_MASK=$DHCP_IP$MGTMASK

echo "DHCP IP Address received : $DHCP_IP" 2>&1 | tee -a $LOG && sleep 2
echo "gateway received : $GW" 2>&1 | tee -a $LOG && sleep 2
echo "gateway IP is: $IP_AND_MASK" 2>&1 | tee -a $LOG && sleep 2

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

## Upload ZTP staging complete file to web server
## this needs to be done before the management interface is moved into vrf
ZTPFINISHFILE=`echo ${DHCP_IP}`${ZTPFINISH}
echo $SWITCHNAME > $TMP/${ZTPFINISHFILE}
echo "Uploading file '$ZTPFINISHFILE' to server 'tftp://${TFTPSERVER}${STAGING_FINISHED}/${ZTPFINISHFILE}'" 2>&1 | tee -a $LOG && sleep 2
$CURL -s -f --interface $OOB_INT -T $TMP/$ZTPFINISHFILE tftp://${TFTPSERVER}${STAGING_FINISHED}/${ZTPFINISHFILE} 2>&1 | tee -a $LOG

## Delete dhcp setting from config
echo "Delete DHCP configuration from OOB mgt interface..." && sleep 2
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -X DELETE $APP$MGMT_IP/restconf/data/ietf-interfaces:interfaces/interface=mgmt1%2F1%2F1/dell-ip:ipv4/dell-ip:dhcp-config

## Delete ip config from interface
echo "Delete IPv4 config from management interface..." && sleep 2
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -X DELETE https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces/interface=mgmt1%2F1%2F1/dell-ip:ipv4/dell-ip:dhcp-config
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -X DELETE https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces/interface=mgmt1%2F1%2F1/dell-ip:ipv4/dell-ip:address


## Delete all IPv6 config from interface
echo "Delete IPv6 config from management interface..." && sleep 2
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -X DELETE https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces/interface=mgmt1%2F1%2F1/dell-ip:ipv6/dell-ip:autoconfig
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -X DELETE https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces/interface=mgmt1%2F1%2F1/dell-ip:ipv6/dell-ip:dhcp-config
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -X DELETE https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces/interface=mgmt1%2F1%2F1/dell-ip:ipv6/dell-ip:link-local-addr
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -X DELETE https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces/interface=mgmt1%2F1%2F1/dell-ip:ipv6/dell-ip:site-local-addr
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -X DELETE https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces/interface=mgmt1%2F1%2F1/dell-ip:ipv6/dell-ip:ipv6-addresses
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d '{"ietf-interfaces:interfaces":{"interface":[{"name":"mgmt1/1/1","dell-ip:ipv6":{"autoconfig":false,"dhcp-config":{"is-dhcp":false}}}]}}' -X PATCH https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d '{"ietf-interfaces:interfaces":{"interface":[{"name":"mgmt1/1/1","dell-ip:ipv6":{"intf-v6-enabled":true}}]}}' -X PATCH https://$MGMT_IP/restconf/data/ietf-interfaces:interfaces

echo "Management interface is now default..."  2>&1 | tee -a $LOG && sleep 2

echo "Release DHCP IP address..."  2>&1 | tee -a $LOG && sleep 2
sudo dhclient -r $OOB_INT

echo "Create management vrf..."  2>&1 | tee -a $LOG && sleep 2
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d '{"dell-vrf:vrf-config":{"vrf":[{"vrf-name":"management"}]}}' -X PATCH https://$MGMT_IP/restconf/data/dell-vrf:vrf-config

echo "Add management interface to vrf..."  2>&1 | tee -a $LOG && sleep 2
curl -i -f -s -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d '{"dell-vrf:vrf-config":{"vrf":[{"vrf-name":"management","auto-move":true}]}}' -X PATCH https://$MGMT_IP/restconf/data/dell-vrf:vrf-config

## Set mgmt address fixed in config
echo "Configure IP address $DHCP_IP on OOB mgt interface..."  2>&1 | tee -a $LOG && sleep 2
apicall=`curl -f -s -i -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d'{"ietf-interfaces:interfaces":{"interface":[{"name":"mgmt1/1/1","dell-ip:ipv4":{"address":{"primary-addr":"'"$IP_AND_MASK"'" }}}]}}' -X PATCH $APP$MGMT_IP/restconf/data/ietf-interfaces:interfaces`

sleep 5

echo "Configure default route in management vrf, Gateways IP : $GW_IP..."  2>&1 | tee -a $LOG && sleep 2
#apicall=`curl -f -s -i -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d '{"dell-management-routing:ipv4-mgmt-routes":{"route":[{"destination-prefix":"0.0.0.0/0","forwarding-router-address":"'"$GW_IP"'"}]}}' -X PATCH https://$MGMT_IP/restconf/data/dell-management-routing:ipv4-mgmt-routes`

## Create scriptfile to execute with clish
## This is a workaround cause API call does not work to add a management route
cat <<EOT > $TMP/clish_os10_script.txt
configure terminal
management route 0.0.0.0/0 $GW_IP
EOT

sleep 2

clish -qB $TMP/clish_os10_script.txt 2>&1 | tee -a $LOG

sleep 2

## Set hostname
echo "Configuring hostname $SWITCHNAME via API..." 2>&1 | tee -a $LOG && sleep 2
apicall=`curl -f -s -i -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d'{"dell-system:system":{"hostname": "'"$SWITCHNAME"'" }}' -X PATCH $APP$MGMT_IP/restconf/data/dell-system:system`

apicall=`curl -f -s -i -k -H "Accept: application/json" -H "Content-Type: application/json" -u $USER_NAME:$PASSWORD -d '{"yuma-netconf:input":{"target":{"startup":[null]},"source":{"running":[null]}}}' -X POST https://$MGMT_IP/restconf/operations/copy-config`

echo "Finished ZTP staging." 2>&1 | tee -a $LOG 

