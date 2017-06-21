# baseline

Baseline is a tool for running test scripts that have deterministic
standard output. The test scripts can be written in any language supported
by the system running the tests. Baseline is designed to work on \*nix
environments, and with modifications, may work on other environments.

Usage:
 * To create a baseline of a script with deterministic output:
   `> ./baseline -b [script]`
   Creates [script].baseline

* To test a script with an existing baseline:
  `> ./baseline [script]`
  Runs [script], captures its output, and compares against [script].baseline

## Options

```
-b                  Update/create baselines
-q                  Quiet: do not print diff/stderr on failures
-s                  Silent: do not print any status during testing
-r                  Recursively scan any given directories for tests
-f                  Adds all baseline context to any diff
-h, -?, --help      Show help
```

## Self-Tests

Self-tests for the baseline tool live within [regress/](./regress/).
To run those tests, simply run:
```
./baseline regress/
```
