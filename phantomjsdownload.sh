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

# Once the PhantomJS binary has been packaged, the resulting archive will be placed in this location
downloadLocation='/data/dist/phantomjs'

# Checks whether a given string matches the expected pattern for PhantomJS versioning
# For example, '2.1.1' and '2.1.1-3' returns true and 'beans' returns false
#
# $1 -> The string to check
isValidVersionNumber() {
    stringToCheck=$1
    versionRegex="^[0-9]+\.[0-9]+\.[0-9]+(\$|-[0-9]+)"

    if [ -n "${stringToCheck}" ] && echo "${stringToCheck}" | grep -Eq "${versionRegex}" ;then
        return 0
    else
        return 1
    fi
}

# Scrapes a given URL for available versions of PhantomJS arch packages, and returns the version numbers as a list
# 
# $1 -> The architecture to look for e.g. armv7h/aarch64/...
# $2 -> The URL to scrape
scrapePageForVersions() {
    local architecture=$1
    local page=$2

    # Retrieves a list of version numbers
    local versions=$(curl "${page}" -L -s | grep "phantomjs-.*-${architecture}.pkg.tar.xz<" | sed -e 's/^.*<a href="phantomjs-//' | sed -e "s/-${architecture}.*$//")
    
    # We sanitise the version numbers just to be safe
    local sanitisedVersions=""
    for version in $versions; do
        if isValidVersionNumber "${version}"; then
            sanitisedVersions+="${version} "
        fi
    done

    echo "${sanitisedVersions}"
}

# Checks to see whether a specific architecture and version of PhantomJS has already been archived
# Returns true if it has, false otherwise
#
# $1 -> architecture to check e.g. 'armv7h'/'aarch64'/...
# $2 -> version number to check e.g. 2.1.1
alreadyDownloaded() {
    local architecture=$1
    local version=$2

    echo -n "- Checking to see whether the latest version has already been downloaded..."

    local filename="${downloadLocation}/phantomjs-${version}-linux-${architecture}.tar.bz2"
    if [ -f $filename ]; then
        echo "Done."
        echo "- The latest version of phantomjs ($version) for the ${architecture} architecture has already been downloaded."
        return 0
    else
        echo "Done."
        return 1
    fi
}

# Strips the extra version numbers sometimes added by the Arch package system
# i.e. 2.1.1-3 -> 2.1.1
#
# $1 -> The version number to strip
stripAlarmVersioning() {
    local alarmVersion=$1
    echo "$(echo ${alarmVersion} | sed -e 's/-.*//')"
}

# The Arch packaging system adds extra version information on top of the PhantomJS official version numbers, for example 2.1.1 -> 2.1.1-3
# Given the full Arch version number, this function returns true if it is later than the already archived packages with the SAME PhantomJS version# number, and false otherwise
#
# $1 -> The alarm version number to check
# $2 -> The architecture of the packages to compare against
isLatestVersion() {
    local alarmVersion=$1
    local architecture=$2
    local version="$(stripAlarmVersioning ${alarmVersion})"

    # Strips the leading official PhantomJS version, leaving just the alarm version number i.e. 2.1.1-3 -> 3
    local alarmVersionToCheck="$(echo "$alarmVersion" | sed -e 's/.*-//g')"

    local prefix="${downloadLocation}/phantomjs-${version}"
    local suffix="linux-${architecture}.tar.bz2"
    local escapedPrefix="$(echo "${prefix}" | sed -e 's/\//\\\//g')"
    local escapedSuffix="$(echo "${suffix}" | sed -e 's/\./\\\./g')"
    local filesWithSameArchitectureAndVersion="$(ls -1 ${prefix}-*-${suffix})"
    for file in ${filesWithSameArchitectureAndVersion}; do
        # Strips the leading official PhantomJS version, leaving just the alarm version number i.e. 2.1.1-3 -> 3
        alarmVersionForFile="$(echo "$(echo ${file} | sed -e "s/${escapedPrefix}-//g" | sed -e "s/-${escapedSuffix}//g")")"
        if (( alarmVersionForFile > alarmVersionToCheck )); then
            return 1
        fi
    done

    # If we reach this point then none of the version numbers were greater, therefore the version we are checking must be the latest
    return 0
}

# Downloads the specified arch package from the given web directory, packages it in the PhantomJS manner and places the resulting archive in the
# appropriate place
#
# $1 -> The architecture of the package to retrieve e.g. 'armv7h'/'aarch64'
# $2 -> The version number of the package to download
# $3 -> The temporary directory to work in
# $4 -> The web folder URL to download packages from, this must not have a trailing slash
downloadAndPackage() {
    local architecture=$1
    local alarmVersion=$2
    local tmpRoot=$3
    local page=$4

    # Create a new tmp directory inside the root tmp directory
    # This prevents conflicts with other instances of this function
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

    # Remove the tmp directory we created earlier, in order to use disk space more efficiently
    rm -r ${tmp}
}

# Packages a given PhantomJS binary in the same way as the official PhantomJS downloads are packaged, placing the resulting archive in the
# specified download location
#
# $1 -> The target architecture of the binary
# $2 -> The version number of the binary. This should be the full Arch version number where possible.
# $3 -> The root temporary directory to work in
# $4 -> The temporary directory for this particular architecture & version number combination
# $5 -> The path of the PhantomJS binary
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

    # Download and extract the official PhantomJS release files (for the changelog, readme, licenses, examples etc.)
    # If a binary with the same version but targeting a different architecture has already been downloaded, then this archive may already be
    # present in the root temporary directory
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
    # We need to make sure that the binary is executable
    chmod +x ${outputDirPath}/bin/phantomjs
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

    # Most users will be looking for PhantomJS packages using the official PhantomJS versioning system, however, as this script archives each of
    # the available Arch Linux versions, they may not find the version number exactly as expected. To solve this problem, we create a symbolic
    # link using the official PhantomJS version number that points to the latest package using the Arch versioning system. Care is taken to
    # ensure that the link is not overwritten if the package being processed is NOT the latest Arch version available in the download location.
    if [ "${alarmVersion}" != "${version}" ] && isLatestVersion "${alarmVersion}" "${architecture}"; then
        echo -n "- Creating symlink file without the extra Arch Linux ARM versioning..."
        local outputFileNoAlarmVersioning="${outputDir}.${outputArchiveExtension}"
        ln -sf ${downloadLocation}/${outputArchive} ${downloadLocation}/${outputFileNoAlarmVersioning}
        echo "Done."
    fi
}

# Downloads and packages the arch package with the specified architecture and version number, available from the given URL, ONLY IF it is not
# already archived.
#
# $1 -> The architecture of the package to download.
# $2 -> The version number of the package to download.
# $3 -> The temporary directory to work in.
# $4 -> The URL of the directory to download packages from.
downloadAndPackageIfNotAlreadyArchived() {
    local architecture=$1
    local version=$2
    local tmp=$3
    local page=$4

    if ! alreadyDownloaded "${architecture}" "${version}"; then
        downloadAndPackage "${architecture}" "${version}" "${tmp}" "${page}"
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
            # If the user did not specify a download URL, then we use the official Arch Linux ARM package mirror
            page="http://mirror.archlinuxarm.org/${architecture}/community"
        else
            page=${userSpecifiedPage}
        fi

        for version in $(scrapePageForVersions ${architecture} ${page}); do
            echo "${architecture} ${version}"
            downloadAndPackageIfNotAlreadyArchived "${architecture}" "${version}" "${tmpRoot}" "${page}"
        done
    done
# If given 3 arguments then we are to package a binary whose path is passed as the 1st argument
elif [ $# -eq 3 ]; then
    pathToBinary=$1
    version=$2
    architecture=$3

    # First, we must check that the path to the binary points to a file that actually exists
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
