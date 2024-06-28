# freshdeskmonitor
```
[fkabell@localhost ~]$ /usr/local/bin/ticketmon.sh -h
usage: ticketmon.sh [-cehlnp] [-i SECONDS]
Monitor, log, and perform actions on tickets created within the last minute.
Intended to be ran every minute via cron(1).

-c      Close tickets from known automated senders.
-e      Print error messages to stderr.
-h      Display this help and exit successfully. Implies `-e'.
-i      Specify the persist interval for SMS notifications.
-l      Log to /var/log/ticket.
-n      Notify via SMS when a ticket is created.
-p      Persist SMS notifications. Implies `-n'.
```
