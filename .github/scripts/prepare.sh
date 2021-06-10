#!/usr/bin/env bash

set -e

declare -a SOURCES
declare -r MAIN_DIR="test/complete"
declare -r SUBSET_DIR="test/dashboard"

# create array of sources for upload
function getUploadables {
  SOURCES=($(find "$MAIN_DIR" -type f | sort))

  if [ -d "$SUBSET_DIR" ]; then
    subset=($(find "$SUBSET_DIR" -type f | sort))
    SOURCES+=("${subset[@]}")
  fi
}

# $1 - file
# if the extension is json, it's a "package"
function isPackage {
  [[ "${1#*.}" == "json" ]]
}

# $1 - file
# if the extension is html or xlsx, it's a "reference"
function isReference {
  [[ "${1#*.}" == "html" ]] || [[ "${1#*.}" == "xlsx" ]]
}

# $1 - file
# get "package" JSON object from file
function getPackageObject {
  if isPackage "$1"; then
    jq -r '.package' < "$1"
  fi
}

# $1 & $2 - file path
# create source->destination JSON
function createJson {
  jq -n --arg key "$1" --arg value "$2" '[{"source": $key, "destination": $value}]'
}

# $1 & $2 - JSON
# append JSON $2 to $1
function addToJson {
  echo "$1" | jq -c --argjson new "$2" '. += $new'
}

# $1 - JSON
# create path from "package" JSON object
function createPath {
  # get package details from object
  locale=$(echo "$1" | jq -r '.locale')
  code=$(echo "$1" | jq -r '.code')
  type=$(echo "$1" | jq -r '.type')
  package_version=$(echo "$1" | jq -r '.version')
  dhis2_version=$(echo "$1" | jq -r '.DHIS2Version')

  # construct path
  path="$locale/$code/$type/$package_version/$dhis2_version"

  # if the file is in a subset dir, add it to the path
  if [[ $1 =~ $SUBSET_DIR  ]]; then
    path+="$SUBSET_DIR/"
  fi

  echo "$path"
}

# get reference path and file name from the first "package" found
function getReferenceDestination {
  files=("$@")

  for file in "${files[@]}"
  do
    object=$(getPackageObject "$file")

    # remove locale from path
    path=$(createPath "$object")
    path_without_locale=${path#*/}

    # remove locale from name
    name=$(echo "$object" | jq -r '.name')
    name_without_locale=${name%-*}

    echo "$path_without_locale/$name_without_locale"

    # return after first found file
    return
  done
}

# create matrix of sources and destinations
function createMatrix {
  # list of files from arguments
  files=("$@")

  # initialize empty matrix
  matrix='[]'

  # default reference path and file name
  reference_destination=$(getReferenceDestination "${files[@]}")

  # create source -> destination for all files
  for file in "${files[@]}"
  do
    packageObject=$(getPackageObject "$file")
    path=$(createPath "$packageObject")

    file_name=$(echo "$packageObject" | jq -r '.name')

    if isPackage "$file"; then
      addition=$(createJson "$file" "$path/$file_name.${file#*.}")
      matrix=$(addToJson "$matrix" "$addition")
    fi

    if isReference "$file"; then
      # get reference locale from "parent" directory of the file
      locale=$(basename $(dirname "$file"))
      addition=$(createJson "$file" "$locale/$reference_destination-$locale-ref.${file#*.}")
      matrix=$(addToJson "$matrix" "$addition")
    fi
  done
}

getUploadables

createMatrix "${SOURCES[@]}"

echo "$matrix"
