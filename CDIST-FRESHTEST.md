# NAME

cdist-freshtest

# SYNOPSIS

`cdist-freshtest [OPTION]... NAME`

# DESCRIPTION

Proves that cdist can configure a brand new host, and that running it again
changes nothing.

It deploys a throwaway container with the `ct` helper, which also runs the full
configuration on it, and then asks cdist itself:

```
runcdist -d -v NAME.LNW.VERBOOM.NET
```

A dry run of a converged host processes **no** objects. Everything that cdist
still wants to process here is by definition not idempotent: the object was
created again, a parameter does not match, a file is rewritten on every run.
Those objects are listed, grouped by type. The container is destroyed again
afterwards.

This is the one thing the offline tools (`cdist-audit`, `cdist-render`) cannot
tell you: whether the configuration actually converges on a real, empty host.

# OPTIONS

`-k`, `--keep`
Keep the container and its logs, for inspection.

`-p`, `--probe-only`
Do not deploy anything and do not destroy anything: only probe the host named
on the command line. Use this on an existing host.

`-s`, `--second-run`
Run the real configuration a second time after the probe and probe again. A
brand new host can legitimately not be converged after the first run, for
example because the inventory (and therefore the host's tags) is only generated
afterwards - this option shows whether the second run fixes that.

`-r`, `--retries N`
How often to retry the deploy when the new host never becomes reachable
(default 1). A retry destroys whatever may have been created first.

`-t`, `--timeout N`
Seconds per step (default 1800), so a hanging deploy or cdist run does not hang
the test forever.

`-q`, `--quiet`
Only print the verdict and the log path.

`-V`, `--version`, `-h`, `--help`
The usual.

# ENVIRONMENT

`CDIST_FRESHTEST_DOMAIN` (default `lnw.verboom.net`), `CDIST_FRESHTEST_CT`
(default `ct`), `CDIST_FRESHTEST_RUN` (default `runcdist`),
`CDIST_FRESHTEST_WORK` (default `/tmp/cdist-freshtest`).

# WHEN THE DEPLOY FAILS

`ct deploy` runs cdist on the container immediately after creating it. That
regularly fails while the name does not resolve yet or sshd is still starting,
even though the container itself is fine. So a failed deploy is not fatal here:
if the host answers over ssh, cdist-freshtest configures it itself and carries
on with the test (the verdict says so). If the host never answers, the test
retries (see `--retries`) and only then gives up - always destroying what was
created.

# WHAT IT CREATES AND REMOVES

Everything `ct deploy` does, and `ct destroy` undoes:

* a container on the Proxmox host, from the container template;
* an address from the ipam;
* an entry in the ssh config of the hosts that need it;
* explorer data and inventory tags for the new host (through the normal
  `runcdist` postrun steps);
* on destroy: the container is stopped and removed, the address is released and
  the explorer data is moved to `explore.decomissioned` by `ct destroy`;
  cdist-freshtest additionally removes the **inventory entry** that the runcdist
  postrun step generated for the test host (kept in the work directory), because
  `ct destroy` leaves it behind and a host that does not exist any more should
  not stay in the inventory;
* cdist's ssh accepts new host keys, so the test host ends up in the cdist
  user's `known_hosts`; that entry is removed again as well, otherwise reusing
  the same test name fails with a changed host key.

A test therefore needs the same access as a normal `ct deploy` and should not
be run in parallel with itself under the same name.

# EXIT STATUS

`0` when the host is idempotent (and no error occurred), `1` otherwise.

# EXAMPLES

A complete test, including the removal of the container:

```
cdist-freshtest wptest-01
```

Keep a failing container around to look at it:

```
cdist-freshtest --keep wptest-01
ssh wptest-01.lnw.verboom.net
ct destroy wptest-01
```

Check whether an existing host is converged:

```
cdist-freshtest --probe-only --keep avon.lnw.verboom.net
```

See whether a brand new host converges by itself:

```
cdist-freshtest --second-run wptest-01
```

# OUTPUT

```
=== deploy: ct deploy wptest-01
deploy -> exit 0 in 74s

=== probe idempotent: runcdist -d -v wptest-01.lnw.verboom.net
probe idempotent -> exit 0 in 21s
probe idempotent: 3 object(s) would still change, 0 error(s)
      2 __file
      1 __apt_update_index
cdist-freshtest wptest-01: NOT-IDEMPOTENT (wptest-01.lnw.verboom.net)
log: /tmp/cdist-freshtest/wptest-01.log
```

Everything (including the full cdist log of every step) is collected in
`$CDIST_FRESHTEST_WORK/NAME.log`; the dry run output of each probe is kept next
to it as `NAME.<phase>.log`.

# LIMITS

* It reports objects that are not idempotent, it does not say why - the object
  name and the cdist log are the starting point for that.
* A host that is not idempotent because of deliberate periodic work (for
  example an `__apt_update_index` that runs every time) will always be
  reported. That is what the object list is for.

# SEE ALSO

`ct`, `runcdist`, `cdist-audit`, `cdist-render`
