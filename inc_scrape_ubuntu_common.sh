#!/bin/sh

# this is somewhat crude but then again, so is this shitty pastebin which doesn't
# offer a way to download the raw paste; without logging in using OpenID anyway.

wget -q -O - "$1" | grep -A 10000 -F '<table class="pastetable">' | grep -B 10000 -F '</table>' | \
    sed 's/<[^>]*>//g' | grep -v '^[       ]*[0-9][0-9]*$' | sed '1s/^[0-9][0-9]*//' | \
    sed -e 's/&amp;/\&/g' -e "s/&#39;/'/g" -e 's/&quot;/"/g' -e 's/&lt;/</g' -e 's/&gt;/>/g'
