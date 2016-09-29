#!/bin/bash

source "/opt/premiumize-cli-downloader.conf"

BOUNDARY="---------------------------312412633113176"
TEMP_FILE="temp.file"
LINKS_FILE="temp.links"
DLC_FILE=$1
SEED="2or48h"

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
    if [[ $line == "http://ul.to"* ]] ; then
        echo "  Getting premium link for ${line}..."
        curl -s "https://www.premiumize.me/api/transfer/create" \
                    -H "Host: www.premiumize.me" \
                    -H "Accept: */*" \
                    -H "Referer: https://www.premiumize.me/downloader" \
                    -H "Connection: keep-alive" \
                    -H "Cookie: login=$USER_ID:$USER_PIN" \
                    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
                    --data "src=${line}&seed=$SEED" | \
        jq '.location' | \
        sed -e 's/^"//g' | sed -e 's/"$//g' >> $LINKS_FILE
    fi
done  

echo "Getting file names and downloading files..."
rm $TEMP_FILE
while read -r url ; do
    FILENAME=$(echo $url | sed -e 's/^.*&f=//g')
    echo $FILENAME >> $TEMP_FILE
    echo "  Downloading file ${FILENAME}..."
    curl $url -o $FILENAME -#
done < "${LINKS_FILE}"

echo "Trying to extract files..."
if [[ $FILENAME == *".rar" ]] ; then
    echo "  Archive is rar, extracting..."
    unrar e -o+  $FILENAME
fi

echo "Finished, just cleaning up..."
while read -r file ; do
    echo "  Removing $file"
    rm $file
done < "${TEMP_FILE}"

if [ -e $TEMP_FILE ] ; then
    echo "  Removing temp file $TEMP_FILE"
    rm $TEMP_FILE
fi

if [ -e $LINKS_FILE ] ; then
    echo "  Removing links file $LINKS_FILE"
    rm $LINKS_FILE
fi
