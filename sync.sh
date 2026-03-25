#!/bin/bash
while IFS='|' read -r namespace src; do
    image=${src##*/}
    dst="$REGISTRY/$namespace/$image"
    echo "$src -> $dst"
    skopeo copy -a -q docker://$src docker://$dst
done < <(grep -v "#" images.txt)
