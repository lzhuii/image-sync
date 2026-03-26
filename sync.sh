#!/bin/bash
grep -v "#" images.txt | while IFS='|' read -r namespace src; do
    [ -z "$namespace" ] && continue
    image=${src##*/}
    dst="$REGISTRY/$namespace/$image"
    echo "$src -> $dst"
    skopeo copy -a -q docker://$src docker://$dst
done
