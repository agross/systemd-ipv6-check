#!/usr/bin/env bats

load 'test/helpers/mocks/stub'
load 'test/helpers/bats-support/load'
load 'test/helpers/bats-assert/load'

setup() {
  rm -rf "$BATS_MOCK_BINDIR"
}

teardown() {
  unstub date || true
  unstub mail || true
  unstub ping || true
}

@test 'Ping success without state file' {
  state="$(mktemp)"
  rm "$state"

  mail_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date 'echo 1'

  run ./ipv6-check -s "$state"

  assert_success
  assert_output --partial 'google.de is reachable'

  assert grep --quiet 'up 1' "$state"
  assert grep --quiet 'true' "$mail_called"
}

@test 'Ping success with previous success in state file' {
  state="$(mktemp)"
  echo 'up 0' > "$state"

  mail_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date 'echo 1'

  run ./ipv6-check -s "$state"

  assert_success
  assert_output --partial 'google.de is reachable'

  assert grep --quiet 'up 0' "$state"
  refute grep --quiet 'true' "$mail_called"
}

@test 'Ping failure without state file' {
  state="$(mktemp)"
  rm "$state"

  mail_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date 'echo 1'

  run ./ipv6-check -s "$state"

  assert_failure 1
  assert_output --partial 'google.de is not reachable'

  assert grep --quiet 'down-notified 1' "$state"
  assert grep --quiet 'true' "$mail_called"
}

@test 'Ping failure with previous success in state file' {
  state="$(mktemp)"
  echo 'up 0' > "$state"

  mail_called="$(mktemp)"

  stub mail "echo true > '$mail_called'"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date 'echo 1'

  run ./ipv6-check -s "$state"

  assert_failure 1
  assert_output --partial 'google.de is not reachable'

  assert grep --quiet 'down 1' "$state"
  refute grep --quiet 'true' "$mail_called"
}

@test 'Ping failure within grace period with previous failure in state file' {
  timeout=10

  state="$(mktemp)"
  echo 'down 0' > "$state"

  mail_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date "echo $((timeout * 60))"

  run ./ipv6-check -s "$state" -t $timeout

  assert_failure 2
  assert_output --partial 'google.de is not reachable'

  assert grep --quiet 'down 0' "$state"
  refute grep --quiet 'true' "$mail_called"
}

@test 'Ping failure after grace period with previous failure in state file' {
  timeout=10

  state="$(mktemp)"
  echo 'down 0' > "$state"

  mail_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date "echo $((timeout * 60 + 1))"

  run ./ipv6-check -s "$state" -t $timeout

  assert_failure 2
  assert_output --partial 'google.de is not reachable'

  assert grep --quiet 'down-notified 0' "$state"
  assert grep --quiet 'true' "$mail_called"
}

@test 'Ping failure after notification' {
  timeout=10

  state="$(mktemp)"
  echo 'down-notified 0' > "$state"

  mail_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date "echo $((timeout * 60 + 1))"

  run ./ipv6-check -s "$state" -t $timeout

  assert_failure 2
  assert_output --partial 'google.de is not reachable'

  assert grep --quiet 'down-notified 0' "$state"
  refute grep --quiet 'true' "$mail_called"
}

@test 'Recovery within grace period' {
  timeout=10

  state="$(mktemp)"
  echo "down 0" > "$state"

  mail_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date "echo $((timeout * 60))"

  run ./ipv6-check -s "$state" -t $timeout

  assert_success
  assert_output --partial 'google.de is reachable'

  assert grep --quiet "up $succeeded_at" "$state"
  refute grep --quiet 'true' "$mail_called"
}

@test 'Recovery after grace period' {
  timeout=10

  state="$(mktemp)"
  echo "down 0" > "$state"

  mail_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date "echo $((timeout * 60 + 1))"

  run ./ipv6-check -s "$state" -t $timeout

  assert_success
  assert_output --partial 'google.de is reachable'

  assert grep --quiet "up $succeeded_at" "$state"
  assert grep --quiet 'true' "$mail_called"
}
