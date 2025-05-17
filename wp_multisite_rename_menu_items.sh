#!/bin/bash

# Debug flag
VERBOSE=false
DRY_RUN=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-v|--verbose] [-d|--dry-run]"
            exit 1
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    echo "🔍 DRY RUN MODE - No changes will be made"
    echo
fi

# Function to print debug information
debug() {
    if [ "$VERBOSE" = true ]; then
        echo "[DEBUG] $1"
    fi
}

# Function to validate wp-config.php values
validate_config() {
    local missing_values=()
    
    [ -z "$DB_NAME" ] && missing_values+=("DB_NAME")
    [ -z "$DB_USER" ] && missing_values+=("DB_USER")
    [ -z "$DB_PASS" ] && missing_values+=("DB_PASSWORD")
    [ -z "$DB_HOST" ] && missing_values+=("DB_HOST")
    [ -z "$WP_PREFIX" ] && missing_values+=("table_prefix")

    if [ ${#missing_values[@]} -ne 0 ]; then
        echo "Error: The following values are missing from wp-config.php:"
        printf '%s\n' "${missing_values[@]}"
        exit 1
    fi

    debug "Configuration loaded successfully:"
    debug "- Database: $DB_NAME"
    debug "- Host: $DB_HOST"
    debug "- User: $DB_USER"
    debug "- Table Prefix: $WP_PREFIX"
}

# Function to show available menu items from first site
show_sample_menu_items() {
    echo "Available menu items from main site:"
    wp menu item list $(wp term list nav_menu --field=term_id --name="Main Menu" --format=csv 2>/dev/null | tail -n 1) --fields=title --format=csv 2>/dev/null | tail -n +2 | sort -u | sed 's/^"//' | sed 's/"$//'
    echo
}

# Function to select sites
select_sites() {
    echo "How would you like to update the sites?"
    echo "1) All sites in the network"
    echo "2) Single specific site"
    echo "3) Multiple specific sites"
    read -p "Select an option (1-3): " SITE_OPTION

    case $SITE_OPTION in
        1)
            wp site list --fields=blog_id,url --format=csv | tail -n +2 > /tmp/all_site_ids_and_urls.txt
            echo "Selected all sites in the network"
            debug "Created site list with $(wc -l < /tmp/all_site_ids_and_urls.txt) sites"
            ;;
        2)
            echo "Available sites:"
            wp site list --fields=url --format=csv | tail -n +2 | nl
            read -p "Enter the number of the site to update: " SITE_NUM
            wp site list --fields=blog_id,url --format=csv | tail -n +2 | sed -n "${SITE_NUM}p" > /tmp/all_site_ids_and_urls.txt
            echo "Selected site: $(cat /tmp/all_site_ids_and_urls.txt)"
            debug "Selected single site #$SITE_NUM"
            ;;
        3)
            echo "Available sites:"
            wp site list --fields=url --format=csv | tail -n +2 | nl
            echo "Enter the numbers of the sites to update (space-separated):"
            read -p "Site numbers: " SITE_NUMS
            > /tmp/all_site_ids_and_urls.txt
            for num in $SITE_NUMS; do
                wp site list --fields=blog_id,url --format=csv | tail -n +2 | sed -n "${num}p" >> /tmp/all_site_ids_and_urls.txt
            done
            echo "Selected sites:"
            cat /tmp/all_site_ids_and_urls.txt
            debug "Selected multiple sites: $SITE_NUMS"
            ;;
        *)
            echo "Invalid option. Exiting."
            exit 1
            ;;
    esac
    echo
}

# Show sample menu items to help user
show_sample_menu_items

# Get input with validation
while true; do
    read -p "Enter the menu item title to search for: " SEARCH_TITLE
    if [[ -n "$SEARCH_TITLE" ]]; then
        break
    else
        echo "Error: Search title cannot be empty. Please try again."
    fi
done

while true; do
    read -p "Enter the new menu item title to replace with: " NEW_TITLE
    if [[ -n "$NEW_TITLE" ]]; then
        break
    else
        echo "Error: New title cannot be empty. Please try again."
    fi
done

# Select sites to update
select_sites

# Script configuration
OUTPUT="menu_items_change.txt"
MENU_NAME="Main Menu"

# Check if wp-config.php exists
if [ ! -f "wp-config.php" ]; then
    echo "Error: wp-config.php not found in current directory"
    exit 1
fi

debug "Loading configuration from wp-config.php"

# Load configuration from wp-config.php
DB_NAME=$(grep "DB_NAME" wp-config.php | cut -d "'" -f 4)
DB_USER=$(grep "DB_USER" wp-config.php | cut -d "'" -f 4)
DB_PASS=$(grep "DB_PASSWORD" wp-config.php | cut -d "'" -f 4)
DB_HOST=$(grep "DB_HOST" wp-config.php | cut -d "'" -f 4)
WP_PREFIX=$(grep "table_prefix" wp-config.php | cut -d "'" -f 2)

# Validate configuration
validate_config

# Remove trailing underscore if present (as we'll add it in the table name construction)
WP_PREFIX=${WP_PREFIX%_}
debug "Using table prefix: ${WP_PREFIX}_"

# Confirm with user
echo
if [ "$DRY_RUN" = true ]; then
    echo "The following changes would be made:"
else
    echo "Please confirm the following changes:"
fi
echo "- Search for menu items titled: '$SEARCH_TITLE'"
echo "- Replace with new title: '$NEW_TITLE'"
echo "- Will affect $(wc -l < /tmp/all_site_ids_and_urls.txt) site(s)"
[ "$VERBOSE" = true ] && echo "- Using table prefix: ${WP_PREFIX}_"

if [ "$DRY_RUN" = false ]; then
    read -p "Continue? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

echo "site_id,site_url,menu_term_id,menu_item_id,status" > "$OUTPUT"

# Create temporary files for summary data
TEMP_SITES_WITH_CHANGES=$(mktemp)
TEMP_SITES_WITHOUT_ITEM=$(mktemp)
TEMP_MENU_ITEM_IDS=$(mktemp)

while IFS=, read -r SITE_ID SITE_URL; do
    # Remove trailing slash from URL if present (wp cli is picky)
    SITE_URL=$(echo "$SITE_URL" | sed 's:/*$::')
    
    echo "Processing site: $SITE_URL"

    # Determine correct table prefix
    if [[ "$SITE_ID" == "1" ]]; then
        TABLE_POSTS="${WP_PREFIX}_posts"
    else
        TABLE_POSTS="${WP_PREFIX}_${SITE_ID}_posts"
    fi
    debug "Using table: $TABLE_POSTS"

    # Get menu term_id for "Main Menu"
    MENU_TERM_ID=$(wp term list nav_menu --field=term_id --name="$MENU_NAME" --url="$SITE_URL" --format=csv 2>/dev/null | tail -n 1)

    if [[ -z "$MENU_TERM_ID" ]]; then
        echo "$SITE_ID,$SITE_URL,NOT_FOUND,NOT_FOUND,NO_MENU_FOUND" >> "$OUTPUT"
        echo "  No menu found"
        debug "No menu found for site $SITE_ID"
        continue
    fi

    # Get post ID of the menu item (case-insensitive search)
    MENU_ITEMS=$(wp menu item list "$MENU_TERM_ID" --fields=ID,title --url="$SITE_URL" --format=csv 2>/dev/null)
    MENU_ITEM_ID=$(echo "$MENU_ITEMS" | grep -i ",\"$SEARCH_TITLE\"" || echo "$MENU_ITEMS" | grep -i ",$SEARCH_TITLE" || echo "")
    MENU_ITEM_ID=$(echo "$MENU_ITEM_ID" | cut -d, -f1)

    if [[ -z "$MENU_ITEM_ID" ]]; then
        echo "$SITE_ID,$SITE_URL,$MENU_TERM_ID,NOT_FOUND,NO_ITEM_FOUND" >> "$OUTPUT"
        echo "  No '$SEARCH_TITLE' menu item found"
        echo "$SITE_URL" >> "$TEMP_SITES_WITHOUT_ITEM"
        debug "No menu item '$SEARCH_TITLE' found for site $SITE_ID"
        continue
    fi

    echo "  Found '$SEARCH_TITLE' menu item: $MENU_ITEM_ID"
    debug "Found menu item ID $MENU_ITEM_ID in table $TABLE_POSTS"

    # Store menu item ID and site URL for summary
    echo "$MENU_ITEM_ID $SITE_URL" >> "$TEMP_MENU_ITEM_IDS"
    echo "$SITE_URL" >> "$TEMP_SITES_WITH_CHANGES"

    # Build SQL query
    SQL="UPDATE ${TABLE_POSTS} SET post_title = '${NEW_TITLE}' WHERE ID = ${MENU_ITEM_ID} AND post_type = 'nav_menu_item';"
    
    if [ "$DRY_RUN" = true ]; then
        echo "  Would execute: $SQL"
        echo "$SITE_ID,$SITE_URL,$MENU_TERM_ID,$MENU_ITEM_ID,WOULD_UPDATE" >> "$OUTPUT"
    else
        debug "Executing SQL: $SQL"
        MYSQL_PWD="$DB_PASS" mysql -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$SQL"
        echo "$SITE_ID,$SITE_URL,$MENU_TERM_ID,$MENU_ITEM_ID,UPDATED" >> "$OUTPUT"
        echo "  Updated to '$NEW_TITLE'"
    fi

done < /tmp/all_site_ids_and_urls.txt

# Generate summary
echo
echo "============ SUMMARY ============"
if [ "$DRY_RUN" = true ]; then
    echo "Changes that would be made:"
    echo "Total sites processed: $(grep -c "," "$OUTPUT")"
    echo "Would update: $(grep -c ",WOULD_UPDATE" "$OUTPUT") sites"
else
    echo "Total sites processed: $(grep -c "," "$OUTPUT")"
    echo "Successfully updated: $(grep -c ",UPDATED" "$OUTPUT") sites"
fi
echo "Sites without '$SEARCH_TITLE' menu item: $(grep -c ",NO_ITEM_FOUND" "$OUTPUT")"
echo
echo "Menu item IDs found:"
echo "--------------------"
sort "$TEMP_MENU_ITEM_IDS" | awk '{print $1}' | uniq -c | while read count id; do
    echo "ID $id: found on $count site(s)"
    if [ "$count" -eq 1 ]; then
        grep "$id" "$TEMP_MENU_ITEM_IDS" | cut -d' ' -f2-
    fi
done
echo
echo "Sites without the menu item:"
echo "---------------------------"
cat "$TEMP_SITES_WITHOUT_ITEM"
echo
echo "Detailed results saved in: $OUTPUT"

if [ "$DRY_RUN" = true ]; then
    echo
    echo "✨ This was a dry run - no changes were made"
    echo "Run without --dry-run to apply these changes"
fi

# Cleanup
debug "Cleaning up temporary files"
rm -f /tmp/all_site_ids_and_urls.txt "$TEMP_SITES_WITH_CHANGES" "$TEMP_SITES_WITHOUT_ITEM" "$TEMP_MENU_ITEM_IDS"
