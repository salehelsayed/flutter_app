#!/bin/bash
# Read-only: can the Mac reach the update host on port 22?
nc -z -G 10 updates.mknoon.xyz 22 && echo mac_port22_open || echo mac_port22_closed
