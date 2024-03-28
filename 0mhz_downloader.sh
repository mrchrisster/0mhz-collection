#!/bin/bash

# Simple script to download DOS games and stay up to date with the 0mhz project


# Where should the games be installed? Change accordingly if you want games to be stored on usb
games_loc="/media/fat"


###### The rest of the script should probably not be changed 
base_dir="${games_loc}/games/AO486"

# Path for mgl files. Always on fat drive
dos_mgl="/media/fat/_DOS Games"



# Set your GitHub repository details and the folder path
USER_OR_ORG="0mhz-net"
REPO="0mhz-collection"
FOLDER_PATH="mgls"
BRANCH="main" 

# GitHub API URL for listing contents of the folder
API_URL="https://api.github.com/repos/$USER_OR_ORG/$REPO/contents/$FOLDER_PATH?ref=$BRANCH"

# Ensure the local directory exists
mkdir -p "$dos_mgl"
mkdir -p "$base_dir"

# Check available space on the device where base_dir is located
available_space_gb=$(df -BG "$base_dir" | awk 'NR==2 {print substr($4, 1, length($4)-1)}')

if [ "$available_space_gb" -lt 30 ]; then
    echo "Less than 30GB space available in $base_dir. Aborting."
    exit 1
fi

# Navigate to the local directory
cd "$dos_mgl"

# Fetch the list of files in the remote folder via GitHub's API
curl --insecure -s "$API_URL" | jq -r '.[] | select(.type=="file") | .download_url' | while read file_url; do
    # URL decode the file name for local use/display.
    # Note: This requires Perl for URL decoding.
    file_name=$(basename "$file_url" | perl -pe 's/%([0-9A-F]{2})/chr(hex($1))/eg')

    # Check if the file already exists locally
    if [ ! -f "$file_name" ]; then
        echo "Downloading $file_name..."
        # Download the file using the encoded URL
        curl --insecure -s -o "$file_name" "$file_url"
    else
        echo "$file_name already exists, skipping."
    fi
done

echo "Synchronization complete."
echo "Checking if files exist"

mgl_dir="$dos_mgl"

# Initialize an array to hold the names of .mgl files with missing paths
mgl_with_missing_paths=()

# Loop through all .mgl files in the mgl_dir
for mgl_file in "$mgl_dir"/*.mgl; do

    # Extract paths using grep and sed. This is less reliable than xmllint and assumes well-formed input.
    paths=$(grep -o 'path="[^"]*"' "$mgl_file" | sed 's/path="\(.*\)"/\1/')

    if [ -z "$paths" ]; then
        echo "No paths found in $mgl_file."
        continue
    fi

    has_missing_paths=false
    # Check each path
    while IFS= read -r path; do
        # Trim leading and trailing spaces from the path
        trimmed_path=$(echo "$path" | sed 's/^ *//;s/ *$//')

        # Construct the full path
        full_path="${base_dir}/${trimmed_path}"

        echo "Checking existence of: $full_path"

        # Check if the file exists
        if [ ! -f "$full_path" ]; then
            echo "Missing: $trimmed_path"
            has_missing_paths=true
        else
            echo "Found: $trimmed_path"
        fi
    done <<< "$paths"

    # If the file has missing paths, add its name to the array
    if [ "$has_missing_paths" = true ]; then
        mgl_with_missing_paths+=("$(basename "$mgl_file")")
    fi
done

# Check if any .mgl files with missing paths were found
if [ ${#mgl_with_missing_paths[@]} -eq 0 ]; then
    echo "No .mgl files with missing paths were found."
else
	echo ""
    echo "List of .mgl files with missing files:"
    for mgl_file in "${mgl_with_missing_paths[@]}"; do
        echo "$mgl_file"
    done
fi


# URL of the online XML file
xml_url="https://archive.org/download/0mhz-dos/0mhz-dos_files.xml"

# Fetch the XML file and extract all file names
file_names=$(curl --insecure -L -s "$xml_url" | xmllint --xpath '//file/@name' - | sed -e 's/name="\([^"]*\)"/\1\n/g')

# Iterate through the mgl_with_missing_paths array
for mgl_file in "${mgl_with_missing_paths[@]}"; do
    # Replace the .mgl extension with .zip for each file
    zip_name="${mgl_file%.mgl}.zip"

    # Check if the .zip version exists in the file names
    if echo "$file_names" | fgrep -qi "$zip_name"; then
		echo ""
        echo "Downloading missing zip: $zip_name"
        # Print the download link for the .zip file
        dl_zip="$(echo https://archive.org/download/0mhz-dos/"$zip_name" | sed 's/ /%20/g')"
		mkdir -p ${base_dir}/tmpdownload
		curl --insecure -L -# -o "${base_dir}/tmpdownload/$zip_name" "$dl_zip"		
		if unzip -o "$base_dir/tmpdownload/${zip_name}" -d "$games_loc"; then
			echo "Unzipped $zip_name successfully."
			rm "$base_dir/tmpdownload/${zip_name}"
		else
			echo "Error unzipping $zip_file."
		fi		
    fi
done
