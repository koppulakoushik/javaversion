#!/bin/bash

# Define the repository URL and the branch
REPO_URL="https://github.com/koppulakoushik/version.git"
BRANCH="main"  # Update this to your actual branch name
LOCAL_DIR="/tmp/version-repo"  # Directory for cloning the repository
FILENAME="versionfiles.txt"
 # New file where updated lines will be saved
git config --global --add safe.directory "$LOCAL_DIR"

# Clean up any existing directory
if [ -d "$LOCAL_DIR" ]; then
    echo "Directory exists. Attempting to remove it."
    rm -rf "$LOCAL_DIR" || { echo "Failed to remove directory: $LOCAL_DIR. Please check NFS or lock issues."; exit 1; }
fi

# Clone the repository
git clone -b "$BRANCH" "$REPO_URL" "$LOCAL_DIR"

# Change to the local repository directory
cd "$LOCAL_DIR" || { echo "Directory not found: $LOCAL_DIR"; exit 1; }

# Function to process a single line for non-ppc64le architectures
process_non_ppc64le() {
    local PARAMS="$1"
    IFS=',' read -r version base flavor <<< "$PARAMS"
    local ver="${version}"
    local base="${base}"
    local JDK_VERSION="${flavor}"
    BASEPATH=$(pwd)

    GITHUB_API_URI="https://api.github.com/repos/adoptium/temurin${ver}-binaries/releases/latest"
    GITHUB_URI="https://github.com/adoptium/temurin${ver}-binaries/releases/latest"
    JAVA_LATEST_RELEASE=$(curl -L -s -H 'Accept: application/json' ${GITHUB_URI})
    JAVA_LATEST_VERSION=$(echo $JAVA_LATEST_RELEASE | sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/')
    ARTIFACT_USER="devops_art_rw"
    ARTIFACT_PASS="<PASSWORD>"

    # Path to Alpine certificates
    PATH_TO_ALPINE_CA_CERTS_FILE_11="/tmp/alpinecerts/cacerts_11"
    PATH_TO_ALPINE_CA_CERTS_FILE_17="/tmp/alpinecerts/cacerts_17"

    echo "Checking the version file for version match"
    if [ "$JDK_VERSION" = "$JAVA_LATEST_VERSION" ]; then
        echo "There is no change to JDK Version today"
        updated_lines+=("${ver},${base},${JDK_VERSION}")
    else
        echo "You have $JAVA_LATEST_VERSION available for download. Proceeding to add E2open CA Certs"

        ARTIFACT=$(curl -s ${GITHUB_API_URI} | grep browser_download_url | grep -v debugimage | grep -v sources | grep ${base} | grep tar.gz | head -1 | awk -F / '{print $NF}' | sed 's/.$//')
        ARTIFACT_URL="https://github.com/adoptium/temurin${ver}-binaries/releases/download/${JAVA_LATEST_VERSION}/${ARTIFACT}"
        ARTIFACTORY_CERT_PATH="https://artifactory.dev.e2open.com/artifactory/ext-libs-dev/jdk_truststore/certs/e2open_CAs.zip"

        # Clean up any old directories
        cd ${BASEPATH}
        rm -rf ${BASEPATH}/java ${BASEPATH}/certs
        mkdir -p java certs
        cd certs

        # Download certificates
        wget ${ARTIFACTORY_CERT_PATH}
        if [ $? -ne 0 ]; then
            echo "Error while downloading the certificates"
            exit 1
        fi
        CERT_ZIPFOLDER="`echo ${ARTIFACTORY_CERT_PATH} | rev | cut -d '/' -f1 | rev`"
        unzip ${CERT_ZIPFOLDER}
        echo "Downloading the latest certificates completed."

        # Download and extract the JDK artifact
        cd ../java
        wget ${ARTIFACT_URL}
        if [ $? -ne 0 ]; then
            echo "Error while downloading the latest version."
            exit 1
        fi
        
        tar -xvzf ${ARTIFACT}
        echo "Downloading and extracting the JDK completed."

        # Prepare for certificate import
        FOLDER="`ls -d */ | cut -d '/' -f1`"
        VERSION="`echo ${FOLDER} | cut -d '-' -f2`"
        NUMBER="`echo ${VERSION} | cut -d '.' -f1`"
        rm -f ${ARTIFACT}

        cd ${FOLDER}
        
        if [[ "${base}" =~ "alpine" ]]; then
            # Import CA certs for Alpine
            if [[ "${ver}" =~ "11" ]]; then
                echo -n "Alpine - Importing CA CERTS from ${PATH_TO_ALPINE_CA_CERTS_FILE_11}"
                cp -f ${PATH_TO_ALPINE_CA_CERTS_FILE_11} lib/security/cacerts
            fi
            if [[ "${ver}" =~ "17" ]]; then
                echo -n "Alpine - Importing CA CERTS from ${PATH_TO_ALPINE_CA_CERTS_FILE_17}"
                cp -f ${PATH_TO_ALPINE_CA_CERTS_FILE_17} lib/security/cacerts
            fi
        else
            # Import CA certs for Linux
            echo -n "Importing into CA CERTS for Linux - primaryCAsha2G2"
            bin/keytool -importcert -cacerts -storepass changeit -file $BASEPATH/certs/E2primaryCAsha2G2.crt -alias e2openrootg2 -noprompt
            echo -n "Importing into CA CERTS for Linux - intCAsha2G2"
            bin/keytool -importcert -cacerts -storepass changeit -file $BASEPATH/certs/E2ServerCAsha2G2.crt -alias e2openintermediateg2 -noprompt
            echo -n "Importing into CA CERTS for Linux - CAG3"
            bin/keytool -importcert -cacerts -storepass changeit -file $BASEPATH/certs/E2ServerCAG3.crt -alias e2openintermediateg3 -noprompt
        fi

        # Prepare the final zip file
        LATEST_ZIPNAME="OpenJDK${NUMBER}U-${flavor}_hotspot-latest.tar.gz"
        cd ..
        tar -cvzf ${LATEST_ZIPNAME} ${FOLDER}
        echo "Zip with latest version and certs completed."

        local DEST_ARTIFACTORY_URL="https://artifactory.dev.e2open.com/artifactory/ext-libs-dev/com/java/${ver}/OpenJDKU-${base}_hotspot/latest"
        local DEST_ARTIFACTORY_URL2="https://artifactory.dev.e2open.com/artifactory/ext-libs-dev/com/java/${ver}/OpenJDK-${base}_hotspot/${JAVA_LATEST_VERSION}"

        echo ${DEST_ARTIFACTORY_URL}
        echo ${DEST_ARTIFACTORY_URL2}

        # Find and upload the artifact files
        for file in $(find . -name "*.gz" 2>/dev/null | cut -d '/' -f2)
        do
            NEW_FILE_NAME="OpenJDK${NUMBER}U-${base}_hotspot-${JAVA_LATEST_VERSION}.tar.gz"
            cp ${file} ${NEW_FILE_NAME}
            echo  "${ARTIFACT_USER}:${ARTIFACT_PASS} -T ${file} ${DEST_ARTIFACTORY_URL}/${file}"
            echo  "${ARTIFACT_USER}:${ARTIFACT_PASS} -T ${NEW_FILE_NAME} ${DEST_ARTIFACTORY_URL2}/${NEW_FILE_NAME}"
            updated_lines+=("${ver},${base},${JAVA_LATEST_VERSION}")
        done
    fi
}
# Function to process a single line for ppc64le architectures
process_ppc64le() {
    local PARAMS="$1"
    IFS=',' read -r version base flavor <<< "$PARAMS"
    local ver="${version}"
    local base="${base}"
    local JDK_VERSION="${flavor}"
    BASEPATH=$(pwd)

    GITHUB_API_URI="https://api.github.com/repos/adoptium/temurin${ver}-binaries/releases/latest"
    GITHUB_URI="https://github.com/adoptium/temurin${ver}-binaries/releases/latest"
    JAVA_LATEST_RELEASE=$(curl -L -s -H 'Accept: application/json' ${GITHUB_URI})
    JAVA_LATEST_VERSION=$(echo $JAVA_LATEST_RELEASE | sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/')

    ARTIFACT_USER="devops_art_rw"
    ARTIFACT_PASS="<PASSWORD>"


    echo "Checking the version file for version match"
    if [ "$JDK_VERSION" = "$JAVA_LATEST_VERSION" ]; then
        echo "There is no change to JDK Version today"
        updated_lines+=("${ver},${base},${JDK_VERSION}")
    else
        echo "You have $JAVA_LATEST_VERSION available for download."

        ARTIFACT=$(curl -s ${GITHUB_API_URI} | grep browser_download_url | grep -v debugimage | grep -v sources | grep ${base} | grep tar.gz | head -1 | awk -F / '{print $NF}' | sed 's/.$//')
        ARTIFACT_URL="https://github.com/adoptium/temurin${ver}-binaries/releases/download/${JAVA_LATEST_VERSION}/${ARTIFACT}"

        # Clean up any old directories
        cd ${BASEPATH}
        rm -rf ${BASEPATH}/java ${BASEPATH}/certs
        mkdir -p java certs
       

        # Skip certificates download for ppc64le
        echo "Skipping certificate download for ppc64le architecture"

        # Download and extract the JDK artifact only for ppc64le
        cd java
        wget ${ARTIFACT_URL}
        echo "JDK downloaded "

        # Upload the artifact to Artifactory
        local DEST_ARTIFACTORY_URL="https://artifactory.dev.e2open.com/artifactory/ext-libs-dev/com/java/${ver}/OpenJDKU-${base}_hotspot/latest"
        local DEST_ARTIFACTORY_URL2="https://artifactory.dev.e2open.com/artifactory/ext-libs-dev/com/java/${ver}/OpenJDK-${base}_hotspot/${JAVA_LATEST_VERSION}"

        echo ${DEST_ARTIFACTORY_URL}
        echo ${DEST_ARTIFACTORY_URL2}

       for file in $(find . -name "*.tar.gz" 2>/dev/null)
       do
          echo "Processing file: $file"
          NEW_FILE_NAME="OpenJDK${ver}U-${base}_hotspot-${JAVA_LATEST_VERSION}.tar.gz"
          cp ${file} ${NEW_FILE_NAME}
          if [ $? -eq 0 ]; then
              echo "File copied successfully to ${NEW_FILE_NAME}"
          else
             echo "Error copying file ${file}"
          fi
         echo  "${ARTIFACT_USER}:${ARTIFACT_PASS} -T ${file} ${DEST_ARTIFACTORY_URL}/${file}"
         echo  "${ARTIFACT_USER}:${ARTIFACT_PASS} -T ${NEW_FILE_NAME} ${DEST_ARTIFACTORY_URL2}/${NEW_FILE_NAME}"
         updated_lines+=("${ver},${base},${JAVA_LATEST_VERSION}")
       done

    fi
}


# Read and process each line from the versionfiles.txt
if [[ -f "$FILENAME" ]]; then
    mapfile -t lines < "$FILENAME"
    updated_lines=()

    # Process each line from the versionfile
    for line in "${lines[@]}"; do
        line=$(echo "$line" | tr -d '\r')  # Remove any carriage return characters
        IFS=',' read -r version base flavor <<< "$line"
        if [[ "${base}" =~ "ppc64le" ]]; then
            process_ppc64le "$line"
        else
            process_non_ppc64le "$line"
        fi
    done

    # Create a new version.txt and overwrite it with the updated content
    printf "%s\n" "${updated_lines[@]}" > "${LOCAL_DIR}/${FILENAME}"
    echo "Updated version.txt with the processed entries."
    # Add versionfiles.txt to git staging
    git add "${LOCAL_DIR}/${FILENAME}"

    # Commit the changes with a message
    git commit -m "Updated JDK versions in versionfiles.txt"

    # Push the changes to the remote repository on the specified branch
    git push origin "$BRANCH"

else
    echo "File does not exist: $FILENAME"
fi
