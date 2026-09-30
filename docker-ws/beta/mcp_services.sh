#!/bin/bash
# Install / remove / show the Maestro and Appium MCP servers as per-user LaunchAgents.
#   mcp_services.sh install   -> wrappers in ~/tools/mcp, agents in ~/Library/LaunchAgents, started
#   mcp_services.sh remove    -> stop agents, delete the plists and wrappers
#   mcp_services.sh status    -> agent state + listen addresses
# Both servers listen on 127.0.0.1 only (Docker containers reach them via host.docker.internal).
set -u
. "$(dirname "$0")/beta_env.sh"
T="$HOME/tools/mcp"; LOGS="$T/logs"; LA="$HOME/Library/LaunchAgents"
U=$(id -u)
M_LABEL=com.mknoon.mcp.maestro; A_LABEL=com.mknoon.mcp.appium
M_PORT=18931; A_PORT=18932

write_wrappers() {
  mkdir -p "$T" "$LOGS" "$T/maestro-work"
  cat > "$T/run-maestro-mcp.sh" <<EOF
#!/bin/bash
# Maestro MCP (stdio) behind mcp-proxy on 127.0.0.1:$M_PORT (/mcp streamable HTTP, /sse).
export ANDROID_HOME="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME"
export PATH="$HOME/.maestro/bin:\$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_DRIVER_STARTUP_TIMEOUT=120000
exec "$HOME/.local/bin/mcp-proxy" --host 127.0.0.1 --port $M_PORT --pass-environment -- maestro mcp --no-viewer --working-dir "$T/maestro-work"
EOF
  cat > "$T/run-appium-mcp.sh" <<EOF
#!/bin/bash
# Appium MCP (embedded UiAutomator2 + XCUITest drivers) over httpStream on 127.0.0.1:$A_PORT.
export ANDROID_HOME="$ANDROID_HOME" ANDROID_SDK_ROOT="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME"
export PATH="\$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
exec "$T/node_modules/.bin/appium-mcp" --httpStream --port=$A_PORT
EOF
  chmod +x "$T/run-maestro-mcp.sh" "$T/run-appium-mcp.sh"
}

write_plist() {  # label script log
  cat > "$LA/$1.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$2</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>$3</string>
  <key>StandardErrorPath</key><string>$3</string>
</dict></plist>
EOF
}

status() {
  for l in $M_LABEL $A_LABEL; do
    printf '%s: ' "$l"; launchctl print "gui/$U/$l" 2>/dev/null | grep -E "^\s+(state|pid) =" | tr -s ' ' | tr '\n' ' '; echo
  done
  lsof -nP -iTCP:$M_PORT -sTCP:LISTEN 2>/dev/null | tail -n +2
  lsof -nP -iTCP:$A_PORT -sTCP:LISTEN 2>/dev/null | tail -n +2
}

case "${1:-status}" in
  install)
    write_wrappers
    mkdir -p "$LA"
    write_plist $M_LABEL "$T/run-maestro-mcp.sh" "$LOGS/maestro-mcp.log"
    write_plist $A_LABEL "$T/run-appium-mcp.sh" "$LOGS/appium-mcp.log"
    for l in $M_LABEL $A_LABEL; do
      launchctl bootout "gui/$U/$l" 2>/dev/null
      launchctl bootstrap "gui/$U" "$LA/$l.plist" && echo "loaded $l"
    done
    for i in $(seq 1 60); do
      lsof -nP -iTCP:$M_PORT -sTCP:LISTEN >/dev/null 2>&1 && lsof -nP -iTCP:$A_PORT -sTCP:LISTEN >/dev/null 2>&1 && break
      sleep 1
    done
    status ;;
  remove)
    for l in $M_LABEL $A_LABEL; do launchctl bootout "gui/$U/$l" 2>/dev/null; rm -f "$LA/$l.plist"; done
    rm -f "$T/run-maestro-mcp.sh" "$T/run-appium-mcp.sh"
    echo "removed agents and wrappers (packages stay in $T)"; status ;;
  status) status ;;
esac
