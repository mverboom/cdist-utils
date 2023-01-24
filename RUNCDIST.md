# NAME

runcdist

# SYNOPSIS

`runcdist [OPTION]... <arguments>...`

# DESCRIPTION

A wrapper around the cdist software to make running cdist easier. This wrapper
relies on the inventory function of cdist.

Arguments that can be used are:

`-c`
Source a specific cdistrc file before starting cdist.

`-v`
Make output more verbose. Each `-v` increases the verbosity.

`-q`
Make output quiet.

`-p`
Run the configuration of hosts in parallel.

`-P`
Timestamp log messages with the current local date and time in the format: YYYYMMDDHHMMSS.us.

`-m`
Mail the result of the command to the email address specified in the configuration file.

`-o <manifest>`
Overrule running any generic manifest and only run the specified manifest.

`-t`
All arguments are to be considered tags. All tags need to be present for a host to be
selected. Run cdist with resulting hosts.

`-T`
All arguments are to be considered tags. Any of the tags need to be present for a host to 
be selected. Run cdist with resulting hosts.

`-l`
All arguments are to be considered tags. All tags need to be present for a host to be
selected. List all resulting hosts.

`-T`
All arguments are to be considered tags. Any of the tags need to be present for a host to 
be selected. List all resulting hosts.

`-a`
Run manifest(s) on all hosts in inventory.

`-d`
Dry run, don't execute types (will run manifests)

`-x`
Run in debug mode

# CONFIGURATION FILE

Runcdist will see if there is an `~/.runcdist.ini` configuration file. If this file
exists, it is expected to be in ini style format. The following headings are recognized.

`[main]`

This section has the following settings:

`parrallel`

Default the number of CPU's will be used as the value for parrallellism when running
with the -p option. Setting parrallel will override this.

`cdistrc`

The default cdistrc file is `~/.cdistrc`. Setting this option will use the value as the
default cdistrc file to source.

`mail`

This option points to a mail address. This option is used when the -m commandline option is in effect.

`[prerun]`
`[postrun]`

These sections can be used to specify commands that need to be run before or after
each cdist action.

Item name can be arbitrary and will be sorted. The value of each item will be treated as
a command that will be run. There are variables that can optionally
be used in the commands:
`$CDISTRET`: The return value of the cdist command
`${CDISTARGS[]}': Array of the options the runcdist command was started with

# EXAMPLES

Run cdist for all systems tagged as server

`runcdist -t server`

Run cdist with the exim manifest on all systems tagged as mailer and be verbose.

`rundist -v -o exim -t mailer`

Config file to set default parrallellism to 5 and run `cdist-inventory` after each
run.
```
[main]
parrallel=5

[postrun]
step1=cdist-inventory
```

# AUTHOR

Written by Mark Verboom

# REPORTING BUGS

Prefferably by opening an issue on the github page.

# COPYRIGHT

Copyright  ©  2014  Free Software Foundation, Inc.  License GPLv3+: GNU
GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free  to  change  and  redistribute  it.
There is NO WARRANTY, to the extent permitted by law.
