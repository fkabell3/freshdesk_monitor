# freshdeskmonitor
POSIX shell script which monitors the Freshdesk ticketing system and performs actions on tickets. Actions include closing tickets via source email, sending SMS notifications (optionally repeatedly until ticket is assigned), and logging.

This script has a monetary cost for both the Freshdesk and ClickSend APIs.

```
[fkabell@localhost ~]$ /usr/local/bin/ticketmon.sh -h
usage: ticketmon.sh [-cehlnnp] [-i SECONDS]
Monitor, log, and perform actions on tickets created within the last minute.
Intended to be ran every minute via cron(1).

-c      Close tickets from known automated senders.
-e      Print error messages to stderr.
-h      Display this help and exit successfully. Implies `-e'.
-i      Specify the persist interval for SMS notifications.
-l      Log to /var/log/ticket.
-n      Notify via SMS when a ticket is created.
-nn	Like above, but notify for automated senders as well.
-p      Persist SMS notifications. Implies `-n'.
```
