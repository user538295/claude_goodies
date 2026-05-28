/^## / {
    heading = tolower($0)
    sub(/[[:space:]]+$/, "", heading)
    if (heading ~ /^## tasks?$/ || heading ~ /^## task breakdown$/) { found=1 } else { found=0 }
    next
}
