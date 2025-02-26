# Get It Back (Kup)

A KDE service menu to get files (or directories) back from Kup based backups.

## Warning

This currently does **not** support rsync(1) based Kup backups.

## Installation

Both files *should* go to `$HOME/.local/share/kio/servicemenus/` directory.

Both files *shall* be executable.

The bash script *might* be copied to any directory included in `$PATH` and will be preferred.

## Command line usage

```
get-it-back-kup [options] <file-to-restore-full-path>
```

Whereas options are:

```
-k, --kuprc, -c, --config <any-kup-config-file>
-C, --outdir <directory-to-restore-files-in>
-D, --dry-run
-S, --no-save (do not create backups of existing files before restore)
```

## TODOs and IDEAs

* support rsync based backups
* add aditional actions, such as 'run in konsole', show list of files before restoring
* add support for remote backups (if Kup can do this)
* add / use an install script
* give wife a hug
