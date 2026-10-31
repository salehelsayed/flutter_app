#!/bin/bash
# List the title/text lines of every com.mknoon.app notification on a device (dumpsys only).
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
adb -s "$1" shell dumpsys notification --noredact | awk '/NotificationRecord\(/{p=($0 ~ /pkg=com.mknoon.app/)} p && /android\.(title|text)=String/' | sed 's/^ *//'
