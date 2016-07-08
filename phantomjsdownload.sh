#!/bin/bash

# Exit immediately on error, printing a failure message containing the error code
set -o errexit
set -o errtrace
printErrorMessage() {
    lineNumber=$1
    errorCode=$2
    echo "The script failed with error code ${errorCode} on line ${lineNumber}."
}
trap 'printErrorMessage ${LINENO} ${?}' ERR

# Exit if the script tries to use an uninitialised variable (this usually indicates error)
set -o nounset

# Should be the location of a folder without the trailing /
downloadLocation='/data/dist/phantomjs'

# Scrapes the ALARM package page for the available versions of phantomjs and returns them as a list
scrapePageForVersions() {
    local architecture=$1
    local page="http://mirror.archlinuxarm.org/${architecture}/community/"
    local versions=$(curl "${page}" -L -s | grep "phantomjs-.*-${architecture}.pkg.tar.xz<" | sed -e 's/^.*<a href="phantomjs-//' | sed -e "s/-${architecture}.*$//")
    
    local sanitisedVersions=""
    for version in $versions; do
        # Check that the version number is valid
        versionRegex="^[0-9]+\.[0-9]+\.[0-9]+(\$|-[0-9]+)"

        # Only add versions to the sanitised list if they match the regex
        if [ -n "$version" ] && echo "$version" | grep -Eq "$versionRegex" ;then
            sanitisedVersions+="${version} "
        fi
    done

    echo "${sanitisedVersions}"
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
    local releaseFilesDirPath="${tmp}/releaseFiles"
    mkdir $tmp
    mkdir $alarmDirPath
    mkdir $outputDirPath
    mkdir $releaseFilesDirPath

    # Download and extract the Arch Linux ARM package
    local pkgFilename="phantomjs-${alarmVersion}-${architecture}.pkg.tar.xz"
    echo -n "- Downloading the Arch Linux ARM package..."
    wget --quiet "http://mirror.archlinuxarm.org/${architecture}/community/${pkgFilename}" -O ${tmp}/${pkgFilename}
    echo "Done."

    # Download and extract the release files (for the changelog and readme), if it is not already downloaded
    releaseFilesFilenameNoExtension="phantomjs-${version}"
    releaseFilesFilename="${releaseFilesFilenameNoExtension}.tar.gz"
    releaseFilesFilePath="${tmpRoot}/${releaseFilesFilename}"
    if [ ! -f ${releaseFilesFilePath} ]; then
        echo -n "- Downloading the official PhantomJS source release (for README and ChangeLog)..."
        wget --quiet "https://github.com/ariya/phantomjs/archive/${version}.tar.gz" -O ${releaseFilesFilePath}
        echo "Done."
    fi

    # Construct the phantomjs output folder by extracting the required components to the appropriate directory
    echo -n "- Constructing the output directory by extracting the required components..."
    tar xJf ${tmp}/${pkgFilename} -C ${outputDirPath}/ usr/bin --strip-components=1
    tar xJf ${tmp}/${pkgFilename} -C ${outputDirPath}/ usr/share/phantomjs/examples --strip-components=3
    tar xJf ${tmp}/${pkgFilename} -C ${outputDirPath}/ usr/share/licenses/phantomjs --strip-components=4
    tar xzf ${releaseFilesFilePath} -C ${outputDirPath}/ ${releaseFilesFilenameNoExtension}/README.md --strip-components=1
    tar xzf ${releaseFilesFilePath} -C ${outputDirPath}/ ${releaseFilesFilenameNoExtension}/ChangeLog --strip-components=1
    echo "Done."

    # Compress the output folder
    local outputArchiveExtension="tar.bz2"
    local outputArchive="phantomjs-${alarmVersion}-linux-${architecture}.${outputArchiveExtension}"
    local outputFile="${tmp}/${outputArchive}"
    echo -n "- Compressing the output directory..."
    tar cjf ${outputFile} --directory=${tmp} ${outputDir}
    echo "Done."

    # Move the output archive to the appropriate location
    echo -n "- Moving the output archive to the final destination..."
    mv ${outputFile} ${downloadLocation}
    echo "Done."

    # Symbolically link the latest phantomjs version to the latest ALARM version
    if [ "${alarmVersion}" != "${version}" ]; then
        echo -n "- Creating symlink file without the extra Arch Linux ARM versioning..."
        local outputFileNoAlarmVersioning="${outputDir}.${outputArchiveExtension}"
        ln -sf ${downloadLocation}/${outputArchive} ${downloadLocation}/${outputFileNoAlarmVersioning}
        echo "Done."
    fi
}

# If the latest version has not already been downloaded, it is downloaded and packaged for use
# The architecture to download and package for should be given as the first argument (something like "armv7h")
downloadAndPackage() {
    local architecture=$1
    local tmp=$2
    local latestAlarmVersion=$3

    echo -n "- Checking to see whether the latest version has already been downloaded..."
    if alreadyDownloaded "${architecture}" "${latestAlarmVersion}"; then
        echo "Done."
        echo "- The latest version of phantomjs ($latestAlarmVersion) for the ${architecture} architecture has already been downloaded."
    else
        echo "Done."
        download "${architecture}" "${latestAlarmVersion}" "${tmp}"
    fi
}

tmp="$(mktemp -d)"
for architecture in "aarch64" "arm" "armv6h" "armv7h"; do
    echo "${architecture}"

    for version in $(scrapePageForVersions ${architecture}); do
        downloadAndPackage "${architecture}" "${tmp}" "${version}"
    done
done
rm -r $tmp

# Before exiting, we need to reset the EXIT trap to prevent a failure message from being printed
exit 0
