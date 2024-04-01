#!/bin/bash

# Simple script to download DOS games and stay up to date with the 0mhz project
# Checks Github for new mgl files and then checks archive to download those zip files.
# Please visit https://0mhz.net/ for more info

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# Copyright 2024 mrchrisster


# Where should the games be installed? Change accordingly if you want games to be stored on usb
games_loc="/media/fat"

# Path for mgl files. Should be on /media/fat drive.
dos_mgl="/media/fat/_DOS Games"

#Cleanup files in /media directory. If a file 
delete_unmatched_files=false

# Always download fresh copies of mgl's to assure we stay up to date
always_dl_mgl=false


###### The rest of the script should probably not be changed 

base_dir="${games_loc}/games/AO486"

# URL of the 0mhz archive.org XML file
xml_url="https://archive.org/download/0mhz-dos/0mhz-dos_files.xml"

# 0mhz GitHub API URL for listing contents of the mgls folder
api_url="https://api.github.com/repos/0mhz-net/0mhz-collection/contents/mgls?ref=main"

# Ensure the local directory exists
mkdir -p "$dos_mgl"
mkdir -p "$base_dir"

# Empty out the mgl_dir if always_dl_mgl is true
if [ "$always_dl_mgl" = true ]; then
    echo "Clearing out $mgl_dir..."
    rm -f "$dos_mgl"/*.mgl
fi

# Check available space on the device where base_dir is located
available_space_gb=$(df -BG "$base_dir" | awk 'NR==2 {print substr($4, 1, length($4)-1)}')

if [ "$available_space_gb" -lt 30 ]; then
    echo "Less than 30GB space available in $base_dir. Aborting."
    exit 1
fi

# Navigate to the local directory
cd "$dos_mgl"

# Fetch the list of files in the remote folder via GitHub's API
curl --insecure -s "$api_url" | jq -r '.[] | select(.type=="file") | .download_url' | while read file_url; do
    file_name=$(basename "$file_url" | perl -pe 's/%([0-9A-F]{2})/chr(hex($1))/eg')

    # Check if the file already exists locally
    if [ "$always_dl_mgl" = true ] || [ ! -f "$file_name" ]; then
        echo "Downloading $file_name..."
        curl --insecure -s -o "$file_name" "$file_url"
    else
        echo "$file_name already exists, skipping."
    fi
done

echo "Synchronization complete."
echo "Checking if files exist"

mgl_dir="$dos_mgl"

# Initialize an array to hold all paths mentioned in mgl
referenced_paths=()

# Initialize an array to hold the names of .mgl files with missing paths/files
mgl_with_missing_paths=()


# Loop through all .mgl files in the mgl_dir
for mgl_file in "$mgl_dir"/*.mgl; do

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

        full_path="${base_dir}/${trimmed_path}"
        referenced_paths+=("$full_path")
		
        echo "Checking: $full_path"

        if [ ! -f "$full_path" ]; then
            echo "Missing: $trimmed_path"
            has_missing_paths=true
        else
            echo "Found: $trimmed_path"
        fi
    done <<< "$paths"

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
		mkdir -p ${base_dir}/.0mhz_downloader
		curl --insecure -L -# -o "${base_dir}/.0mhz_downloader/$zip_name" "$dl_zip"		
		if unzip -o "$base_dir/.0mhz_downloader/${zip_name}" "media/*" -d "$games_loc"; then
			echo "Unzipped $zip_name successfully."
			rm "$base_dir/.0mhz_downloader/${zip_name}"
		else
			echo "Error unzipping $zip_file."
		fi		
    fi
done

if [ "$delete_unmatched_files" = true ]; then
    echo "File cleanup is enabled."
	media_dir="${base_dir}/media"

	# List all files in the media directory
	find "$media_dir" -type f | while read media_file; do
		
		# Check if the relative path is in the referenced_paths array
		if [[ ! " ${referenced_paths[@]} " =~ " ${media_file} " ]]; then
			echo "Deleting file: $media_file"
			# Prompt for deletion or directly delete as per your requirement
			rm "$media_file"
		fi
	done
else
    echo "Skipping deletion of unreferenced files."
fi
