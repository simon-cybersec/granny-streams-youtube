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
WORKING_DIR=~/.grannys-streams-youtube
mkdir -p $WORKING_DIR

# Working files
RAW_RESPONSE_FILE=$WORKING_DIR/raw_response_file.txt
CLEAN_RESPONSE_FILE=$WORKING_DIR/clean_response_file.txt
LOGFILE=$WORKING_DIR/grannyslog.txt

# Default values (NASA livestream). Can be specified in the config file located in at ~/granny-streams-youtube/
CHANNEL_ID="UCLA_DiR1FfKNvjuUpBHmylQ"
LIVESTREAM_URL="https://www.youtube.com/channel/UCLA_DiR1FfKNvjuUpBHmylQ/live"
update_threshold=86400    # 1day
streamday=4 # Stream on Sunday

# Source the config file
CONFIG_FILE=~/.granny-streams-youtube/config
echo "CONFIGFILE=$CONFIG_FILE"
if test -f $CONFIG_FILE ; then
    source $CONFIG_FILE
else
    touch $CONFIG_FILE
fi

# ---------------------------- Start Action ----------------------------



WEEKDAY=$(date +%u)
echo "Weekday: $WEEKDAY"

# Only livestream on sunday
if (( $WEEKDAY == $streamday )); then
    echo -e "[$(date)] Execution...\n" >> $LOGFILE
        
    # 1) get raw data
    curl $LIVESTREAM_URL &> $RAW_RESPONSE_FILE     # Do this once every day. The other code downwards can then also be done on the existing files

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
    
    
    echo "IS_LIVE: $IS_LIVE"
    echo "PLAYABILITY: $PLAYABILITY"
    echo "PLAYABILITY_REASON: $PLAYABILITY_REASON"
    echo "STREAMABILITY: $STREAMABILITY"
    echo "UPCOMING_TIME: $UPCOMING_TIME"
    
    #if (( $UPCOMING_TIME != null )); then   
    if [ ! -z "$UPCOMING_TIME" ]; then
        echo "date_calc: $date_calc"
        
        seconds_left=$(( $UPCOMING_TIME - $(date +%s) ))
        echo "seconds_left: $seconds_left"
        
        if (( $seconds_left < 0 )); then
            echo "YAY.....stream ready to rumble...."
        fi
    fi
    
    # Play livestream
    if [ ! -z "$IS_LIVE" ]; then
        
        # Play stream using mpv. Later on Raspi youse omx or sth else.
        mpv $LIVESTREAM_URL --fs >> $LOGFILE
        
        echo "" >> $LOGFILE
    fi
    
    # Get status
    #youtube-dl --quiet --skip-download $LIVESTREAM_URL &> $LOGFILE    
    
    # could be useful: timeout 2h mpv...
    
    #if (( $? == 1 )); then
        #echo -e "SORRY \n"
        #cat $LOGFILE
        
    echo "[$(date)]"
    echo "Exiting script."

else
    delta=$(( 7-$WEEKDAY ))
    echo "The next stream is in $delta day(s)"
    
    echo -e "[$(date)] It is not a sunday, no stream.\n" >> $LOGFILE
fi


