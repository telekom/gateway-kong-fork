# ENI tinted Kong

This is a mirrored repository of [Kong](https://github.com/Kong/kong). All branches and commits are automatically replicated by Gitlab. **Do not edit any branches beside mentioned ones.**

## How to edit/implement files?
We want to implement and extend plugins to our needs. Therefore we need a way to implement our changes but maintain the ability to update changes from Kong.\
Therefore we use the following approach: all edits are solely done in eni-prefixed branches.\

This means master has a eni-master equivalent.\
Release tags have a eni-x.x.x equivalent.

## How to update our sources?
Release branches should not require updates from remote.\
Eni-master can be updated via merge from master. This way we keep changes from us included and simultaneously updated.

## [Not verified] How to built hotfixes?
There are two reasons to create a hotfix:
1. If we have a bug in our code, we simply release e.g. eni-2.8.1.x version. Even if we break semver. \
2. Bugfix-release from Kong: we simply create an eni-2.8.x version branch and add our changes to it.

