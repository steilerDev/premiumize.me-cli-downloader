#!/bin/bash 
source "/opt/premiumize.me-cli-downloader/premiumize-cli-downloader.conf"

# Variables required for http requests
BOUNDARY="---------------------------312412633113176"
SEED="2or48h"

# File variables
SOURCE_FILE=".premiumize.$$.source"
TEMP_FILE=".premiumize.$$.file"
LINKS_FILE=".premiumize.$$.links"
FAILED_FILE="premiumize.$$.failed.links"

main () {
    savelog -q $LOG_FILE

    debug "$(date)"
    log "Starting processing $1"

    # Making sure nothing comes into our way    
    > $TEMP_FILE
    > $LINKS_FILE

    # Switching to default download location and renaming files accordingly
    if [ ! -z $DEFAULT_DOWNLOAD_LOCATION ] ; then
        log "Saving files to $DEFAULT_DOWNLOAD_LOCATION"
        mv $1 $DEFAULT_DOWNLOAD_LOCATION/$SOURCE_FILE
        cd $DEFAULT_DOWNLOAD_LOCATION
    else
        mv $1 ./$SOURCE_FILE
    fi

    # Filling $LINKS_FILE at this point
    if [[ $1 == *".dlc" ]] ; then
        decrypt_dlc
    elif [[ $1 == *".links" ]] ; then
        while read -r URL _; do 
            ((TOTAL_FILE_COUNT++))
            get_premium_link $URL $TOTAL_FILE_COUNT
        done < "$SOURCE_FILE"
    else
        log "Stated file is neither a DLC nor a links file, can not continue processing!"
        exit
    fi
    
    > $TEMP_FILE

    # Downloading based on $LINKS_FILE
    download_file_list

    # Removing temp files, as well as processed archives
    cleanup

    log "Finished processing $1!"
    if [ -e $FAILED_FILE ] ; then
        log "!! Some downloads failed, check $FAILED_FILE for retrying"
    fi
}

decrypt_dlc () {

    #
    # Creating DLC decrypt payload
    #

    echo "--$BOUNDARY" >> $TEMP_FILE
    echo "Content-Disposition: form-data; name=\"src\"; filename=\"${SOURCE_FILE}.dlc\"" >> $TEMP_FILE
    echo "Content-Type: application/octet-stream" >> $TEMP_FILE
    echo >> $TEMP_FILE
    cat $SOURCE_FILE >> $TEMP_FILE
    echo >> $TEMP_FILE
    echo "--$BOUNDARY" >> $TEMP_FILE
    echo "Content-Disposition: form-data; name=\"seed\"" >> $TEMP_FILE
    echo >> $TEMP_FILE
    echo $SEED >> $TEMP_FILE
    echo "--$BOUNDARY" >> $TEMP_FILE
    echo "Content-Disposition: form-data; name=\"password\"" >> $TEMP_FILE
    echo >> $TEMP_FILE
    echo >> $TEMP_FILE
    echo "--$BOUNDARY--" >> $TEMP_FILE

    debug "Using payload: "
    debug "$(cat $TEMP_FILE)"

    #
    # Decrypting dlc and getting premium link list
    #
    log "Decrypting DLC..."
    curl -s "https://www.premiumize.me/api/transfer/create" \
                -H "Host: www.premiumize.me" \
                -H "Accept: */*" \
                -H "Referer: https://www.premiumize.me/downloader" \
                -H "Connection: keep-alive" \
                -H "Cookie: login=$USER_ID:$USER_PIN" \
                -H "Content-Type: multipart/form-data; boundary=$BOUNDARY" \
                --data-binary @$TEMP_FILE | \
    jq -r -c '.content[]' | \
        while read -r line; do 
            ((TOTAL_FILE_COUNT++))
            get_premium_link $line $TOTAL_FILE_COUNT
        done  
}

get_premium_link () {
    URL=$1
    TOTAL_FILE_COUNT=$2
    if [[ $URL == "http://ul.to"* ||  $URL == "http://uploaded.net"* ]] ; then
        log "- Getting premium link (#${TOTAL_FILE_COUNT}) for ${URL}..."
        curl -s "https://www.premiumize.me/api/transfer/create" \
                    -H "Host: www.premiumize.me" \
                    -H "Accept: */*" \
                    -H "Referer: https://www.premiumize.me/downloader" \
                    -H "Connection: keep-alive" \
                    -H "Cookie: login=$USER_ID:$USER_PIN" \
                    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
                    --data "src=${URL}&seed=$SEED" > $TEMP_FILE

        debug "Got response for link #${TOTAL_FILE_COUNT} (${URL}): "
        debug "$(cat $TEMP_FILE)"

        if [[ "$(cat $TEMP_FILE | jq '.status')" == *"success"* ]] ; then
            echo -n "$URL " >> $LINKS_FILE
            cat $TEMP_FILE | \
                jq '.location' | \
                sed -e 's/^"//g' | sed -e 's/"$//g' | tr '\n' ' ' >> $LINKS_FILE

            cat $TEMP_FILE | \
                jq '.filesize' | \
                sed -e 's/^"//g' | sed -e 's/"$//g' | tr '\n' ' ' >> $LINKS_FILE

            cat $TEMP_FILE | \
                jq '.filename' | \
                sed -e 's/^"//g' | sed -e 's/"$//g' >> $LINKS_FILE
        else
            log "! Unable to get premium link (#${TOTAL_FILE_COUNT}) for ${URL}!"
            echo "$URL" >> $FAILED_FILE
        fi
    else
        log "! Link is not supported: ${URL}!"
    fi
}


#
# Iterating over links file (if it exists), downloading each file and extracting them
# Todo: Spawn curl process with `&` and wait for them to finish
#
download_file_list () {
    if [ ! -e $LINKS_FILE ] ; then
        log "Unable to retrieve premium links!"
        return
    else 
        log "Downloading files..."

        TOTAL_FILE_COUNT=$(cat $LINKS_FILE | wc -l)
        CURRENT_FILE_COUNT=0

        while read -r OURL URL SIZE FILENAME; do
            while [ "$(jobs | wc -l)" -ge "$MAX_PARALLEL_DL" ] ; do
                sleep 10
            done

            ((CURRENT_FILE_COUNT++))
            download_file "$CURRENT_FILE_COUNT" "$TOTAL_FILE_COUNT" "$SIZE" "$URL" "$OURL" "$FILENAME" &

        done < "${LINKS_FILE}"
        debug "All Downloads started, waiting for them to finish..."
        wait

        extract_files
    fi
}

download_file () {
    URL=$4
    O_URL=$5
    CFC=$1
    TFC=$2
    SIZE=$3
    NAME=$6

    log "- Downloading file ${CFC}/${TFC} (${NAME})..."
    curl $URL -o $NAME -# > /dev/null 2>&1

    ACTUAL_SIZE=$(stat --printf="%s" $NAME)
    if [ "$ACTUAL_SIZE" -ne "$SIZE" ] ; then
        log "! Failed downloading ${CFC}/${TFC} (${NAME}), because size is not as expected (${SIZE} vs. ${ACTUAL_SIZE})"
        # If the download failed, the file will be removed from the link list (in order to not be respected during extraction later)
        sed -i '/'"${FILENAME}"'/d' ${LINKS_FILE}
        # The file's metadata will be written to a file in order to be retried later
        echo "$O_URL $URL $SIZE $NAME" >> $FAILED_FILE
        # The remaining data that was downloaded will be removed
        rm $FILENAME
    else
        log "- Finished downloading ${CFC}/${TFC} (${NAME})!"
    fi
}

extract_files () {
    log "Trying to extract files..."
    
    while [ -s ${LINKS_FILE} ] ; do
        read -r OURL URL SIZE FILENAME < ${LINKS_FILE}
        log "- Processing $FILENAME"
        if [ ! -e $FILENAME ] ; then
            log "-- $FILENAME does not exist, unable to extract"
            sed -i '/'"${FILENAME}"'/d' ${LINKS_FILE}
        elif [[ $FILENAME == *".rar" ]] ; then
            log "-- Extracting ${FILENAME}..."
            unrar e -o+ $FILENAME | tr $'\r' $'\n' >> $LOG_FILE 2>&1
            UNRAR_EXIT="${PIPESTATUS[0]}"
            if [ "$UNRAR_EXIT" -ne "0" ] ; then
                log "--- Extraction of $FILENAME failed, not removing!"
                sed -i '/'"${FILENAME}"'/d' ${LINKS_FILE}
            fi
            # Getting all files belonging to archive, in order to delete them later and not process them again
            unrar l -v $FILENAME | \
                grep '^Volume' | \
                sed -e 's/Volume //g' | \
                while read -r line; do
                    log "--- $line is part of ${FILENAME}'s archive"

                    if [ "$UNRAR_EXIT" -eq "0" ] ; then
                        # Adding the filename to the temp file will mark it for removal later, only doing so, if the extraction was successful
                        echo ${line} >> ${TEMP_FILE}
                    fi
                    # Removing line from links file means, that the file will not be processed during extraction again
                    sed -i '/'"${line}"'/d' ${LINKS_FILE}
                done
        else
            log "- Archive (${FILENAME}) is not rar"
            sed -i '/'"${FILENAME}"'/d' ${LINKS_FILE}
        fi
    done
}

cleanup () {
    log "Finished, just cleaning up..."

    debug "Killing all eventually running jobs..."
    jobs -l | \
        grep -oE '[0-9]+ Running' | \
        grep -oE '[0-9]+' | \
        while read -r pid ; do
            kill -9 $pid
        done

    if [ -e $TEMP_FILE ] ; then
        while read -r file ; do
            if [ -e $file ] ; then
                log "-  Removing $file"
                rm $file
            else
                log "- $file does not exist, unable to delete"
            fi
        done < "${TEMP_FILE}"
        log "- Removing temp file ${TEMP_FILE}"
        rm ${TEMP_FILE}
    else
        log "- $TEMP_FILE does not exist, can't remove it or adjacent archives!"
    fi

    if [ -e $SOURCE_FILE ] ; then
        log "- Removing source file $SOURCE_FILE"
        rm $SOURCE_FILE
    fi

    if [ -e $LINKS_FILE ] ; then
        log "- Removing links file $LINKS_FILE"
        rm $LINKS_FILE
    fi
}

log () {
    echo $@ | tee -a $LOG_FILE
}

debug () {
    echo $@ >> $LOG_FILE
}

main $@
