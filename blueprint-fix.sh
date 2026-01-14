#!/bin/bash
# =================================================
#  Blueprint Fixer
#  Discord : @eiro.tf
#  Special Thanks : @kaydennn.tsx
# =================================================

# -------- Colors --------
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m'

# -------- Animation Functions --------
type_text() {
    text="$1"
    delay=0.03
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep $delay
    done
    echo
}

spinner() {
    pid=$!
    spin='-\|/'
    i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${CYAN}[%c] Working...${NC}" "${spin:$i:1}"
        sleep .1
    done
    printf "\r${GREEN}[✔] Done!${NC}\n"
}

clear
type_text "${PURPLE}╔══════════════════════════════════════╗${NC}"
type_text "${PURPLE}║        Blueprint Fixer Tool          ║${NC}"
type_text "${PURPLE}║  Discord: @eiro.tf                   ║${NC}"
type_text "${PURPLE}║  Thanks: @kaydennn.tsx               ║${NC}"
type_text "${PURPLE}╚══════════════════════════════════════╝${NC}"
echo

cd /var/www/pterodactyl || exit 1

(
for f in \
resources/scripts/components/server/files/FileNameModal.tsx \
resources/scripts/components/server/files/FileObjectRow.tsx \
resources/scripts/components/server/files/NewDirectoryButton.tsx \
resources/scripts/components/server/files/RenameFileModal.tsx
do
    sed -i "/import { join } from 'pathe';/d" "$f"
    grep -q "const join = (...paths" "$f" || \
    sed -i "1i // Blueprint Fixer | @eiro.tf | thanks @kaydennn.tsx\nconst join = (...paths: string[]) => paths.filter(Boolean).join('/');" "$f"
done

sed -i "/@ts-expect-error todo: check on this/d" \
resources/scripts/components/elements/CopyOnClick.tsx

sed -i "s/import axios, { AxiosProgressEvent } from 'axios';/import axios from 'axios';/g" \
resources/scripts/components/server/files/UploadButton.tsx

sed -i "s/AxiosProgressEvent/ProgressEvent/g" \
resources/scripts/components/server/files/UploadButton.tsx

set +H

sed -i "/Assert::isInstanceOf/c\\
\$server = \$request->route()?->parameter('server');\\n\\n\
if (is_string(\$server) || !(\$server instanceof Server)) {\\n\
    return Limit::none();\\n\
}" app/Enum/ResourceLimit.php

set -H

blueprint -rerun-install
) & spinner

echo
type_text "${GREEN}✔ Blueprint Fixer completed successfully!"
type_text "${BLUE}→ Maintained by @eiro.tf"
type_text "${CYAN}→ Special thanks to @kaydennn.tsx"
echo
