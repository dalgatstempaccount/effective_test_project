#!/bin/bash
# I used mockoon (free and open source) to emulate HTTP API ( therefore localhost:3000/status ) and created /status route in mockoon
# and changed request type to POST to send process' status
# wget https://github.com/mockoon/mockoon/releases/download/v9.0.0/mockoon-9.0.0.amd64.deb
SLEEP_INTERVAL=60
PROCESS_NAME="nano"
PROCESS_ID=""
START_TIME=""
LOG_FILE_LOCATION="/var/log/monitoring.log"
SYSTEMD_DIR="/etc/systemd/system"
API_ENDPOINT="http://localhost:3000/status"
SCRIPT_NAME=${0##*/}
SYSTEM_SERVICE_FILE_PATH="${SYSTEMD_DIR}/$( echo $SCRIPT_NAME | sed 's/.sh/.service/')"

# Checking if log file exists, if not creating the logfile
if [ ! -f $LOG_FILE_LOCATION ]; then
    echo "Log file not found!"
    touch $LOG_FILE_LOCATION
    echo "$(date +"%d-%m-%y %T") info: log file was created" >> $LOG_FILE_LOCATION
    echo "Log file was created"
fi

 # Creating unit file for systemd and enabling the service
 if [ ! -f  $SYSTEM_SERVICE_FILE_PATH ]; then
    echo "Systemd startup service file not found!"
    touch $SYSTEM_SERVICE_FILE_PATH
    echo "[Unit]
    Description=Simple watchdog for ${PROCESS_NAME}
    After=network.target
    [Service]
    Type=simple
    ExecStart=$(pwd)/${0}
    [Install]
    WantedBy=multi-user.target" | sed "s/^[ \t]*//" > $SYSTEM_SERVICE_FILE_PATH
    systemctl enable $( echo $SCRIPT_NAME | sed 's/.sh/.service/')
    systemctl daemon-reload
    echo "$(date +"%d-%m-%y %T") info: systemd unit file ${SYSTEM_SERVICE_FILE_PATH} was created" >> $LOG_FILE_LOCATION
fi

#Checking if curl is installed ( and installing it for Debian based systems )
if [ -z  "$(which curl)" ]; then
    echo "Curl is not found! Installing curl to continue"
    apt-get update
    apt-get install -y curl
    echo "$(date +"%d-%m-%y %T") info: Curl was installed" >> $LOG_FILE_LOCATION
fi

#  Main loop.
while true 
do
    PROCESS_ID=$(ps -eo pid,lstart,cmd | grep ${PROCESS_NAME} | grep -v grep | awk '{print $1;}' )
    HTTP_RESPONSE_CODE=""
    if [ -z $PROCESS_ID ]; then
        echo "$(date +"%d-%m-%y %T") error: process ${PROCESS_NAME} is not running" >> $LOG_FILE_LOCATION
        # Sending message that process is not running
        HTTP_RESPONSE_CODE=$(curl --header "Content-Type: application/json"\
         --request POST --data '{"process":"'$PROCESS_NAME'","status":"dead"}'\
        -s -o /dev/null -w "%{http_code}" $API_ENDPOINT )

    else
        CURRENT_START_TIME=$(ps -p $PROCESS_ID -wo lstart | awk 'NR==2')
        
        if [[ "$START_TIME" != "$CURRENT_START_TIME" ]] && [[ -n "$START_TIME" ]]; then
            echo "$(date +"%d-%m-%y %T") error: The process ${PROCESS_NAME} was restarted at ${CURRENT_START_TIME}" >> $LOG_FILE_LOCATION
        fi
        START_TIME=$CURRENT_START_TIME
        # Sending message that process is running
        HTTP_RESPONSE_CODE=$(curl --header "Content-Type: application/json"\
         --request POST --data '{"process":"'$PROCESS_NAME'","status":"alive"}'\
        -s -o /dev/null -w "%{http_code}" $API_ENDPOINT)
    fi
    if [ $HTTP_RESPONSE_CODE == "200" ]; then
        true
    elif [ $HTTP_RESPONSE_CODE == "000" ]; then
        echo "$(date +"%d-%m-%y %T") error: API endpoint ${API_ENDPOINT} is down or inaccessible" >> $LOG_FILE_LOCATION
    else
        echo "$(date +"%d-%m-%y %T") error: Bad HTTP request. HTTP response code: ${HTTP_RESPONSE_CODE}" >> $LOG_FILE_LOCATION
    fi
    sleep $SLEEP_INTERVAL
done