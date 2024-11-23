#!/bin/bash

# Define the repository URL and the branch
REPO_URL="https://github.com/koppulakoushik/version.git"
BRANCH="main"  # Update this to your actual branch name
LOCAL_DIR="/c/Users/kkoppula/OneDrive - e2open, LLC/Documents/javatask"  # Specified directory for cloning
FILENAME="versionfiles.txt"

# Add the directory to Git's safe list
git config --global --add safe.directory "$LOCAL_DIR"

# Clean up any existing directory
rm -rf "$LOCAL_DIR"

# Clone the repository
git clone -b "$BRANCH" "$REPO_URL" "$LOCAL_DIR"

# Change to the local repository directory
cd "$LOCAL_DIR" || { echo "Directory not found: $LOCAL_DIR"; exit 1; }

# Function to process a single line
process_line() {
    local PARAMS="$1"
    
    IFS=',' read -r version base flavor <<< "$PARAMS"
    local ver="${version}"
    local base="${base}"
    local FLAVOR="${flavor}"
    GITHUB_API_URI="https://api.github.com/repos/adoptium/temurin${ver}-binaries/releases/latest"
    GITHUB_URI="https://github.com/adoptium/temurin${ver}-binaries/releases/latest"
    
    # Fetch the latest version from GitHub API
    JAVA_LATEST_RELEASE=$(curl -L -s -H 'Accept: application/json' ${GITHUB_URI})
    JAVA_LATEST_VERSION=$(echo $JAVA_LATEST_RELEASE | sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/')

    echo "Checking the version file for version match"

    # Check if the latest version matches the specified flavor
    if [ "$JAVA_LATEST_VERSION" = "$FLAVOR" ]; then
        echo "There is no change to JDK Version today"
        # If the versions match, add the current line as is to updated_lines
        updated_lines+=("${ver},${base},${FLAVOR}")
    else
        echo "You have $JAVA_LATEST_VERSION available for download. Proceeding to add E2open CA Certs"

        # Construct the destination URLs
        local DEST_ARTIFACTORY_URL="https://artifactory.dev.e2open.com/artifactory/ext-libs-dev/com/java/${ver}/OpenJDKU-${base}_hotspot/latest"
        local DEST_ARTIFACTORY_URL2="https://artifactory.dev.e2open.com/artifactory/ext-libs-dev/com/java/${ver}/OpenJDK-${base}_hotspot/${JAVA_LATEST_VERSION}"

        echo "${DEST_ARTIFACTORY_URL}"
        echo "${DEST_ARTIFACTORY_URL2}"

        local NEW_FILE_NAME="OpenJDK-${base}_hotspot-${JAVA_LATEST_VERSION}.tar.gz"

        echo "${DEST_ARTIFACTORY_URL}/file"
        echo "${DEST_ARTIFACTORY_URL2}/${NEW_FILE_NAME}"

        # Update the version in the array with the new version
        updated_lines+=("${ver},${base},${JAVA_LATEST_VERSION}")
    fi
}

# Main script execution
if [[ -f "$FILENAME" ]]; then
    # Read the file into an array
    mapfile -t lines < "$FILENAME"
    updated_lines=()

    # Process each line
    for line in "${lines[@]}"; do
        line=$(echo "$line" | tr -d '\r')  # Remove any carriage return characters
        process_line "$line"
    done

    # Write the updated content back to the file
    printf "%s\n" "${updated_lines[@]}" > "$FILENAME"
    
    # Commit and push changes to the Git repository
    git add .
    git commit -m "Updated JDK versions"
    git push origin "$BRANCH"
else
    echo "File does not exist: $FILENAME"
fi
