# NAME

eq

# SYNOPSIS

`eq [OPTION]... <expressions>...`

# DESCRIPTION

A utility meant to more easily query the explorer output of cdist.

Arguments that can be used are:

`-r <report fields>`
Define which explorer information should be reported for the systems matching the expressions.
Multiple explorers can be defined separated which comma's.

`-H <hosts>`
Specify one or more hosts to run the expressions on. Multiple hosts can be specified
separated by comma's.

`-t <tags>`
Use cdist inventory tags to specify the hosts to run the expressions on. Multiple tags can
be defined, separated by comma's. When specifying multiple tags, any of them will match.

`-T <tags>`
Use cdist inventory tags to specify the hosts to run the expressions on. Multiple tags can
be defined, separated by comma's. When specifying multiple tags, all of them will match.

`-j`
Output the resulting information in json format.

`-w`
Output the resulting information in html format.

# EXPRESSIONS

An expression consists of one or more expression combined with logical operators. The
expression evaluation is rather limited, which requires entering specific precedence.

A single expression looks like:

`<explorer file name> <operator> <operand>`

The explorer file name references the file in the explorer directory for the host.

The operator can be one of:

* contains file contains string anywhere
* eq        numerical exact match
* gt        numerical greater than
* ge        numerical greater or equall than
* lt        numerical less than
* le        numerical less or equall than

Multiple expression can be combined by logical operators. Supported operators are:

*  and       both are true
*  or        either or are true

When using multiple expressions, square brackets need to be used in order to define
precedence.

Two expressions:

`[ expression1 ] and [ expression2 ]`

Three expressions:

`[ expression1 ] and [ [ expression2 ] or [ expression3 ] ]

# EXPLORER FILENAME MODIFIERS

Explorer files can have multiple lines or multiple values on a single line. In order
to assist with this, modifiers can be used in reporting fields or expressions when
specifying an explorer file.

The basic syntax is:

`<explorer file>:<modifier>:<modifier>..`

The following modifiers are supported:

`f[nr]`

With using space as a seperator, output only field number <nr>.

`~[word]`

Only output the line in the explorer containing the word <word>. Grep is used for this,
so basic grep expressions can be used.

# EXAMPLES

Report fqdn and os version for all debian systems with a version lower than 12

`eq -r fqdn,os_version [ os = debian ] and [ os_version lt 12 ]`

Report fqdn for all systems where the package list explorer contains nginx.

`eq -r fqdn packages contains nginx`

Report fqdn and version of bc for all systems where the package list explorer contains bc.

`eq -r fqdn,packages:~^bc:f2 packages:f1 contains bc

# AUTHOR

Written by Mark Verboom

# REPORTING BUGS

Prefferably by opening an issue on the github page.

# COPYRIGHT

Copyright  ©  2014  Free Software Foundation, Inc.  License GPLv3+: GNU
GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free  to  change  and  redistribute  it.
There is NO WARRANTY, to the extent permitted by law.
