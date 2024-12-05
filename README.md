# berp (working title)

Small script to automate branch names and commits following taskflow management guidelines
It follows the https://github.com/len-foss/bidoolgit/ approach.

## Requirements

The script uses bash. 
The functions are not compatible with e.g. vanilla zsh and need to be rewritten to support other shells.
To work around this in non bash environments, use it as a subscript.

## Install

You can simply move the `er.sh` script to your path.
To keep it under version control in a simple way, you can create a file like `er` (changing the path as appropriate) to your path, which just transfers the command arguments.

## Usage:

The following assume the script is present under the `er` alias.

```er b```
will simply create a branch based on the current branch and append the ticket and its number.
For example, if the current branch is `17.0-staging`, it will switch to branch `17.0-staging-ticket-222599`.

```er c "optional message"```
will commit the staged files using the message of the form `[ticket-222599] folder1, folder2: optional message`, where:
- [ticket-222599] is taken using the `$TICKET` variable.
- `folder1, folder2` are any folder in `$FOLDER` (by default `custom`) that has been modified, if any

The `$TICKET` variable is parsed from the branch name if possible, and otherwise it asks for input.