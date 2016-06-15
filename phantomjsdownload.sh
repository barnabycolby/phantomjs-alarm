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

# The version to download from Arch Linux ARM should be passed as the first argument
# The version to create should be passed as the second argument
# Note that these values may differ if the Arch Linux ARM packages have been patched
download() {
    alarmVersion=$1
    version=$2

    # Create the required directories
    local tmp="$(mktemp -d)"
    local alarmDirPath="${tmp}/alarm"
    local outputDir="phantomjs-${version}-linux-armv7h"
    local outputDirPath="${tmp}/${outputDir}"
    local bitbucketDirPath="${tmp}/bitbucket"
    mkdir $alarmDirPath
    mkdir $outputDirPath
    mkdir $bitbucketDirPath

    # Download and extract the Arch Linux ARM package
    local pkgFilename="phantomjs-${alarmVersion}-armv7h.pkg.tar.xz"
    wget "http://mirror.archlinuxarm.org/armv7h/community/${pkgFilename}" -O ${tmp}/${pkgFilename}
    tar xvJf ${tmp}/${pkgFilename} -C $alarmDirPath

    # Download and extract the bitbucket package (for the changelog and readme)
    bitbucketFilenameNoExtension="phantomjs-${version}-linux-x86_64"
    bitbucketFilename="${bitbucketFilenameNoExtension}.tar.bz2"
    wget "https://bitbucket.org/ariya/phantomjs/downloads/${bitbucketFilename}" -O ${tmp}/${bitbucketFilename}
    tar xvjf ${tmp}/${bitbucketFilename} -C ${bitbucketDirPath}

    # Construct the phantomjs output folder
    cp -r ${alarmDirPath}/usr/bin ${outputDirPath}/
    cp -r ${alarmDirPath}/usr/share/phantomjs/examples ${outputDirPath}/
    cp -r ${alarmDirPath}/usr/share/licenses/phantomjs/* ${outputDirPath}/
    cp ${bitbucketDirPath}/${bitbucketFilenameNoExtension}/README.md ${outputDirPath}/
    cp ${bitbucketDirPath}/${bitbucketFilenameNoExtension}/ChangeLog ${outputDirPath}/

    # Compress the output folder
    local outputFile="${tmp}/${outputDir}.tar.bz2"
    tar cvjf ${outputFile} --directory=${tmp} ${outputDir}

    # Move the output archive to the appropriate location
    mv ${outputFile} ${downloadLocation}

    rm -r $tmp
}

echo -n "Finding the latest version of phantomjs available..."
# tr -d removes all whitespace, in particular, this is used to remove the leading newline added by echo
latestAlarmVersion="$(printLatestVersion | tr -d '[[:space:]]')"
latestVersion="$(echo ${latestAlarmVersion} | sed -e 's/-.*//')"
echo "Done."

echo -n "Checking to see whether the latest version has already been downloaded..."
if alreadyDownloaded "$latestVersion"; then
    echo "Done."
    echo "The latest version of phantomjs ($latestVersion) has already been downloaded."
    exit 2
fi
echo "Done."

echo -n "Downloading latest version..."
download "$latestAlarmVersion" "$latestVersion"
echo "Done."

exit 0
