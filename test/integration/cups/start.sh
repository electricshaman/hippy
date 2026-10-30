#!/bin/sh
# Starts CUPS and creates the queues used by test/integration/cups_test.exs.
set -e

mkdir -p /spool
touch /spool/filtered.ps && chmod 666 /spool/filtered.ps

cupsd -f &
until lpstat -r >/dev/null 2>&1; do sleep 0.2; done
# lpstat can report the scheduler as running slightly before lpadmin is accepted.
sleep 2

# Generic PostScript queue writing to a file: exercises the CUPS filter pipeline.
lpadmin -p filtered -E -v file:///spool/filtered.ps -m drv:///sample.drv/generic.ppd

# Raw queues discarding output.
lpadmin -p raw -E -v file:///dev/null -m raw
lpadmin -p secure -E -v file:///dev/null -m raw
lpadmin -p rejecting -E -v file:///dev/null -m raw && cupsreject rejecting

# Paused queues so jobs stay pending. Separate queues keep tests independent.
for q in held_jobs held_cancel; do
  lpadmin -p "$q" -E -v file:///dev/null -m raw && cupsdisable "$q"
done

# A class containing two of the queues, and a default destination.
lpadmin -p raw -c raw_class && lpadmin -p filtered -c raw_class && cupsenable raw_class && cupsaccept raw_class
lpadmin -d raw

echo READY
wait
