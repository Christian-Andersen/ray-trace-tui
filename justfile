alias c := check
alias r := run

default: check run
check:
    prek run --all-files
run:
    zig build run
