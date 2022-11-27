#! /bin/bash

# Dependencies
#
# jq
# mpv
# youtube-dl (currently not)
# git (currently not)

echo "------------------------------"
echo ">>> Granny streams YouTube <<<"
echo "------------------------------"

# ------------------------ What the script does ------------------------
# This script is executed by a cronjob every sunday at 9:30am.
# At first it checks for the correct day and time.
# Then it checks for a running livestream every minute for ten minutes.
# Then it plays the livestream. If there is no livestream it checks
# again at 11:00am.
# 
# ----------------------------------------------------------------------


# ----------------------- Checks And Preparation -----------------------

# Check for required packages:
#echo -e "\nChecking required packages..."
#packages='jq mpv git youtube-dl'
#CHECK_BAD=0
#
#for pkg in $packages; do
#    status="$(dpkg-query -W --showformat='${db:Status-Status}' "$pkg" 2>&1)"
#    if [ ! "$status" = installed ]; then
#        echo -e "-- $pkg: missing"
#        CHECK_BAD=1
#    else
#        echo -e "-- $pkg: o.k. "
#    fi
#done
#
#if [ $CHECK_BAD == 1 ]; then
#    echo -e "Please install the missing package(s)."
#    exit
#fi


# Create (hidden) working direcectory in homefolder
WORKING_DIR=~/.granny-streams-youtube
mkdir -p $WORKING_DIR

# Working files
RAW_RESPONSE_FILE=$WORKING_DIR/raw_response_file.txt
CLEAN_RESPONSE_FILE=$WORKING_DIR/clean_response_file.txt
LOGFILE=$WORKING_DIR/grannyslog.txt
echo -e "[+] Logfile: $LOGFILE"

# Default values (NASA livestream). Can be specified in the config file located in at ~/granny-streams-youtube/
CHANNEL_ID="UCLA_DiR1FfKNvjuUpBHmylQ"
LIVESTREAM_URL="https://www.youtube.com/channel/UCLA_DiR1FfKNvjuUpBHmylQ/live"
update_threshold=86400    # 1day
streamday=7 # Stream on Sunday

# Source the config file. This overrides the CHANNEL_ID and LIVESTREAM_URL etc.
CONFIG_FILE=~/.granny-streams-youtube/config

echo "CONFIGFILE=$CONFIG_FILE" >> $LOGFILE
if test -f $CONFIG_FILE ; then
    source $CONFIG_FILE
    
    echo -e "[$(date)] CHANNEL_ID = $CHANNEL_ID" >> $LOGFILE
    echo -e "[$(date)] LIVESTREAM_URL = $LIVESTREAM_URL" >> $LOGFILE
else
    touch $CONFIG_FILE
fi


# ---------------------------- Start Action ----------------------------


WEEKDAY=$(date +%u)
start_hour=5
start_min=31

stop_hour=10
stop_min=45

# Only livestream on sunday
if (( $WEEKDAY == $streamday )); then
    echo -e "[$(date)] It is sunday." >> $LOGFILE
    
    # Check time and sleep if needed, otherwise play livestream
    GO=1
    while [ $GO == 1 ]
    do
        HOUR=$(date +"%_H")
        MIN=$(date +"%_M")
        echo -e "[$(date)] $HOUR:$MIN" >> $LOGFILE
    
        # Check hour
        if [[ $HOUR -ge $start_hour ]]; then

            # Check minute
            if [[ $MIN -ge $start_min ]]; then
                echo -e "[$(date)] Time is ready. Request..." >> $LOGFILE
        
                # 1) get raw data
                curl $LIVESTREAM_URL &> $RAW_RESPONSE_FILE

                # 2) clean up and format
                cat $RAW_RESPONSE_FILE | sed -n 's/.*var ytInitialPlayerResponse = \({[^<]*}\);.*/\1/p' | jq -r . > $CLEAN_RESPONSE_FILE

                # 3) get data

                # If `videoDetails.isLive` exists, it should be on live, when a video
                # is not live (normal videos, and even upcoming streams) this key will be missing and jq will
                # return `null`
                IS_LIVE=$(cat $CLEAN_RESPONSE_FILE | jq -r '.videoDetails.isLive | select(.!=null)')

                # This status will always return:
                # - `OK` for live streams, private streams, or normal videos,
                # - `LIVE_STREAM_OFFLINE` for offline channel
                PLAYABILITY=$(cat $CLEAN_RESPONSE_FILE | jq -r '.playabilityStatus.status | select(.!=null)')

                # You will get some playability reasons for:
                # - `Offline` for streams are not live
                # - `This live event will begin in {n} hours.` for upcoming streams, you can also get specific
                #   UNIX timestamp with .scheduledStartTime (see below)
                # - `null` (this key will be missing) for:
                #   - On live streams or private streams
                #   - Non-streaming content
                PLAYABILITY_REASON=$(cat $CLEAN_RESPONSE_FILE | jq -r '.playabilityStatus.reason | select(.!=null)')

                # When the streamer is streaming privately, this key will be empty
                STREAMABILITY=$(cat $CLEAN_RESPONSE_FILE | jq -r '.playabilityStatus.liveStreamability.liveStreamabilityRenderer.videoId | select(.!=null)')

                # Get upcoming time when available
                # This key will be missing if no upcoming events available
                UPCOMING_TIME=$(cat $CLEAN_RESPONSE_FILE | jq -r '.playabilityStatus.liveStreamability.liveStreamabilityRenderer.offlineSlate.liveStreamOfflineSlateRenderer.scheduledStartTime | select(.!=null)')
                if [ ! -z "$UPCOMING_TIME" ]; then
                    date_calc=`date -d @$UPCOMING_TIME`
                fi

                # Get video ID
                VIDEO_ID=$(cat $CLEAN_RESPONSE_FILE | jq -r '.videoDetails.videoId')
                
                
                echo -e "[$(date)] IS_LIVE: $IS_LIVE" >> $LOGFILE
                echo -e "[$(date)] PLAYABILITY: $PLAYABILITY" >> $LOGFILE
                echo -e "[$(date)] PLAYABILITY_REASON: $PLAYABILITY_REASON" >> $LOGFILE
                echo -e "[$(date)] STREAMABILITY: $STREAMABILITY" >> $LOGFILE
                echo -e "[$(date)] UPCOMING_TIME: $UPCOMING_TIME" >> $LOGFILE
                
                #if (( $UPCOMING_TIME != null )); then   
                if [ ! -z "$UPCOMING_TIME" ]; then
                    echo -e "[$(date)] date_calc: $date_calc" >> $LOGFILE
                    
                    seconds_left=$(( $UPCOMING_TIME - $(date +%s) ))
                    echo -e "[$(date)] seconds_left: $seconds_left" >> $LOGFILE
                    
                    if (( $seconds_left < 0 )); then
                        echo -e "[$(date)] Seconds left are less than zero." >> $LOGFILE
                    else
                        echo -e "[$(date)] seconds left are greater than zero." >> $LOGFILE
                    fi
                
                fi
                
                # Play livestream
                if [ ! -z "$IS_LIVE" ]; then
                    echo -e "[$(date)] Starting player..." >> $LOGFILE
                    
                    # Play stream using mpv. Later on Raspi youse omx or sth else.
                    mpv $LIVESTREAM_URL --fs >> $LOGFILE 2>/dev/null
                    
                    echo "" >> $LOGFILE
                    
                else
                    echo -e "[$(date)] No live stream. (IS_LIVE = null). Sleeping..." >> $LOGFILE             
                    sleep 1m
                fi
                
                # Get status
                #youtube-dl --quiet --skip-download $LIVESTREAM_URL &> $LOGFILE    
                
                # could be useful: timeout 2h mpv...
                
                #if (( $? == 1 )); then
                    #echo -e "SORRY \n"
                    #cat $LOGFILE
                    
                if [[ $HOUR -ge $stop_hour ]]; then                
                    if [[ $MIN -ge $stop_min ]]; then
                        echo -e "[$(date)] Its time to stop. Exiting... \n"
                        exit
                    fi                
                fi
                    
                echo -e "[$(date)] Bottom of while loop checking request. \n" >> $LOGFILE
                
            else
                echo -e "[$(date)] Its too early (Min). Sleep..." >> $LOGFILE
                sleep 1m
            fi
        
        else
            echo -e "[$(date)] Its before 9 am. Exiting... \n" >> $LOGFILE
            exit
        fi
        
        
    done

else
    delta=$(( 7-$WEEKDAY ))
    echo -e "[$(date)] The next stream is in $delta day(s). Exiting... \n" >> $LOGFILE
fi


