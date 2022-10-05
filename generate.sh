#!/bin/sh
echo "Generating Master Key..."
java -jar flowcrypt-workspace-key-manager-free.jar --create-master-key
sleep 1

exit 0