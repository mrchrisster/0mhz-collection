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
games_loc="/media/usb0"

# Path for mgl files. Should be on /media/fat drive.
dos_mgl="/media/fat/_DOS Games"

# Prefer mt32 files. This will download all mgl files but if a MT-32 version exist, it will use that version.
prefer_mt32=false

# Always download fresh copies of mgls to assure we stay up to date
always_dl_mgl=true

# Deletes mgls that are not associated with files on archive. Set to false to disable automatic deletion
unresolved_mgls=true  

###### The rest of the script should probably not be changed 

base_dir="${games_loc}/games/AO486"

# URL of the 0mhz archive.org XML file
xml_url="https://archive.org/download/0mhz-dos/0mhz-dos_files.xml"

mgl_dir="$dos_mgl"

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

# We use zip. Temporary directory for the repository
temp_dir="/tmp/0mhz-collection"
repo_zip_url="https://github.com/0mhz-net/0mhz-collection/archive/refs/heads/main.zip"
repo_zip_path="/tmp/0mhz-collection.zip"
mgls_dir_name="0mhz-collection-main/mgls"
mgl_gh_dir="$temp_dir/$mgls_dir_name"

# Download and unzip the repository
download_and_unzip_repo() {
    echo "Downloading repository..."
    curl -s --insecure -L -o "$repo_zip_path" "$repo_zip_url"
    echo "Unzipping repository to $temp_dir..."
    mkdir -p "$temp_dir"
    unzip -qq -o "$repo_zip_path" -d "$temp_dir"
}

# Function to prefer MT-32 files
prefer_mt32_files() {
    echo ""
    echo "Preferring MT-32 files"
	echo ""

    # Find all standard .mgl files
    find "$mgl_gh_dir"  -maxdepth 1 -type f -name "*.mgl" | while read standard_file; do
        # Determine MT-32 counterpart
        mt32_file="${standard_file%.*} (MT-32).mgl"
        mt32_file="${mt32_file/$mgl_gh_dir/$mgl_gh_dir/_MT-32}"

        if [[ -f "$mt32_file" ]]; then
            # If MT-32 counterpart exists, prefer it by deleting the standard file
            echo "Processing $(basename "$mt32_file")"
            rm -f "$standard_file"
        fi
    done
}

# Execute functions
download_and_unzip_repo
find "$mgl_gh_dir" -maxdepth 1 -type f -name '*.mgl' -exec cp -n {} "$dos_mgl" \;


if [ "$prefer_mt32" = true ]; then
	prefer_mt32_files
	find "$mgl_gh_dir/_MT-32" -maxdepth 1 -type f -name '*.mgl' -exec cp -n {} "$dos_mgl" \;
fi

# Cleanup
echo "Cleanup downloaded ZIP..."
rm -f "$repo_zip_path"
rm -rf "$temp_dir"

echo "Synchronization complete."
echo ""
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
    echo ""
    # Check if preference for MT-32 is enabled and the MT-32 version exists
    if $prefer_mt32 && echo "$file_names" | fgrep -qi "$mt32_name"; then
        echo "Downloading MT-32 version: $mt32_name"
        selected_zip="$mt32_name"
    elif echo "$file_names" | fgrep -qi "$standard_name"; then
        echo "Downloading: $standard_name"
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
    echo ""
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
