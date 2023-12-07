<!--
SPDX-FileCopyrightText: 2023 Deutsche Telekom AG

SPDX-License-Identifier: CC0-1.0
-->

# ENI tinted Kong

This is a mirrored repository of [Kong](https://github.com/Kong/kong). All branches and commits are automatically replicated by Gitlab. **Do not edit any branches beside mentioned ones.**

**NOTE** Always take care of the MTR_TARGET_TAG variable naming!

## How to edit/implement files?
We want to implement and extend plugins to our needs. Therefore we need a way to implement our changes but maintain the ability to update changes from Kong.\
Therefore we use the following approach: all edits are solely done in release/eni-prefixed branches.\

This means master has a eni-master equivalent.\
Releases have a eni-release/x.x.x.x equivalent and released as x.x.x.x. The final x indicates the ENI-Version.

## Hot to build release?
Create a release branch e.g. eni-release/2.8.1.4 from the eni-release/2.8.1.x branch. \
If not set in gitlab-ci: Prepare a final release with setting MTR_TARGET_TAG to the proper image version, e.g. 2.8.1.4. \
Increase the ENI version in kong/meta.lua. \
Create a tag with the release name, e.g. 2.8.1.4. \
Build the image by triggering the build job. \
Delete the eni-release/2.8.1.4 branch.

## How to update our sources?
Release branches should not require updates from remote.\
Eni-master can be updated via merge from master. This way we keep changes from us included and simultaneously updated.

**NOTE:** There are a lot of merge conflicts coming from 2.8.1 onwards master. This means we need to reapply our changes on eni-master in a later stage.

## How to built hotfixes?
There are two reasons to create a hotfix:
1. If we have a bug in our code, we simply release e.g. eni-2.8.1.x version. Even if we break semver. \
2. Bugfix-release from Kong: we simply create an release/eni-2.8.x version branch tag eni-2.8.1 as source. Merge new changes into the new branch.

## Code of Conduct

This project has adopted the [Contributor Covenant](https://www.contributor-covenant.org/) in version 2.1 as our code of conduct. Please see the details in our [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). All contributors must abide by the code of conduct.

By participating in this project, you agree to abide by its [Code of Conduct](./CODE_OF_CONDUCT.md) at all times.

## Licensing

This project follows the [REUSE standard for software licensing](https://reuse.software/).
Each file contains copyright and license information, and license texts can be found in the [./LICENSES](./LICENSES) folder. For more information visit https://reuse.software/.

### REUSE

For a comprehensive guide on how to use REUSE for licensing in this repository, visit https://telekom.github.io/reuse-template/.   
A brief summary follows below:

The [reuse tool](https://github.com/fsfe/reuse-tool) can be used to verify and establish compliance when new files are added. 

For more information on the reuse tool visit https://github.com/fsfe/reuse-tool.

**Check for incompliant files (= not properly licensed)**

Run `pipx run reuse lint`

**Get an SPDX file with all licensing information for this project (not for dependencies!)**

Run `pipx run reuse spdx`

**Add licensing and copyright statements to a new file**

Run `pipx run reuse annotate -c="<COPYRIGHT>" -l="<LICENSE-SPDX-IDENTIFIER>" <file>`

Replace `<COPYRIGHT>` with the copyright holder, e.g "Deutsche Telekom AG", and `<LICENSE-SPDX-IDENTIFIER>` with the ID of the license the file should be under. For possible IDs see https://spdx.org/licenses/.

**Add a new license text**

Run `pipx run reuse download --all` to add license texts for all licenses detected in the project.

