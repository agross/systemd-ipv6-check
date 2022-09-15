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
  unstub systemctl || true
}

@test 'Ping success without state file' {
  state="$(mktemp)"
  rm "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date '--utc +%s : echo 1' \
            '--date=@1 : echo [test date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -p

  assert_success

  assert_output --partial 'Hosts are reachable since [test date]'
  assert_output --partial 'google.de'
  assert_output --partial 'Sending notification'

  assert grep --quiet 'up 1' "$state"
  assert grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Ping success with previous success in state file' {
  state="$(mktemp)"
  echo 'up 0' > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date '--utc +%s : echo 1' \
            '--date=@1 : echo [test date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -p

  assert_success

  assert_output --partial 'Hosts are reachable since [test date]'
  assert_output --partial 'google.de'
  refute_output --partial 'Sending notification'

  assert grep --quiet 'up 0' "$state"
  refute grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Ping failure without state file' {
  state="$(mktemp)"
  rm "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date '--utc +%s : echo 1' \
            '--date=@1 : echo [test date]' \
            '--date=@ : exit 1'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -p

  assert_failure 1

  assert_output --partial 'Hosts are not reachable since [test date]'
  assert_output --partial 'Last state unknown since unknown'
  assert_output --partial 'google.de'
  assert_output --partial 'Sending notification'

  assert grep --quiet 'down-notified 1' "$state"
  assert grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Ping failure with previous success in state file' {
  state="$(mktemp)"
  echo 'up 0' > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date '--utc +%s : echo 1' \
            '--date=@1 : echo [test date]' \
            '--date=@0 : echo [up date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -p

  assert_failure 1

  assert_output --partial 'Hosts are not reachable since [test date]'
  assert_output --partial 'Last state up since [up date]'
  assert_output --partial 'google.de'
  refute_output --partial 'Sending notification'

  assert grep --quiet 'down 1' "$state"
  refute grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Ping failure within grace period with previous failure in state file' {
  timeout=10

  state="$(mktemp)"
  echo 'down 0' > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date "--utc +%s : echo $((timeout * 60))" \
            "--date=@$((timeout * 60)) : echo [test date]" \
            '--date=@0 : echo [down date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -t $timeout -p

  assert_failure 2

  assert_output --partial 'Hosts are not reachable since [test date]'
  assert_output --partial 'Last state down since [down date]'
  assert_output --partial 'google.de'
  refute_output --partial 'Sending notification'

  assert grep --quiet 'down 0' "$state"
  refute grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Compares timestamps using math expression' {
  first_error=0
  now=90
  timeout=180

  state="$(mktemp)"
  echo "down $first_error" > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date "--utc +%s : echo $now" \
            "--date=@$now : echo [test date]" \
            "--date=@$first_error : echo [down date]"
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -t $((timeout / 60)) -p

  assert_failure 2

  assert_output --partial 'Hosts are not reachable since [test date]'
  assert_output --partial 'Last state down since [down date]'
  assert_output --partial 'google.de'
  refute_output --partial 'Sending notification'

  assert grep --quiet "down $first_error" "$state"
  refute grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Ping failure after grace period with previous failure in state file' {
  timeout=10

  state="$(mktemp)"
  echo 'down 0' > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date "--utc +%s : echo $((timeout * 60 + 1))" \
            "--date=@$((timeout * 60 + 1)) : echo [test date]" \
            '--date=@0 : echo [down date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -t $timeout

  assert_failure 2

  assert_output --partial 'Hosts are not reachable since [test date]'
  assert_output --partial 'Last state down since [down date]'
  assert_output --partial 'google.de'
  assert_output --partial 'Sending notification'

  assert grep --quiet 'down-notified 0' "$state"
  assert grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Ping failure after grace period with previous failure in state file with reboot' {
  timeout=10

  state="$(mktemp)"
  echo 'down 0' > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date "--utc +%s : echo $((timeout * 60 + 1))" \
            "--date=@$((timeout * 60 + 1)) : echo [test date]" \
            '--date=@0 : echo [down date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -t $timeout -p

  assert_failure 2

  assert_output --partial 'Hosts are not reachable since [test date]'
  assert_output --partial 'Last state down since [down date]'
  assert_output --partial 'google.de'
  assert_output --partial 'Sending notification'

  assert grep --quiet 'down-notified 0' "$state"
  assert grep --quiet 'true' "$mail_called"
  assert grep --quiet 'true' "$systemctl_called"
}

@test 'Ping failure after notification' {
  timeout=10

  state="$(mktemp)"
  echo 'down-notified 0' > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping 'false'
  stub mail "echo true > '$mail_called'"
  stub date "--utc +%s : echo $((timeout * 60 + 1))" \
            "--date=@$((timeout * 60 + 1)) : echo [test date]" \
            '--date=@0 : echo [down date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -t $timeout -p

  assert_failure 2

  assert_output --partial 'Hosts are not reachable since [test date]'
  assert_output --partial 'Last state down-notified since [down date]'
  assert_output --partial 'google.de'
  refute_output --partial 'Sending notification'

  assert grep --quiet 'down-notified 0' "$state"
  refute grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Recovery within grace period' {
  timeout=10

  state="$(mktemp)"
  echo "down 0" > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date "--utc +%s : echo $((timeout * 60))" \
            "--date=@$((timeout * 60)) : echo [test date]"
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -t $timeout -p

  assert_success

  assert_output --partial 'Hosts are reachable since [test date]'
  assert_output --partial 'google.de'
  refute_output --partial 'Sending notification'

  assert grep --quiet "up $succeeded_at" "$state"
  refute grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Recovery after grace period' {
  timeout=10

  state="$(mktemp)"
  echo "down 0" > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date "--utc +%s : echo $((timeout * 60 + 1))" \
            "--date=@$((timeout * 60 + 1)) : echo [test date]"
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -t $timeout -p

  assert_success

  assert_output --partial 'Hosts are reachable since [test date]'
  assert_output --partial 'google.de'
  assert_output --partial 'Sending notification'

  assert grep --quiet "up $succeeded_at" "$state"
  assert grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Recovery after grace period with notification' {
  timeout=10

  state="$(mktemp)"
  echo "down-notified 0" > "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date "--utc +%s : echo $((timeout * 60 + 1))" \
            "--date=@$((timeout * 60 + 1)) : echo [test date]"
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -t $timeout -p

  assert_success

  assert_output --partial 'Hosts are reachable since [test date]'
  assert_output --partial 'google.de'
  assert_output --partial 'Sending notification'

  assert grep --quiet "up $succeeded_at" "$state"
  assert grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Supports multiple hosts' {
  state="$(mktemp)"
  rm "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping
  stub mail "echo true > '$mail_called'"
  stub date '--utc +%s : echo 1' \
            '--date=@1 : echo [test date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -p -h 'first second'

  assert_success

  assert_output --partial 'Hosts are reachable since [test date]'
  assert_output --partial 'first'
  assert_output --partial 'second'
  assert_output --partial 'Sending notification'

  assert grep --quiet 'up 1' "$state"
  assert grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}

@test 'Considers any host up like all hosts up' {
  state="$(mktemp)"
  rm "$state"

  mail_called="$(mktemp)"
  systemctl_called="$(mktemp)"

  stub ping '-6 -c 1 first : exit 0' \
            '-6 -c 1 second : exit 1'
  stub mail "echo true > '$mail_called'"
  stub date '--utc +%s : echo 1' \
            '--date=@1 : echo [test date]'
  stub systemctl "echo true > '$systemctl_called'"

  run ./ipv6-check -s "$state" -p -h 'first second'

  assert_success

  assert_output --partial 'Hosts are reachable since [test date]'
  assert_output --partial 'first'
  assert_output --partial 'second'
  assert_output --partial 'Sending notification'

  assert grep --quiet 'up 1' "$state"
  assert grep --quiet 'true' "$mail_called"
  refute grep --quiet 'true' "$systemctl_called"
}
