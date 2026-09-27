#!/usr/bin/env bash
# Foreground entrypoint for the SM75 runtime image.
#
# launcher.sh is a service *manager*: in non-interactive mode it resolves the
# configuration, starts api_server with nohup+setsid and returns. Run as
# container PID 1 that return ends the container, the restart policy creates it
# again and the whole startup repeats -- observed as a loop where every attempt
# exits 0 while its per-attempt log ends with HTTP 200 responses.
#
# This wrapper keeps PID 1 alive for as long as the server launcher.sh started.
# Arguments are forwarded verbatim, so the documented non-interactive
# invocation is unchanged:
#
#   docker run -d --gpus all -v /path/to/checkpoint:/models:ro -p 8000:8000 \
#     <image> --model-dir /models --profile <profile.env> \
#     --gpu-devices 0,1 --tp-size 2 --pp-size 1 --set SERVICE_SCOPE=lan
#
# Use --entrypoint ./launcher.sh to get the interactive service manager instead.
set -u

cd /workspace

./launcher.sh "$@"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "launcher exited with status $rc" >&2
  exit "$rc"
fi

pid_file=$(ls -t /workspace/run-logs/vllm-*.pid 2>/dev/null | head -1)
if [ -z "$pid_file" ]; then
  echo "launcher returned without a pid file; nothing to keep in the foreground"
  exit 0
fi

server_pid=$(cat "$pid_file" 2>/dev/null || true)
if [ -z "${server_pid:-}" ] || ! kill -0 "$server_pid" 2>/dev/null; then
  echo "no running server behind $pid_file; exiting"
  exit 0
fi

echo "server pid $server_pid (from $pid_file); holding the foreground"
trap 'kill -TERM "$server_pid" 2>/dev/null || true' TERM INT
while kill -0 "$server_pid" 2>/dev/null; do sleep 5; done
echo "server pid $server_pid exited; container terminating"
