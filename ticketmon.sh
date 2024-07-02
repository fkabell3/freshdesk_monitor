#!/bin/sh

# cron job - run every minute
# Depends on curl(1), jq(1),
# date(1) `-u' flag/fmt string,
# and sed(1) `-i' flag.
# Tested on GNU/Linux and OpenBSD.

#################################################
#       This script is not complete!            #
#       Input:                                  #
#           Required variables:                 #
#               freshdesksubdomain              #
#               freshdeskapikey                 #
#               number                          #
#               clicksendapikey                 #
#           updateticket() JSON ticket fields   #
#           updateticket() variables            #
#           Agent IDs/Names                     #
#       Search for strings:                     #
#           `Input me!' and `Example'           #
#################################################

freshdesksubdomain=	# Input me!
# Profile on top right corner -> "Profile settings" -> "View API Key"
freshdeskapikey=	# Input me!

number=+15555555555	# Input me!
# Profile on top right corner -> "Account Settings"
clicksendapikey=	# Input me!

persistinterval=120
tmpfile=/tmp/sms
logfile=/var/log/ticket

apiurl="https://$freshdesksubdomain.freshdesk.com/api/v2/tickets"

error() {
	if [ X"$1" = Xlog ]; then
	    logsuffix="$logsuffix, $2"
	    shift
	fi
	[ "$eflag" -eq 1 ] && printf '%s: %s\n' "$1" "$2" >&2
}

log() {
	[ "$lflag" -eq 1 ] && printf '%s\n' \
	    "$(date): ticket $ticket: \"$subject\" from $name ($email): $1$logsuffix" \
	    >> "$logfile"
}

# When $1 is a variable containing a list of unformatted ticket
# numbers, variable ${1}f is dynamically created to contain a list
# of human-preferred formatted ticket numbers.
# eg: '1 50000 100000' -> '#1, #50,000, and #100,000'
formatticket() {
	# Clear variable values from previous function calls.
	# formatted tickets
	_ticketsf=
	# number of formatted tickets
	_nticketsf=0

	# unformatted tickets
        _ticketsu="$(eval printf \"\$$1\")"
        for _ticket in $_ticketsu; do
            _ticketsf="$_ticketsf $(printf '%s' "#$_ticket" | rev | \
	        sed -E 's/[[:digit:]]{3}/&,/g' | rev | sed 's/#,/#/')"
            _nticketsf=$((_nticketsf + 1))
        done
	# Format tickets with correct comma and "and" word placement.
        case "$_nticketsf" in
            0|1);;
            2)
                _ticketsf="$(printf '%s ' $_ticketsf | \
	            sed -E 's/#([[:digit:]]|,)* $/and &/; s/ $//')"
                ;;
            *)
                _ticketsf="$(printf '%s, ' $_ticketsf | \
	            sed -E 's/#([[:digit:]]|,)*, $/and &/; s/, $//')"
                ;;
        esac
        eval ${1}f=\"${_ticketsf##' '}\"
}

# Check if a ticket is open (status: 2), unassigned, and not deleted.
checkticket() {
	eval "$(curl -s -u "$freshdeskapikey":X -X GET \
	    "$apiurl/$1?include=requester" | jq -r \
	    '"_agentid=\"\(.responder_id)\"
	    _status=\"\(.status)\"
	    _deleted=\"\(.deleted)\""')"

	if [ "$_status" -eq 2 ] && [ X"$_agentid" = Xnull ] && \
	    [ X"$_deleted" = Xnull ]; then
	    return 0
	else
	    return 1
	fi
}

updateticket() {
	# Input me!
	curl \
	    -s -u "$freshdeskapikey":X -X PUT \
	    -H 'Content-Type: application/json' \
	    -d "{
	         \"custom_fields\": {
	           \"cf_custom_field\": \"$cf_custom_field\",
	         },
	         \"status\": $status,
	         \"type\": \"$type\"
	       }" \
	    "$apiurl/$ticket" >/dev/null 2>&1
}

sendsms() {
	if [ "$nflag" -eq 0 ] || \
	    { [ "$auto" -eq 1 ] && [ "$nnflag" -eq 0 ]; }; then
	    return 0
	fi

	_messagestatus="$(curl \
	    -X POST \
	    -H "Authorization: Basic $clicksendapikey" \
	    -H 'Content-Type: application/json' \
	    -d "{
	        \"messages\": [
	          {
	            \"source\": \"php\",
	            \"body\": \"$1\",
	            \"to\": \"$number\"
	          }
	        ]
	       }" \
	    https://rest.clicksend.com/v3/sms/send 2>/dev/null | \
	    jq -r '.data.messages[].status')"

	case "$_messagestatus" in
	    SUCCESS)
	        logsuffix=', SMS sent'
	        ;;
	    INSUFFICIENT_CREDIT)
	        error log warning 'SMS failed due to lack of credit'
	        pflag=0
	        ;;
	    *)
	        error log warning "SMS failed for unknown reason: $_messagestatus"
	        pflag=0
	esac
}

# Run in a subshell and read from $tmpfile for
# communication with other instances of this script.
persist() (
	while sleep "$persistinterval"; do
	    # number of tickets
	    _ntickets="$(wc -l < "$tmpfile" | tr -d ' ')"
	    case "$_ntickets" in
	        ''|0)
	            break
	            ;;
	        *)
	            # unassigned tickets
	            _utickets=
	            # number of unassigned tickets
	            _nutickets=0
	            while read _line; do
	                if checkticket "$_line"; then
	                    _utickets="$_utickets $_line"
	                    _nutickets=$((_nutickets + 1))
	                else
	                    sed -i "/$_line/ d" "$tmpfile"
	                fi
	            done < "$tmpfile"
	            formatticket _utickets

	            case "$_nutickets" in
	                0)
	                    break
	                    ;;
	                1)
	                    _message="Ticket $_uticketsf is open and unassigned!"
	                    ;;
	                *)
	                    _message="Tickets $_uticketsf are open and unassigned!"
	                    ;;
	            esac
	            sendsms "$_message"
	            ;;
	    esac
	done
)

cflag=0
eflag=0
lflag=0
nflag=0
nnflag=0
pflag=0
while getopts cehi:lnp opt 2>/dev/null; do
	    case "$opt" in
	    c)
	        cflag=1
	        ;;
	    e)
	        eflag=1
	        ;;
	    h)
		cat <<- EOF
		usage: $0 [-cehlnnp] [-i SECONDS]
		Monitor, log, and perform actions on tickets created within the last minute.
		Intended to be ran every minute via cron(1).

		-c	Close tickets from known automated senders.
		-e	Print error messages to stderr.
		-h	Display this help and exit successfully. Implies \`-e'.
		-i	Specify the persist interval for SMS notifications.
		-l	Log to $logfile.
		-n	Notify via SMS when a ticket is created.
		-nn	Like above, but notify for automated senders as well.
		-p	Persist SMS notifications. Implies \`-n'.

		EOF
	        printf '%s\t%s\n' 'default persist interval:' \
	            "$persistinterval seconds"
		eflag=1
	        if [ -z "$number" ]; then
	            error warning '$number is absent so SMS functionality is disabled.'
	        else
	            printf '%s\t\t\t%s\n' 'Phone number:' "$number"
	        fi
	        if [ -z "$clicksendapikey" ]; then
	            error warning '$clicksendapikey is absent so SMS functionality is disabled.'
	        else
	            printf '%s\t\t%s\n' 'ClickSend API key:' 'present'
	        fi
	        if [ -z "$freshdesksubdomain" ]; then
		    error fatal '$freshdesksubdomain is absent'
	        else
	            printf '%s\t\t%s\n' 'Freshdesk subdomain:' \
	                "$freshdesksubdomain"
	        fi
	        if [ -z "$freshdeskapikey" ]; then
	            error fatal '$freshdeskapikey is absent'
	        else
	            printf '%s\t\t%s\n' 'Freshdesk API key:' 'present'
	        fi
	        exit 0
	        ;;
	    i)
	        # Only set if $OPTARG is an integer.
	        [ "$OPTARG" -eq "$OPTARG" ] && persistinterval="$OPTARG"
	        ;;
	    l)
	        lflag=1
	        ;;
	    n)
	        if [ "$nflag" -eq 0 ]; then
	            nflag=1
	        else
	            nnflag=1
	        fi
	        ;;
	    p)
	        nflag=1
	        pflag=1
	        ;;
	    esac
done

fatal=0

for cmd in curl jq; do
	if ! which "$cmd" >/dev/null 2>&1; then
	    error fatal "$cmd not found."
	    fatal=1
	fi
done

for var in number clicksendapikey; do
	if eval [ -z "\$$var" ]; then
	    nflag=0
	    nnflag=0
	    pflag=0
	    error log warning "\$$var is empty"
	fi
done

for var in freshdesksubdomain freshdeskapikey; do
	if eval [ -z "\$$var" ]; then
	    error "Fatal: \$$var is empty."
	    fatal=1
	fi
done

[ "$fatal" -eq 1 ] && exit 1

# Remove GNU `date -d' dependency for calculating last execution time (cron).
if date --version 2>/dev/null | grep GNU >/dev/null; then
	earlier="$(date -ud '1 minute ago' +%Y-%m-%dT%H:%M)"
	unixearlier="$(date -d '1 minute ago' +%s)"
else
	datefile=/tmp/"$(basename "$0")"-last_execute_time
	if [ -s "$datefile" ]; then
	    earlier="$(awk \
	        'NR == 1 && /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}/' \
	        "$datefile")"
	    unixearlier="$(awk 'NR == 2 && /[0-9]*/' "$datefile")"
	    date -u +%Y-%m-%dT%H:%M > "$datefile"
	    date +%s >> "$datefile"
	    if [ -z "$earlier" ] || [ -z "$unixearlier" ]; then
	        exit 1
	    fi
	else
	    date -u +%Y-%m-%dT%H:%M > "$datefile"
	    date -u +%s >> "$datefile"
	    chmod 640 "$datefile"
	    # Skip ticket processing in the first execution
	    # since we can not easily calculate the time one
	    # minute ago in the +%Y-%m-%dT%H:%M format string
	    exit 0
	fi
fi    

# Get all tickets updated in the last minute, and then
# filter out tickets not created within the last minute.
# (The above is done in two steps due to FreshDesk API
# insufficiencies; there is no way to filter by creation date.)
# If we don't filter out non recently created tickets, any action will set
# off the SMS alarm, including system auto closing tickets and auto replies.

# Then store all related information in dynamically created variables
# in order to get array-like functionality by using eval(1P).

eval "$(curl -s -u "$freshdeskapikey":X -X GET \
	"$apiurl?updated_since=$earlier&include=requester" | \
	jq --argjson unixearlier "$unixearlier" -r '.[] |
	select (.created_at | fromdateiso8601 > $unixearlier) |
	"tickets=\"$tickets \(.id)\"
	subject\(.id)=\"\(.subject)\"
	status\(.id)=\"\(.status)\"
	name\(.id)=\"\(.requester.name)\"
	email\(.id)=\"\(.requester.email)\"
	agentid\(.id)=\"\(.responder_id)\""')"

[ -z "${tickets##' '}" ] && exit 0

for ticket in $tickets; do
	# Ticket is not from an automated
	# sender unless otherwise specified.
	auto=0

	formatticket ticket
	for var in subject status name email agentid; do
	    eval $var=\$"$var$ticket"
	done

	case "$agentid" in
	    null) agent=unassigned;;
	    # Input me!
	    99999999999) agent='First_name Last_name';;
	    *) agent="an unknown agent ($agentid)";;
	esac

	case "$email" in
	    # Input me!
	    *@mycompany.com)
	        case "$agent" in
	            unassigned)
	                sendsms "Ticket $ticketf '$subject' has been submitted by $name."
	                ;;
	            "$name")
	                sendsms "Ticket $ticketf '$subject' was submitted by and assigned to $agent."
	                ;;
	            *)
	                sendsms "Ticket $ticketf '$subject' from $name was assigned to $agent."
	                ;;
	        esac
	        ;;
	    # Input me!
	    automated_sender@example.com)
	        auto=1
	        case "$agent" in
	            unassigned)
	                if [ "$cflag" -eq 1 ]; then
	                    # Input me!
	                    cf_custom_field=
	                    status=4    # Resolved
	                    type='Example'
	                    updateticket
	                    # Not sure about ClickSend, but other communication
	                    # API providers do not allow emails in the SMS body.
	                    sendsms "Ticket $ticketf closed due to example.com email."
	                    logmessage="closed due to $email email"
	                else
	                    sendsms "Example ticket $ticketf has been submitted by an automated sender."
	                    logmessage="no action taken in FreshDesk since \`-c' flag not specified"
	                fi
	                ;;
	            *)
	                sendsms "Example ticket $ticketf was assigned to $agent."
	                logmessage="no action taken in FreshDesk since assigned to $agent"
	                ;;
	        esac
	        ;;
	    *)
	        case "$agent" in
	            unassigned)
	                sendsms "Ticket $ticketf '$subject' has been submitted by $name (external)."
	                ;;
	            *)
	                sendsms "Ticket $ticketf '$subject' from $name (external) was assigned to $agent."
	                ;;
	        esac
	        ;;
	esac

	if [ "$pflag" -eq 1 ] && [ "$auto" -eq 0 ] && \
	    checkticket "$ticket"; then
	    logsuffix="$logsuffix, persisting"
	    if [ -s "$tmpfile" ]; then
	        printf '%s\n' "$ticket" >> "$tmpfile"
	    else
	        printf '%s\n' "$ticket" > "$tmpfile"
	        chmod 660 "$tmpfile"
	        persist &
	    fi
	fi

	if [ "$auto" -eq 1 ]; then
	    log "$logmessage"
	    continue
	fi

	# if the ticket does not have any comments/notes
	# (do not take action on tickets a human is working on)
	#if [ -z "$(curl \
	#    -s -u "$freshdeskapikey":X \
	#    -H 'Content-Type: application/json' \
	#    -X GET "$apiurl/$ticket/conversations" | \
	#    jq '.[]')" ]
	#then
	#    <action>
	#fi

	case "$agent" in
	    unassigned)
	        log "ticket unassigned"
	        ;;
	    *)
	        log "ticket assigned to $agent"
	        ;;
	esac
done

exit 0
