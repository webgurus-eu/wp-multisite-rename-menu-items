# Rename Menu Items in WordPress Multisite

This script automates the renaming of menu items across a WordPress Multisite network using WP-CLI.

## Features
- Select specific sites or update all sites in the multisite network.
- Target specific menus (e.g., 'Main Menu').
- Find and rename specific menu items by their label.
- Supports dry-run mode to preview changes before applying.

## Requirements
- Bash shell
- WP-CLI installed and configured
- Access to WordPress multisite installation
- Environment must support reading `.env` files for DB credentials (if applicable)

## Usage
```bash
./wp_multisite_rename_menu_items.sh
```

You will be prompted to:
- Choose whether to update all sites or specific ones.
- Select a menu from the main site.
- Enter the current and new label for the menu item.
- Optionally run a dry-run or execute changes.

### Example Dry Run
```bash
./wp_multisite_rename_menu_items.sh --dry-run
```

### Example Execution
```bash
./wp_multisite_rename_menu_items.sh
```

## Output
- A summary of changes that would or have been made.
- Menu item IDs that were changed.
- A log file named `menu_items_change.txt` containing detailed results.

## Notes
- Use dry-run mode (`--dry-run`) to test changes safely.
- Ensure you have backups before running on production sites.

## License
MIT License (or add your own licensing info here).