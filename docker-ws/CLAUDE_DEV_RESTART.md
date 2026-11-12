# Restart Claude-Dev in its own worktree

Claude-Dev used to run in a container whose `/workspace` was the main flutter_app checkout.
From now on it runs in its own locked worktree, `/Volumes/CrucialX9/flutter_app-claude-dev`
(branch `claude-dev/work`), and its container says who it is with `KAYAN_AGENT=claude-dev`.

The owner runs these steps on the Mac. No agent stops another agent's container.

## 1. Stop the old Claude-Dev container

In the terminal that runs Claude-Dev, end the session (`/exit`, or Ctrl-C twice).
If that terminal is gone, find and stop the container:

```
docker ps --format '{{.ID}}  {{.Status}}  {{.Mounts}}' | grep flutter_app
docker stop <ID of the Claude-Dev container>
```

Check the mounts before stopping: the flutter_app session (agent `flutter`) also mounts
`/Volumes/CrucialX9/flutter_app`. Stop only the Claude-Dev one.

## 2. Launch Claude-Dev in the new folder

```
cd /Volumes/CrucialX9/flutter_app-claude-dev && KAYAN_AGENT=claude-dev claude-docker
```

`claude-docker` (the function in `~/.zshrc`) starts the launcher of the checkout you are in,
so this runs the worktree's own `scripts/run_claude_docker.sh` with your usual options.
The launcher refuses to start from a worktree without `KAYAN_AGENT`.
The first `git status` inside the new container can take several minutes, because git
hashes every file once over the bind mount.

## 3. Onboarding prompt (Kayan supplies)

Paste the prompt Kayan sends for Claude-Dev here, as the first message of the new session.

## After the restart

- Claude-Dev commits nothing more in `/Volumes/CrucialX9/flutter_app` (the main checkout).
- It moves its BL-21 work from `build/wt-claude-dev-bl21` (in the main checkout) into the new
  worktree, then tells Kayan.
- The main flutter_app session keeps `KAYAN_AGENT=flutter` (the launcher's default for the main checkout).
