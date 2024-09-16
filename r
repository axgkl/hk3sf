#!/bin/bash

# Read the file line by line
while IFS= read -r line; do
    # Extract the repository name from the line
    repo=$(echo $line | awk '{print $1}')
    test -z "$repo" && continue
    # Delete the repository
    echo "Deleting $repo"
    gh repo delete "$repo" --yes
done <foo
