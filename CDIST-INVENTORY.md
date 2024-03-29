# NAME

cdist-inventory

# SYNOPSIS

`cdist-inventory`

# DESCRIPTION

A script that generates the cdist inventory based on generated explorer output.

The command expects the following environment variables to be set:

`CDIST_EXPLORE`
This variable points to the directory where explorer output is stored for
all systems.

`CDIST_INVENTORY`
This variable points to the directory where the cdist inventory is stored.
Cdist default uses `~/.cdist/inventory` but as this script is destructive of
the content the variable points to, it needs to be specified.

The script expects a configuration file at the following location:

`~/.cdist-inventory.ini`

When running the script, the configuration file is parsed and the rules are applied
to all hosts in the explorer directory. Based on the rules and the available
explorer output, the inventory directory is repopulated.

It is also possible to add manual tags. This requires the following directory
to be present:

`~/cdist-inventory`

Like an explorer direcory, this directory contains files which match the labels
in the configuration file. The content of the file consists of the names of
hosts. Compared to the explorer directory matching on this directory only 
generates a true or false outcome.

# CONFIGURATION FILE

The configuration file is in .ini style format.

The name of each section in the file refers to the name of an explorer file
containing output. The content of the section contains one or more rules to be
applied to the content of the explorer output.

Each rule can consist of one or more statements concatenated by the +
symbol. The output of each statement will be concactenated into the tag
name.

The statements are composed of two parts:

* Operator
* Arguments

The two parts are separated by a `:`.

The following operators are available.

## if

The if operator requires an argument containing of two parts:

* search string
* tag value

The two parts of the argument need to be seperated by a `=`.

The search string is applied to the content of the explorer. If the search string
matches the explorer content, the tag is added to the inventory entry for the host. If the search string starts with an !, the tag is added if the search string does not match.

If the tag starts with a ~ and the search is not negated, the part after the
~ will be seen as an expression that is passed to sed. The input to sed will
be the match of the search string. With this option, matched values can be
transformed before being used as the tag value.

When matching to a file in the `cdist-inventory` directory, the search string is not used and can be an arbitrary word in the if expression. The search string will always be the system hostname.

## content

Content requires one argument. The following arguments are available:

* copy
Copies to the content of the explorer as a tag to the hosts inventory entry.

When matching to a file in the `cdist-inventory` directory, the content will be true if the host is present and false if it isn't.

* ~

If the argument starts with a ~, the argument will be interpreted as a sed
filter. The filter will get the content of the explorer as input and the
result will be the tag value.

## static

Static requires one argument. The argument is the value that will be
used as the tag.

# FILES

`~/.cdist-inventory.ini`

Configuration file

# EXAMPLES

An example configuration file is included. This file assumes the following
explorers exists and generate output:

* network: generates the name of the network a system lives in.
* distro: the name of the distribution installed on the system.
* packages: a list of packages installed on the system.
* offline: a referece to a file with hostnames. The file contains hosts that are always offline.
* vlan: numeric value of the vlan the system lives in.

The configuration will do the following:

* Copy the content of the explorer file `network` as a tag for each host.
* If the distribution contains the word `debian` it will add the tag `dpkg` to the inventory of each host.
* If the list of packages contains `xrdp` it will add the tag `rdp` to the inventory of each host.
* If the hosts does not exist in the file offline, it will be given the tag `online`.
* The vlan number is prepended by the work vlan and used as a tag.

# AUTHOR

Written by Mark Verboom

# REPORTING BUGS

Prefferably by opening an issue on the github page.

# COPYRIGHT

Copyright  ©  2014  Free Software Foundation, Inc.  License GPLv3+: GNU
GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free  to  change  and  redistribute  it.
There is NO WARRANTY, to the extent permitted by law.
