#!/bin/bash

# Should be the location of a folder without the trailing /
downloadLocation='/data/dist/phantomjs'

# Prints the latest version of phantomjs available from archlinuxarm
printLatestVersion() {
    local version=$(curl 'http://mirror.archlinuxarm.org/armv7h/community/' -L -s | grep 'phantomjs-.*-armv7h.pkg.tar.xz<' | sed -e 's/^.*<a href="phantomjs-//' | sed -e 's/-armv7h.*$//')
    
    # Check that the version number is valid
    versionRegex="^[0-9]+\.[0-9]+\.[0-9]+(\$|-[0-9]+)"
    echo "$(echo "$version" | grep -Eq "$versionRegex")"
    if [ -z "$version" ] || ! echo "$version" | grep -Eq "$versionRegex" ;then
        echo "The version number scraped from the ALARM mirror was invalid: $version"
        exit 1
    fi

    echo $version
}

# Check to see whether we already have it archived
# Requires the version to check for as the first argument
alreadyDownloaded() {
    local filename="${downloadLocation}/phantomjs-${1}-linux-armv7h.tar.bz2"
    if [ -f $filename ]; then
        return 0
    else
        return 1
    fi
}

# If not, download and extract it
# Make it publicly available

download() {
    wget 'http://mirror.archlinuxarm.org/armv7h/community/phantomjs-2.1.1-3-armv7h.pkg.tar.xz'
    mkdir tmp
    tar -xvJf phantomjs-2.1.1-3-armv7h.pkg.tar.xz -C tmp
    cp tmp/usr/bin/phantomjs phantomjs-2.1.1-3-armv7h
    rm -r tmp
    rm phantomjs-2.1.1-3-armv7h.pkg.tar.xz
}

echo -n "Finding the latest version of phantomjs available..."
# tr -d removes all whitespace, in particular, this is used to remove the leading newline added by echo
latestVersion="$(printLatestVersion | tr -d '[[:space:]]')"
echo "Done."

echo -n "Checking to see whether the latest version has already been downloaded..."
if alreadyDownloaded "$latestVersion"; then
    echo "Done."
    echo "The latest version of phantomjs ($latestVersion) has already been downloaded."
    exit 2
fi
echo "Done."
