# Premiumize.me CLI Downloader
A simple script, using premiumize.me's undocumented web API to decrypt DLCs, downloading files and extracting them.

The script was created, since pyload is currently not working when using `uploaded.to` links with `premiumize.me` accounts and I wanted to download files directly to my server without going through my personal computer.

## Usage
Invoke the script using `./premiumize-cli-downloader.sh <Links.dlc>`. The files will be stored in the current working directory alongside with two temporary files, unless you specified a default download location in your configuration file. After the download finished, the files will be extracted into the working directory and the downloaded archives will be removed.

Currently the script only grabs download links from `uploaded.to`, modify [line 62](https://github.com/steilerDev/premiumize.me-cli-downloader/blob/master/premiumize-cli-downloader.sh#L62) to change this behaviour. Similiarily only rar archives are currently support (see [lines 86-90](https://github.com/steilerDev/premiumize.me-cli-downloader/blob/master/premiumize-cli-downloader.sh#L86-L90)).

## Configuration
I recommend cloning the repository into `/opt/`. In order to configure the script, move or copy the `premiumize-cli-downloader.conf.example` to `/opt/premiumize-cli-downloader.conf` and enter your User ID and PIN (both can be obtained from your profile on the premiumize.me webpage). If you choose to move the application to a different location modify the `source` command in [line 3](https://github.com/steilerDev/premiumize.me-cli-downloader/blob/master/premiumize-cli-downloader.sh#L3).

You can specify a default download location in this file, by setting the variable `$DEFAULT_DOWNLOAD_LOCATION`.

# Prerequisits
The script only requires `curl` (version: 7.26.0) for the web interactions, `jq` (version: jq-1.4-1-e73951f) for JSON processing and `unrar` (version 4.10) for extraction. I tested the script with the annotated versions on a Debian 7 machine, that does not mean that they are explicitly required. 
