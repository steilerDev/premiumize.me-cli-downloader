#!/bin/bash

source "/opt/premiumize.me-cli-downloader/premiumize-cli-downloader.conf"

DLC_FILE=$1
BOUNDARY="---------------------------312412633113176"
TEMP_FILE=".premiumize.$$.file"
LINKS_FILE=".premiumize.$$.links"
SEED="2or48h"

if [ ! -z $DEFAULT_DOWNLOAD_LOCATION ] ; then
    echo "Saving files to $DEFAULT_DOWNLOAD_LOCATION"
    mv $1 $DEFAULT_DOWNLOAD_LOCATION/
    DLC_FILE=$(basename $1)
    cd $DEFAULT_DOWNLOAD_LOCATION
fi

if [ -e $TEMP_FILE ] ; then
    echo "Deleting temp file $TEMP_FILE"
    rm $TEMP_FILE
fi

if [ -e $LINKS_FILE ] ; then
    echo "Deleting links file $LINKS_FILE"
    rm $LINKS_FILE
fi


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

#
# Decrypting dlc and getting premium link list
# Saving link list to $LINKS_FILE
#
echo "Decrypting DLC..."
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
        echo "  Getting premium link for ${line}..."
        curl -s "https://www.premiumize.me/api/transfer/create" \
                    -H "Host: www.premiumize.me" \
                    -H "Accept: */*" \
                    -H "Referer: https://www.premiumize.me/downloader" \
                    -H "Connection: keep-alive" \
                    -H "Cookie: login=$USER_ID:$USER_PIN" \
                    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
                    --data "src=${line}&seed=$SEED" > $TEMP_FILE

        cat $TEMP_FILE | \
            jq '.location' | \
           sed -e 's/^"//g' | sed -e 's/"$//g' | tr '\n' ' ' >> $LINKS_FILE
        cat $TEMP_FILE | \
            jq '.filename' | \
            sed -e 's/^"//g' | sed -e 's/"$//g' >> $LINKS_FILE
    fi
done  

#
# Iterating over links file (if it exists), downloading each file and extracting them
# Todo: Spawn curl process with `&` and wait for them to finish
#
if [ ! -e $LINKS_FILE ] ; then
    echo "Unable to retrieve premium links!"
    exit
else 
    echo "Getting file names and downloading files..."
    while read -r URL FILENAME; do
        echo "  Downloading file ${FILENAME}..."
        curl $URL -o $FILENAME -#
    done < "${LINKS_FILE}"

    rm ${TEMP_FILE}

    echo "Trying to extract files..."
    
    while [ -s ${LINKS_FILE} ] ; do
        read -r URL FILENAME < ${LINKS_FILE}
        echo "  Processing $FILENAME"
        if [ ! -e $FILENAME ] ; then
            echo "   $FILENAME does not exist, unable to extract"
        elif [[ $FILENAME == *".rar" ]] ; then
            # Getting all files belonging to archive
            unrar l -v $FILENAME | \
                grep '^Volume' | \
                sed -e 's/Volume //g' | \
                while read -r line; do
                    echo "  $line is part of ${FILENAME}'s archive"
                    echo ${line} >> ${TEMP_FILE}
                    sed -i '/'"${line}"'/d' ${LINKS_FILE}
                done
            echo "   Extracting ${FILENAME}..."
            unrar e -o+ $FILENAME
        else
            echo "   Archive (${FILENAME}) is not rar"
        fi
        sed -i '/'"${FILENAME}"'/d' ${LINKS_FILE}
    done
fi

echo "Finished, just cleaning up..."
if [ -e $TEMP_FILE ] ; then
    while read -r file ; do
        if [ -e $file ] ; then
            echo "  Removing $file"
            rm $file
        else
            echo "  $file does not exist, unable to delete"
        fi
    done < "${TEMP_FILE}"
else
    echo "  $TEMP_FILE does not exist!"
fi

if [ -e $DLC_FILE ] ; then
    echo "  Removing DLC file $DLC_FILE"
    rm $DLC_FILE
fi

if [ -e $TEMP_FILE ] ; then
    echo "  Removing temp file $TEMP_FILE"
    rm $TEMP_FILE
fi

if [ -e $LINKS_FILE ] ; then
    echo "  Removing links file $LINKS_FILE"
    rm $LINKS_FILE
fi
