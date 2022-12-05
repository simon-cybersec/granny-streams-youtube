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



# ----------------------------- USER INPUT -----------------------------
# NOTE Here you can define the channelID you want to stream from.
#      This is the NASA livestream.
CHANNEL_ID="UCLA_DiR1FfKNvjuUpBHmylQ"

# NOTE Here you can define the day of week you want to stream.
#      Monday = 1; Sunday=7
streamday=1

# NOTE Here you can define the time the script will start to check for
#      a running stream and the time the script will automatically stop.
start_hour=9
start_min=30
stop_hour=10
stop_min=45



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


# Check/create (hidden) working direcectory in homefolder
WORKING_DIR=~/.granny-streams-youtube
mkdir -p $WORKING_DIR

# Defining files to work with
RAW_RESPONSE_FILE=$WORKING_DIR/raw_response_file.txt
CLEAN_RESPONSE_FILE=$WORKING_DIR/clean_response_file.txt
LOGFILE=$WORKING_DIR/grannyslog.txt
echo -e "[+] Logfile: $LOGFILE"

# Source the config file (for example to override the CHANNEL_ID and LIVESTREAM_URL etc.
CONFIG_FILE=~/.granny-streams-youtube/config
echo "CONFIGFILE=$CONFIG_FILE" >> $LOGFILE

if test -f $CONFIG_FILE ; then
    source $CONFIG_FILE
fi
# Default values (NASA livestream). Can be specified in the config file located in at ~/granny-streams-youtube/
LIVESTREAM_URL="https://www.youtube.com/channel/$CHANNEL_ID/live"
REJECT_COOKIE="SOCS=CAESEwgDEgk0OTEzMjUyMTcaAmVuIAEaBgiA3Z-cBg"

echo -e "[$(date)] CHANNEL_ID = $CHANNEL_ID" >> $LOGFILE
echo -e "[$(date)] LIVESTREAM_URL = $LIVESTREAM_URL" >> $LOGFILE
echo -e "[$(date)] STREAMDAY = $streamday" >> $LOGFILE
echo -e "[$(date)] start_hour = $start_hour" >> $LOGFILE
echo -e "[$(date)] start_min = $start_min" >> $LOGFILE
echo -e "[$(date)] stop_hour = $stop_hour" >> $LOGFILE
echo -e "[$(date)] stop_min = $stop_min" >> $LOGFILE


# ---------------------------- Start Action ----------------------------

# Current day of week
CURRENT_WEEKDAY=$(date +%u)

# Check for correct day of week
if (( $CURRENT_WEEKDAY == $streamday )); then
    echo -e "[$(date)] Weekday is correct." >> $LOGFILE
    
    # Check for correct time otherwise sleep. If correct try to play livestream
    GO=1
    BAD_COUNTER=0
    while [ $GO == 1 ]
    do
        CURRENT_HOUR=$(date +"%_H")
        CURRENT_MIN=$(date +"%_M")
        echo -e "[$(date)] $CURRENT_HOUR:$CURRENT_MIN" >> $LOGFILE
    
        # Check hour
        if [[ $CURRENT_HOUR -ge $start_hour ]]; then

            # Check minute
            if [[ $CURRENT_MIN -ge $start_min ]]; then
                echo -e "[$(date)] Time is ready. Make request..." >> $LOGFILE
        
                # 1) get raw data
                curl $REJECT_COOKIE $LIVESTREAM_URL &> $RAW_RESPONSE_FILE

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
                SCEDULED_TIME=$(cat $CLEAN_RESPONSE_FILE | jq -r '.playabilityStatus.liveStreamability.liveStreamabilityRenderer.offlineSlate.liveStreamOfflineSlateRenderer.scheduledStartTime | select(.!=null)')
                if [ ! -z "$SCEDULED_TIME" ]; then
                    date_calc=`date -d @$SCEDULED_TIME`
                    echo -e "[$(date)] date_calc: $date_calc" >> $LOGFILE
                    
                    seconds_left=$(( $SCEDULED_TIME - $(date +%s) ))
                    echo -e "[$(date)] seconds_left: $seconds_left" >> $LOGFILE
                fi

                # Get video ID
                VIDEO_ID=$(cat $CLEAN_RESPONSE_FILE | jq -r '.videoDetails.videoId')
                
                echo -e "[$(date)] IS_LIVE: $IS_LIVE" >> $LOGFILE
                echo -e "[$(date)] PLAYABILITY: $PLAYABILITY" >> $LOGFILE
                echo -e "[$(date)] PLAYABILITY_REASON: $PLAYABILITY_REASON" >> $LOGFILE
                echo -e "[$(date)] STREAMABILITY: $STREAMABILITY" >> $LOGFILE
                echo -e "[$(date)] SCEDULED_TIME: $SCEDULED_TIME" >> $LOGFILE

                
                # If livestream is running play it. Otherwise sleep.
                if [ ! -z "$IS_LIVE" ]; then
                    echo -e "[$(date)] Starting player..." >> $LOGFILE
                    
                    # Play stream using mpv. Later on Raspi youse omx or sth else.
                    mpv $LIVESTREAM_URL --fs >> $LOGFILE 2>/dev/null
                    
                    # If mpv cannot load stream it exits and script will go on infinetly. BAD_COUNTER will prevent this.
                    # TODO: closing omx manually will increment BAD_COUNTER to...
                    BAD_COUNTER=$(( $BAD_COUNTER + 1 ))
                    echo -e "[$(date)] BAD_COUNTER: $BAD_COUNTER" >> $LOGFILE                    
                    if (( $BAD_COUNTER > 5 )); then
                        echo -e "[$(date)] BAD_COUNTER greater than 5! Exiting... \n" >> $LOGFILE
                        exit
                    fi
                    
                    echo "" >> $LOGFILE
                    
                else
                    echo -e "[$(date)] No live stream. (IS_LIVE = null). Sleeping..." >> $LOGFILE  
                    
                    if (( $seconds_left > 0 )); then
                        echo -e "[$(date)] ... $seconds_left seconds" >> $LOGFILE  
                        sleep $seconds_left
                    else
                        echo -e "[$(date)] ... 1 minute" >> $LOGFILE  
                        sleep 1m
                    fi
                fi
                
                

                # Check if script should stop execution
                if [[ $CURRENT_HOUR -ge $stop_hour ]]; then                
                    if [[ $CURRENT_MIN -ge $stop_min ]]; then
                        echo -e "[$(date)] Its time to stop. Exiting... \n"
                        exit
                    fi                
                fi
                    
                echo -e "[$(date)] Bottom of while loop checking request. \n" >> $LOGFILE
                
            else
                echo -e "[$(date)] Its too early. START_MIN not reached yet. Sleeping 1m." >> $LOGFILE
                sleep 1m
            fi
        
        else
            echo -e "[$(date)] START_HOUR not reached yet. Exiting... \n" >> $LOGFILE
            exit
        fi
        
        
    done

else
    echo -e "[$(date)] The next stream is in $$(( $streamday - $CURRENT_WEEKDAY )) day(s). Exiting... \n" >> $LOGFILE
fi


# Get status
#youtube-dl --quiet --skip-download $LIVESTREAM_URL &> $LOGFILE    

# could be useful: timeout 2h mpv...
