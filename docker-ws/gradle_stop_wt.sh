#!/bin/bash
# Stop the Gradle daemons started from one worktree's android project (gradlew --stop only affects daemons of that Gradle version/user home).
cd /Volumes/CrucialX9/flutter_app/build/${1:?tree}/android && JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ./gradlew --stop 2>&1 | tail -2
