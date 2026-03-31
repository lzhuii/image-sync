#!/bin/bash
grep -v -E "^(#|$)" images.txt | while IFS='|' read -r namespace src; do
    image=${src##*/}
    dst="$REGISTRY/$namespace/$image"
    src_digest=$(skopeo inspect --raw docker://$src | sha256sum | cut -d ' ' -f1)
    dst_digest=$(skopeo inspect --raw docker://$dst | sha256sum | cut -d ' ' -f1)
    if [ "$src_digest" = "$dst_digest" ]; then
        echo "$dst exists"
        continue
    fi
    echo "$src -> $dst"
    skopeo copy -a -q docker://$src docker://$dst
done
