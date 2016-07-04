#!/bin/bash

# Should be the location of a folder without the trailing /
downloadLocation='/data/dist/phantomjs'

# Prints the latest version of phantomjs available from archlinuxarm
printLatestVersion() {
    local architecture=$1
    local version=$(curl "http://mirror.archlinuxarm.org/${architecture}/community/" -L -s | grep "phantomjs-.*-${architecture}.pkg.tar.xz<" | sed -e 's/^.*<a href="phantomjs-//' | sed -e "s/-${architecture}.*$//")
    
    # Check that the version number is valid
    versionRegex="^[0-9]+\.[0-9]+\.[0-9]+(\$|-[0-9]+)"
    echo "$(echo "$version" | grep -Eq "$versionRegex")"
    if [ -z "$version" ] || ! echo "$version" | grep -Eq "$versionRegex" ;then
        echo "The version number scraped from the ALARM mirror was invalid: $version"
        return 1
    fi

    echo $version
}

# Check to see whether we already have it archived
# Requires the version to check for as the first argument
alreadyDownloaded() {
    local architecture=$1
    local version=$2

    local filename="${downloadLocation}/phantomjs-${version}-linux-${architecture}.tar.bz2"
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
    local architecture=$1
    local alarmVersion=$2
    local tmpRoot=$3

    # Strips the extra alarm versioning if it exists
    local version="$(echo ${latestAlarmVersion} | sed -e 's/-.*//')"

    # Create the required directories
    local tmp="${tmpRoot}/${architecture}"
    local alarmDirPath="${tmp}/alarm"
    local outputDir="phantomjs-${version}-linux-${architecture}"
    local outputDirPath="${tmp}/${outputDir}"
    local bitbucketDirPath="${tmp}/bitbucket"
    mkdir $tmp
    mkdir $alarmDirPath
    mkdir $outputDirPath
    mkdir $bitbucketDirPath

    # Download and extract the Arch Linux ARM package
    local pkgFilename="phantomjs-${alarmVersion}-${architecture}.pkg.tar.xz"
    wget "http://mirror.archlinuxarm.org/${architecture}/community/${pkgFilename}" -O ${tmp}/${pkgFilename}

    # Download and extract the bitbucket package (for the changelog and readme), if it is not already downloaded
    bitbucketFilenameNoExtension="phantomjs-${version}-linux-x86_64"
    bitbucketFilename="${bitbucketFilenameNoExtension}.tar.bz2"
    bitbucketFilePath="${tmpRoot}/${bitbucketFilename}"
    if [ ! -f ${bitbucketFilePath} ]; then
        wget "https://bitbucket.org/ariya/phantomjs/downloads/${bitbucketFilename}" -O ${bitbucketFilePath}
    fi

    # Construct the phantomjs output folder by extracting the required components to the appropriate directory
    tar xvJf ${tmp}/${pkgFilename} -C ${outputDirPath}/ usr/bin --strip-components=1
    tar xvJf ${tmp}/${pkgFilename} -C ${outputDirPath}/ usr/share/phantomjs/examples --strip-components=3
    tar xvJf ${tmp}/${pkgFilename} -C ${outputDirPath}/ usr/share/licenses/phantomjs --strip-components=4
    tar xvjf ${bitbucketFilePath} -C ${outputDirPath}/ ${bitbucketFilenameNoExtension}/README.md --strip-components=1
    tar xvjf ${bitbucketFilePath} -C ${outputDirPath}/ ${bitbucketFilenameNoExtension}/ChangeLog --strip-components=1

    # Compress the output folder
    local outputArchiveExtension="tar.bz2"
    local outputArchive="phantomjs-${alarmVersion}-linux-${architecture}.${outputArchiveExtension}"
    local outputFile="${tmp}/${outputArchive}"
    tar cvjf ${outputFile} --directory=${tmp} ${outputDir}

    # Move the output archive to the appropriate location
    mv ${outputFile} ${downloadLocation}

    # Symbolically link the latest phantomjs version to the latest ALARM version
    local outputFileNoAlarmVersioning="${outputDir}.${outputArchiveExtension}"
    ln -sf ${downloadLocation}/${outputArchive} ${downloadLocation}/${outputFileNoAlarmVersioning}
}

# If the latest version has not already been downloaded, it is downloaded and packaged for use
# The architecture to download and package for should be given as the first argument (something like "armv7h")
downloadAndPackage() {
    local architecture=$1
    local tmp=$2

    # Get the latest version, ensuring that we check for errors
    echo -n "Finding the latest version of phantomjs available..."
    latestAlarmVersionWithSpaces="$(printLatestVersion ${architecture})"
    if [ $? != 0 ]; then
        echo "${latestAlarmVersionWithSpaces}"
        return 1
    fi

    # tr -d removes all whitespace, in particular, this is used to remove the leading newline added by echo
    latestAlarmVersion="$(echo ${latestAlarmVersionWithSpaces} | tr -d '[[:space:]]')"
    echo "Done."
    echo "${latestAlarmVersion}"

    echo -n "Checking to see whether the latest version has already been downloaded..."
    if alreadyDownloaded "${architecture}" "${latestAlarmVersion}"; then
        echo "Done."
        echo "The latest version of phantomjs ($latestAlarmVersion) has already been downloaded."
    else
        echo "Done."
        echo -n "Downloading latest version..."
        download "${architecture}" "${latestAlarmVersion}" "${tmp}"
        echo "Done."
    fi
}

tmp="$(mktemp -d)"
for architecture in "aarch64" "arm" "armv6h" "armv7h"; do
    downloadAndPackage "${architecture}" "${tmp}"
done
rm -r $tmp

exit 0
