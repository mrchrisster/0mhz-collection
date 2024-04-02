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

# NOTE: If this is the first time you install ao486, make sure you run update_all to install all necessary files for the core

# Where should the games be installed? Change accordingly if you want games to be stored on usb or cifs
games_loc="/media/fat"

# Path for mgl files. Should be on /media/fat drive.
dos_mgl="/media/fat/_DOS Games"

# Prefer mt32 files
prefer_mt32=false

# Always download fresh copies of mgls to assure we stay up to date
always_dl_mgl=false

# Deletes mgls that are not associated with files on archive. Set to false to disable automatic deletion
unresolved_mgls=true  

###### The rest of the script should probably not be changed 

base_dir="${games_loc}/games/AO486"

# URL of the 0mhz archive.org XML file
xml_url="https://archive.org/download/0mhz-dos/0mhz-dos_files.xml"

# 0mhz GitHub API URL for listing contents of the mgls folder
api_url="https://api.github.com/repos/0mhz-net/0mhz-collection/contents/"

mgl_dir="$dos_mgl"

# Adjust API URL based on mt-32
if [ "$prefer_mt32" = true ]; then
    api_url="${api_url}/mgls/_MT-32?ref=main"
else
    api_url="${api_url}mgls?ref=main"
fi

# Ensure the local directory exists
mkdir -p "$dos_mgl"
mkdir -p /media/fat/games/AO486/media
mkdir -p "$base_dir"/media

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
		
        echo -n "Checking: $trimmed_path ..."

        if [ ! -f "$full_path" ]; then
            echo " Missing"
            has_missing_paths=true
        else
            echo " Found"
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
    base_name="${mgl_file%.mgl}"
    mt32_suffix=" (MT-32)"
	mt32_name="${base_name}${mt32_suffix}.zip"
    standard_name="${base_name}.zip"

    # Initialize variable to hold the selected file name
    selected_zip=""

    # Check if preference for MT-32 is enabled and the MT-32 version exists
    if $prefer_mt32 && echo "$file_names" | fgrep -qi "$mt32_name"; then
        echo "MT-32 version found: $mt32_name"
        selected_zip="$mt32_name"
    elif echo "$file_names" | fgrep -qi "$standard_name"; then
        echo "Downloading standard version: $standard_name"
        selected_zip="$standard_name"
    fi

    # Proceed with download if a file has been selected
    if [ ! -z "$selected_zip" ]; then
        echo "Downloading selected zip: $selected_zip"
        dl_zip="$(echo https://archive.org/download/0mhz-dos/"$selected_zip" | sed 's/ /%20/g')"
        mkdir -p "${base_dir}/.0mhz_downloader"
        curl --insecure -L -# -o "${base_dir}/.0mhz_downloader/$selected_zip" "$dl_zip"
        if unzip -o "$base_dir/.0mhz_downloader/${selected_zip}" "games/ao486/media/*" -d "$games_loc"; then
            echo "Unzipped $selected_zip successfully."
            rm "$base_dir/.0mhz_downloader/${selected_zip}"
        else
            echo "Error unzipping $selected_zip."
        fi
    fi
done


if [ "$unresolved_mgls" = true ]; then
	echo "Verifying .mgl files post-download..."

	for mgl_basename in "${mgl_with_missing_paths[@]}"; do
		still_missing_any=false
		mgl_file="$dos_mgl/$mgl_basename"
		while IFS= read -r line; do
			path=$(echo "$line" | grep -o 'path="[^"]*"' | sed 's/path="\(.*\)"/\1/')
			if [[ ! -z "$path" ]]; then
				full_path="$base_dir/${path}"
				if [ ! -f "$full_path" ]; then
					still_missing_any=true
					break
				fi
			fi
		done < "$mgl_file"
		
		if [ "$still_missing_any" = true ]; then
			echo "Incomplete .mgl detected, deleting: $mgl_basename"
			rm "$mgl_file"
		else
			echo "$mgl_basename is complete."
		fi
	done
fi



if [ "$delete_unmatched_files" = true ]; then
    echo "File cleanup is enabled."
	media_dir="${base_dir}/media"

	# List all files in the media directory
	find "$media_dir" -type f | while read media_file; do
		
		# Check if the relative path is in the referenced_paths array
		if [[ ! " ${referenced_paths[@]} " =~ " ${media_file} " ]]; then
			echo "Deleting file: $media_file"
			rm "$media_file"
		fi
	done
fi
