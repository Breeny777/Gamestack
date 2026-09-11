#!/usr/bin/env bash

set -u

SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="${SCRIPT_ROOT}/AzerothCore/server_configs"
TARGET_ROOT="/opt/docker/AzerothCore"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET_ROOT}/config-backups/${TIMESTAMP}"

declare -a CONFIG_FILES=(
    "worldserver.conf|env/dist/etc/worldserver.conf"
    "authserver.conf|env/dist/etc/authserver.conf"
    "AutoBalance.conf|env/dist/etc/modules/AutoBalance.conf"
    "playerbots.conf|env/dist/etc/modules/playerbots.conf"
    "docker-compose.override.yml|docker-compose.override.yml"
)

if [[ ! -d "$SOURCE_ROOT" ]]; then
    echo "Configuration repository not found: $SOURCE_ROOT"
    exit 1
fi

if [[ ! -f "${TARGET_ROOT}/docker-compose.yml" ]]; then
    echo "This script must be located inside the AzerothCore directory."
    exit 1
fi

copied_count=0

for mapping in "${CONFIG_FILES[@]}"; do
    source_relative="${mapping%%|*}"
    target_relative="${mapping#*|}"

    source_file="${SOURCE_ROOT}/${source_relative}"
    target_file="${TARGET_ROOT}/${target_relative}"

    echo
    echo "Source:      $source_file"
    echo "Destination: $target_file"

    if [[ ! -f "$source_file" ]]; then
        echo "Source file does not exist; skipping."
        continue
    fi

    read -r -p "Copy this file? [y/N] " answer

    case "$answer" in
        [yY]|[yY][eE][sS])
            mkdir -p "$(dirname -- "$target_file")"

            if [[ -f "$target_file" ]]; then
                backup_file="${BACKUP_ROOT}/${target_relative}"
                mkdir -p "$(dirname -- "$backup_file")"
                cp --archive -- "$target_file" "$backup_file"
                echo "Backup:     $backup_file"
            fi

            cp -- "$source_file" "$target_file"
            echo "Copied successfully."
            ((copied_count += 1))
            ;;
        *)
            echo "Skipped."
            ;;
    esac
done

echo
echo "$copied_count configuration file(s) copied."

if [[ "$copied_count" -eq 0 ]]; then
    exit 0
fi

echo
echo "Validating Docker Compose configuration..."

if sudo docker compose --project-directory "$TARGET_ROOT" config --quiet; then
    echo "Docker Compose configuration is valid."
else
    echo "Docker Compose validation failed."
    echo "Backups from this run are under: $BACKUP_ROOT"
    exit 1
fi

echo
read -r -p "Recreate the authserver and worldserver now? [y/N] " answer

case "$answer" in
    [yY]|[yY][eE][sS])
        sudo docker compose --project-directory "$TARGET_ROOT" \
            up -d --no-deps --force-recreate \
            ac-authserver ac-worldserver

        echo
        sudo docker compose --project-directory "$TARGET_ROOT" \
            ps ac-authserver ac-worldserver
        ;;
    *)
        echo "Containers were not restarted."
        echo "The copied settings will not all take effect until they are recreated."
        ;;
esac
