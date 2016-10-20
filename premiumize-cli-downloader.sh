#!/bin/bash 
source "/opt/premiumize.me-cli-downloader/premiumize-cli-downloader.conf"

DLC_FILE=".premiumize.$$.dlc"
BOUNDARY="---------------------------312412633113176"
TEMP_FILE=".premiumize.$$.file"
LINKS_FILE=".premiumize.$$.links"
SEED="2or48h"
MAX_PARALLEL_DL=6
LOG_FILE="/var/log/premiumize-me-cli-downloader.log"

main () {
    savelog -q $LOG_FILE

    log "Starting processing $1"

    if [ ! -z $DEFAULT_DOWNLOAD_LOCATION ] ; then
        log "Saving files to $DEFAULT_DOWNLOAD_LOCATION"
        mv $1 $DEFAULT_DOWNLOAD_LOCATION/$DLC_FILE
        cd $DEFAULT_DOWNLOAD_LOCATION
    else
        mv $1 ./$DLC_FILE
    fi

    if [ -e $TEMP_FILE ] ; then
        log "Deleting temp file $TEMP_FILE"
        rm $TEMP_FILE
    fi

    if [ -e $LINKS_FILE ] ; then
        log "Deleting links file $LINKS_FILE"
        rm $LINKS_FILE
    fi

    decrypt_dlc
    download_file_list
    cleanup
    log "Finished processing $1!"
}

decrypt_dlc () {

    #
    # Creating DLC decrypt payload
    #

    echo "--$BOUNDARY" >> $TEMP_FILE
    echo "Content-Disposition: form-data; name=\"src\"; filename=\"$DLC_FILE\"" >> $TEMP_FILE
    echo "Content-Type: application/octet-stream" >> $TEMP_FILE
    echo >> $TEMP_FILE
    cat $DLC_FILE >> $TEMP_FILE
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

    logf "Using payload: "
    logf "$(cat $TEMP_FILE)"

    #
    # Decrypting dlc and getting premium link list
    # Saving link list to $LINKS_FILE returning number of links
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
        if [[ $line == "http://ul.to"* ||  $line == "http://uploaded.net"* ]] ; then
            ((TOTAL_FILE_COUNT++))
            log "- Getting premium link (#${TOTAL_FILE_COUNT}) for ${line}..."
            curl -s "https://www.premiumize.me/api/transfer/create" \
                        -H "Host: www.premiumize.me" \
                        -H "Accept: */*" \
                        -H "Referer: https://www.premiumize.me/downloader" \
                        -H "Connection: keep-alive" \
                        -H "Cookie: login=$USER_ID:$USER_PIN" \
                        -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
                        --data "src=${line}&seed=$SEED" > $TEMP_FILE

            logf "Got response for file #${TOTAL_FILE_COUNT}: "
            logf "$(cat $TEMP_FILE)"

            cat $TEMP_FILE | \
                jq '.location' | \
                sed -e 's/^"//g' | sed -e 's/"$//g' | tr '\n' ' ' >> $LINKS_FILE
            cat $TEMP_FILE | \
                jq '.filename' | \
                sed -e 's/^"//g' | sed -e 's/"$//g' >> $LINKS_FILE

        fi
    done  
    logf "Clearing temp file"
    > $TEMP_FILE
    logf "Extracted links: "
    logf "$(cat $LINKS_FILE)"
}

download_file () {
    log "- Downloading file ${1}/${2} (${4})..."
    curl $3 -o $4 -# > /dev/null 2>&1
    log "- Finished downloading ${1}/${2} (${4})!"
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
        log "Getting file names and downloading files..."

        TOTAL_FILE_COUNT=$(cat $LINKS_FILE | wc -l)
        CURRENT_FILE_COUNT=0

        while read -r URL FILENAME; do
            while [ "$(jobs | wc -l)" -ge "$MAX_PARALLEL_DL" ] ; do
                sleep 10
            done

            ((CURRENT_FILE_COUNT++))
            download_file "$CURRENT_FILE_COUNT" "$TOTAL_FILE_COUNT" "$URL" "$FILENAME" &

        done < "${LINKS_FILE}"
        sleep 2
        log "All Downloads queued, waiting for them to finish..."
        wait

        rm ${TEMP_FILE}

        log "Trying to extract files..."
        
        while [ -s ${LINKS_FILE} ] ; do
            read -r URL FILENAME < ${LINKS_FILE}
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
    fi
}

cleanup () {
    log "Finished, just cleaning up..."

    logf "Killing all eventually running jobs..."
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
    else
        log "- $TEMP_FILE does not exist, can't remove it or adjacent archives!"
    fi

    if [ -e $DLC_FILE ] ; then
        log "- Removing DLC file $DLC_FILE"
        rm $DLC_FILE
    fi

    if [ -e $LINKS_FILE ] ; then
        log "- Removing links file $LINKS_FILE"
        rm $LINKS_FILE
    fi
}

log () {
    echo $@ | tee -a $LOG_FILE
}

logf () {
    echo $@ >> $LOG_FILE
}

main $@
