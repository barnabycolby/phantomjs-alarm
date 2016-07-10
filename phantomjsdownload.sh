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

# Should be the location of a folder without the trailing /
downloadLocation='/data/dist/phantomjs'

# Checks whether a given string matches the expected pattern for PhantomJS versioning
isValidVersionNumber() {
    stringToCheck=$1
    versionRegex="^[0-9]+\.[0-9]+\.[0-9]+(\$|-[0-9]+)"

    if [ -n "${stringToCheck}" ] && echo "${stringToCheck}" | grep -Eq "${versionRegex}" ;then
        return 0
    else
        return 1
    fi
}

# Scrapes the ALARM package page for the available versions of phantomjs and returns them as a list
scrapePageForVersions() {
    local architecture=$1
    local page=$2

    local versions=$(curl "${page}" -L -s | grep "phantomjs-.*-${architecture}.pkg.tar.xz<" | sed -e 's/^.*<a href="phantomjs-//' | sed -e "s/-${architecture}.*$//")
    
    local sanitisedVersions=""
    for version in $versions; do
        # Only add versions to the sanitised list if they are valid version numbers
        if isValidVersionNumber "${version}"; then
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

    echo -n "- Checking to see whether the latest version has already been downloaded..."

    local filename="${downloadLocation}/phantomjs-${version}-linux-${architecture}.tar.bz2"
    if [ -f $filename ]; then
        echo "Done."
        echo "- The latest version of phantomjs ($latestAlarmVersion) for the ${architecture} architecture has already been downloaded."
        return 0
    else
        echo "Done."
        return 1
    fi
}

stripAlarmVersioning() {
    local alarmVersion=$1
    echo "$(echo ${alarmVersion} | sed -e 's/-.*//')"
}

# Given an alarm version number, returns 1 if it is the latest downloaded alarm subversion of the package and 0 otherwise
isLatestVersion() {
    local alarmVersion=$1
    local architecture=$2
    local version="$(stripAlarmVersioning ${alarmVersion})"

    # Just the alarm version i.e. 2.1.1-3 -> 3
    local alarmVersionToCheck="$(echo "$alarmVersion" | sed -e 's/.*-//g')"

    local prefix="${downloadLocation}/phantomjs-${version}"
    local suffix="linux-${architecture}.tar.bz2"
    local escapedPrefix="$(echo "${prefix}" | sed -e 's/\//\\\//g')"
    local escapedSuffix="$(echo "${suffix}" | sed -e 's/\./\\\./g')"
    local filesWithSameArchitectureAndVersion="$(ls -1 ${prefix}-*-${suffix})"
    for file in ${filesWithSameArchitectureAndVersion}; do
        alarmVersionForFile="$(echo "$(echo ${file} | sed -e "s/${escapedPrefix}-//g" | sed -e "s/-${escapedSuffix}//g")")"
        if (( alarmVersionForFile > alarmVersionToCheck )); then
            return 1
        fi
    done

    # If we reach this point then none of the version numbers were greater, therefore the version we are checking must be the latest
    return 0
}

# The version to download from Arch Linux ARM should be passed as the first argument
# The version to create should be passed as the second argument
# Note that these values may differ if the Arch Linux ARM packages have been patched
downloadAndPackage() {
    local architecture=$1
    local alarmVersion=$2
    local tmpRoot=$3
    local page=$4

    # Create the tmp directory
    local tmp="${tmpRoot}/${architecture}-${alarmVersion}"
    mkdir $tmp

    # Download and extract the Arch Linux ARM package
    local pkgFilename="phantomjs-${alarmVersion}-${architecture}.pkg.tar.xz"
    local archiveDownloadLocation=${tmp}/${pkgFilename}
    echo -n "- Downloading the Arch Linux ARM package..."
    wget --quiet "${page}/${pkgFilename}" -O ${archiveDownloadLocation}
    tar xJf ${archiveDownloadLocation} -C ${tmp} usr/bin/phantomjs --strip-components=2
    echo "Done."

    # Package the binary
    package ${architecture} ${alarmVersion} ${tmpRoot} ${tmp} ${tmp}/phantomjs

    # Remove the tmp directory for this particular architecture/version combination to save space
    rm -r ${tmp}
}

package() {
    local architecture=$1
    local alarmVersion=$2
    local tmpRoot=$3
    local tmp=$4
    local binaryLocation=$5

    local version="$(stripAlarmVersioning ${alarmVersion})"

    # Create the required directories
    local alarmDirPath="${tmp}/alarm"
    local outputDir="phantomjs-${version}-linux-${architecture}"
    local outputDirPath="${tmp}/${outputDir}"
    local releaseFilesDirPath="${tmp}/releaseFiles"
    mkdir $alarmDirPath
    mkdir $outputDirPath
    mkdir $releaseFilesDirPath

    # Download and extract the release files (for the changelog and readme), if it is not already downloaded
    releaseFilesFilenameNoExtension="phantomjs-${version}"
    releaseFilesFilename="${releaseFilesFilenameNoExtension}.tar.gz"
    releaseFilesFilePath="${tmpRoot}/${releaseFilesFilename}"
    if [ ! -f ${releaseFilesFilePath} ]; then
        echo -n "- Downloading the official PhantomJS source release (for README, ChangeLog, licenses and examples)..."
        wget --quiet "https://github.com/ariya/phantomjs/archive/${version}.tar.gz" -O ${releaseFilesFilePath}
        echo "Done."
    fi

    # Construct the phantomjs output folder by extracting the required components to the appropriate directory
    echo -n "- Constructing the output directory by extracting the required components..."
    mkdir ${outputDirPath}/bin
    cp ${binaryLocation} ${outputDirPath}/bin/phantomjs
    tar xzf ${releaseFilesFilePath} -C ${outputDirPath}/ ${releaseFilesFilenameNoExtension}/examples --strip-components=1
    tar xzf ${releaseFilesFilePath} -C ${outputDirPath}/ ${releaseFilesFilenameNoExtension}/third-party.txt --strip-components=1
    tar xzf ${releaseFilesFilePath} -C ${outputDirPath}/ ${releaseFilesFilenameNoExtension}/LICENSE.BSD --strip-components=1
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
    if [ "${alarmVersion}" != "${version}" ] && isLatestVersion "${alarmVersion}" "${architecture}"; then
        echo -n "- Creating symlink file without the extra Arch Linux ARM versioning..."
        local outputFileNoAlarmVersioning="${outputDir}.${outputArchiveExtension}"
        ln -sf ${downloadLocation}/${outputArchive} ${downloadLocation}/${outputFileNoAlarmVersioning}
        echo "Done."
    fi
}

# If the latest version has not already been downloaded, it is downloaded and packaged for use
# The architecture to download and package for should be given as the first argument (something like "armv7h")
downloadAndPackageIfNotAlreadyArchived() {
    local architecture=$1
    local tmp=$2
    local latestAlarmVersion=$3
    local page=$4

    if ! alreadyDownloaded "${architecture}" "${latestAlarmVersion}"; then
        downloadAndPackage "${architecture}" "${latestAlarmVersion}" "${tmp}" "${page}"
    fi
}

# Make tmp directory to perform work in
tmpRoot="$(mktemp -d)"

# If 0 or 1 arguments were given then we are to scrape a URL for all available downloads and package them
if [ $# -lt 2 ]; then
    for architecture in "aarch64" "arm" "armv6h" "armv7h"; do
        # The user can specify a custom URL to look for and download the arch packages from
        # The %/ ensures that the URL does not have a trailing slash (required by the script)
        userSpecifiedPage=${1%/}

        # Decide which URL to use
        if [ -z "${userSpecifiedPage}" ]; then
            page="http://mirror.archlinuxarm.org/${architecture}/community"
        else
            page=${userSpecifiedPage}
        fi

        for version in $(scrapePageForVersions ${architecture} ${page}); do
            echo "${architecture} ${version}"
            downloadAndPackageIfNotAlreadyArchived "${architecture}" "${tmpRoot}" "${version}" "${page}"
        done
    done
# If given 3 arguments then we are to package a given binary from the command line
elif [ $# -eq 3 ]; then
    pathToBinary=$1
    version=$2
    architecture=$3

    # First, we must check that the path to the binary is an actual file
    if [ ! -f ${pathToBinary} ]; then
        echo "I can't find the PhantomJS binary, the given path should be accessible from the location that this script is run from."
        exit 1
    fi

    # Then we must check that the given version number is valid
    if ! isValidVersionNumber "${version}"; then
        echo "The version number did not match the expected pattern. It should look something like '2.1.1' or '2.1.1-3'."
        exit 1
    fi

    echo "${architecture} ${version}"

    if ! alreadyDownloaded "${architecture}" "${version}"; then
        # Create the tmp directory
        tmp="${tmpRoot}/${architecture}-${alarmVersion}"
        mkdir $tmp

        # Package the binary
        package ${architecture} ${version} ${tmpRoot} ${tmp} ${pathToBinary}

        rm -r $tmp
    fi
else
    echo "I don't know what to do with that many arguments! Please read the README at https://github.com/barnabycolby/phantomjs-alarm"
fi

rm -r $tmpRoot

exit 0
