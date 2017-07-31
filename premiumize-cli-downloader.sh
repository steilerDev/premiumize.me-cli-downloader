#!/bin/bash 
source "/opt/premiumize.me-cli-downloader/premiumize-cli-downloader.conf"

# Variables required for http requests
BOUNDARY="---------------------------312412633113176"
SEED="2or48h"

# File variables
TEMP_FILE=".premiumize.$$.file"
LINKS_FILE=".premiumize.$$.links"
FAILED_FILE="premiumize.$$.failed.links"
TEMP_FAILED_FILE=".premiumize.$$.failed.links"
TOTAL_FILE_COUNT=0
RETRY=false
RETRY_COUNT=0
EDIT=false
# Keep track of source folder
SOURCE_DIR=""

# Color variables
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[1;31m'
NC='\033[0m'

main () {
    savelog -q $LOG_FILE

    debug "$(date)"
    if [ $# -eq 0 ]; then
        log "No files provided, scanning current directory for DLC files..."
        set -- "$(ls *.dlc *.links)"
    fi
    debug "Got the following files: $@"
    
    # Switching to default download location and renaming files accordingly
    if [ ! -z $DEFAULT_DOWNLOAD_LOCATION ] ; then
        log "Saving files to $DEFAULT_DOWNLOAD_LOCATION"
        SOURCE_DIR="$(pwd)/"
        cd $DEFAULT_DOWNLOAD_LOCATION
    fi
   
    # Making sure there is nothing there 
    if [ -e $LINKS_FILE ] ; then
        > $LINKS_FILE
    fi

    if [ -e $TEMP_FAILED_FILE ] ; then
        > $TEMP_FAILED_FILE
    fi
    
    while getopts "er" opt; do
        case $opt in
            e)
                debug "Edit mode on"
                EDIT=true
                ;;
            r)
                debug "Retry mode on"
                RETRY=true
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                ;;
        esac
    done
  
    # Create $LINKS_FILE 
    process_input $@
    
    # Downloading based on $LINKS_FILE
    download_file_list

    # Removing temp files, as well as processed archives
    cleanup

    # Checks for failed downloads and retries if user wants it
    finish
}

process_input () {
    for INPUT in "$@" ; do
        if [[ $INPUT != "-"* ]] ; then
            INPUT="${SOURCE_DIR}${INPUT}"
            log_start "Starting processing $INPUT"
            > $TEMP_FILE

            # Filling $LINKS_FILE at this point
            if [ ! -e $INPUT ] ; then
                log_error "Unable to process ${INPUT}: File does not exist"
                continue
            elif [[ $INPUT == *".dlc" ]] ; then
                decrypt_dlc $INPUT
            elif [[ $INPUT == *".links" ]] ; then
                while read -r URL _; do 
                    if [[ $URL != "#"* ]] ; then
                        get_premium_link $URL
                    fi
                done < "${INPUT}"
            elif [[ $INPUT == *".premlinks" ]] ; then
                cat $INPUT >> $LINKS_FILE
            else
                log_error "\"$INPUT\" is neither a DLC nor a links file, can not process it!"
                continue
            fi
            log_finish "Finished processing ${INPUT}, removing file!"
            rm $INPUT
        fi
    done

    if [ "$EDIT" = true ] ; then
        vim $LINKS_FILE
    fi
}

# Clears TEMP_FILE, appends LINKS_FILE
decrypt_dlc () {

    #
    # Creating DLC decrypt payload
    #
    > $TEMP_FILE
    echo "--$BOUNDARY" >> $TEMP_FILE
    echo "Content-Disposition: form-data; name=\"src\"; filename=\"${1}.dlc\"" >> $TEMP_FILE
    echo "Content-Type: application/octet-stream" >> $TEMP_FILE
    echo >> $TEMP_FILE
    cat $1 >> $TEMP_FILE
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
    log_start "Decrypting DLC (${1})..."
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
            get_premium_link $line
        done  
}

# Clears TEMP_FILE, appends LINKS_FILE
get_premium_link () {
    URL=$1
    ((TOTAL_FILE_COUNT++))
    > $TEMP_FILE
    if [[ $URL == "http://ul.to"* ||  $URL == "http://uploaded.net"* ||  $URL == "https://openload.co/"* ]] ; then
        log_start "- Getting premium link (#${TOTAL_FILE_COUNT}) for ${URL}..."
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
            log_error "! Unable to get premium link (#${TOTAL_FILE_COUNT}) for ${URL}!"
            echo "$URL" >> $TEMP_FAILED_FILE
        fi
    else
        log_error "! Link is not supported: ${URL}!"
    fi
}


#
# Iterating over links file (if it exists), downloading each file and extracting them
# Todo: Spawn curl process with `&` and wait for them to finish
#
# Removes single line from LINKS_FILE and appends it to TEMP_FAILED_FILE (in case download did not succeed)
download_file_list () {
    if [ ! -e $LINKS_FILE ] ; then
        log_error "Unable to retrieve premium links!"
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

# Removes single line from LINKS_FILE and appends it to TEMP_FAILED_FILE (in case download did not succeed)
download_file () {
    URL=$4
    O_URL=$5
    CFC=$1
    TFC=$2
    SIZE=$3
    NAME=$6

    log_start "- Downloading file ${CFC}/${TFC} (${NAME})..."
    curl $URL -o $NAME -# > /dev/null 2>&1

    ACTUAL_SIZE=$(stat --printf="%s" $NAME)
    if [ "$ACTUAL_SIZE" -ne "$SIZE" ] ; then
        log_error "! Failed downloading ${CFC}/${TFC} (${NAME}), because size is not as expected (${SIZE} vs. ${ACTUAL_SIZE})"
        # If the download failed, the file will be removed from the link list (in order to not be respected during extraction later)
        sed -i '/'"${FILENAME}"'/d' ${LINKS_FILE}
        # The file's metadata will be written to a file in order to be retried later
        echo "$O_URL $URL $SIZE $NAME" >> $TEMP_FAILED_FILE
        # The remaining data that was downloaded will be removed
        rm $FILENAME
    else
        log_finish "- Finished downloading ${CFC}/${TFC} (${NAME})!"
    fi
}

# Clears tempfile, replaces LINKS_FILE and empties it
extract_files () {
    log "Trying to extract files..."
  
    log "- Preparing extraction..." 
    # Sorting files by filename, means we will start with the first archive, subsequential archives do not contain inforamtion about preceding archives, resulting in re-doing the extraction when not starting with the first archive

    debug "Sorting ${LINKS_FILE}..."
    > ${TEMP_FILE} 
    while read -r OURL URL SIZE FILENAME; do
        echo $FILENAME >> ${TEMP_FILE}
    done < "${LINKS_FILE}"
    sort ${TEMP_FILE} -o ${LINKS_FILE}
    > ${TEMP_FILE} 
    debug "${LINKS_FILE} sorted!"

    while [ -s ${LINKS_FILE} ] ; do
        read -r FILENAME < ${LINKS_FILE}
        log_start "- Processing $FILENAME"
        if [ ! -e $FILENAME ] ; then
            log_error "-- $FILENAME does not exist, unable to extract"
            sed -i '/'"${FILENAME}"'/d' ${LINKS_FILE}
        elif [[ $FILENAME == *".rar" ]] ; then
            log "-- Extracting ${FILENAME}..."
            UNRAR_ERR=false

            # Check if all volumes are there
            if unrar l -v $FILENAME 2>&1 | grep -q "Cannot find volume" ; then
                log_error "--- Archive not complete, aborting"
                UNRAR_ERR=true
            else
                unrar e -o+ $FILENAME | tr $'\r' $'\n' >> $LOG_FILE 2>&1
                UNRAR_EXIT="${PIPESTATUS[0]}"
                if [ "$UNRAR_EXIT" -ne "0" ] ; then
                    log_error "--- Extraction of $FILENAME failed!"
                    UNRAR_ERR=true
                fi
            fi

            if [ "$UNRAR_ERR" = true ] ; then
                sed -i '/'"${FILENAME}"'/d' ${LINKS_FILE}
            fi

            # Getting all files belonging to archive, in order to delete them later and not process them again
            unrar l -v $FILENAME 2>&1 | \
                grep '^Archive' | \
                sed -e 's/Archive: //g' | \
                while read -r line; do
                    log "--- $line is part of ${FILENAME}'s archive"

                    if [ "$UNRAR_ERR" = false ] ; then
                        # Adding the filename to the temp file will mark it for removal later, only doing so, if the extraction was successful
                        echo ${line} >> ${TEMP_FILE}
                    fi
                    # Removing line from links file means, that the file will not be processed during extraction again
                    sed -i '/'"${line}"'/d' ${LINKS_FILE}
                done
            log_finish "- Finished processing $FILENAME"
        else
            log_error "- Archive (${FILENAME}) is not rar"
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

    if [ -e $LINKS_FILE ] ; then
        log "- Removing links file $LINKS_FILE"
        rm $LINKS_FILE
    fi
}

finish () {
    log_finish "Finished processing $@!"
    if [ -e $TEMP_FAILED_FILE ] ; then
        (echo "# Failed file list for $@" && cat ${TEMP_FAILED_FILE}) > ${FAILED_FILE}
        rm $TEMP_FAILED_FILE
        log_error "!! Some downloads failed, check $FAILED_FILE for retrying"
        if [ "$RETRY" = true ] ; then
            ((RETRY_COUNT++))
            log "Trying to download failed files (Retry #${RETRY_COUNT})..."
            > $LINKS_FILE
            > $TEMP_FAILED_FILE
            # Source dir needs to be cleared, since FAILED FILE is in the other dir
            SOURCE_DIR=""
            process_input $FAILED_FILE
            download_file_list
            cleanup
            finish
        fi
    fi
}

log_start () {
    echo -e "${CYAN}$@${NC}"
    debug $@
}

log_finish () {
    echo -e "${GREEN}$@${NC}"
    debug $@
}

log_error () {
    echo -e "${RED}$@${NC}"
    debug $@
}

log () {
    echo $@ | tee -a $LOG_FILE
}

debug () {
    echo $@ >> $LOG_FILE
}

main $@
